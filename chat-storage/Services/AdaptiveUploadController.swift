//
//  AdaptiveUploadController.swift
//  chat-storage
//

import Foundation

struct AdaptiveUploadController {
    enum ServerState: Equatable {
        case normal
        case slowDown
        case pause
        case error
    }

    struct Observation: Equatable {
        let ackRTT: TimeInterval?
        let windowBytes: Int
        let windowDuration: TimeInterval
        let serverState: ServerState
        let recommendedChunkSize: Int?
        let recommendedAckWindowBytes: Int?
        let retryAfterMs: Int?
        let isOffsetBehind: Bool
        let socketWriteWaitRatio: Double
        let didTimeout: Bool
        let didDisconnect: Bool
    }

    struct Decision: Equatable {
        let chunkSize: Int
        let ackWindowBytes: Int
        let ackTimeout: TimeInterval
        let isCoolingDown: Bool
        let shouldPause: Bool
        let retryAfterMs: Int?
    }

    private static let minimumChunkSize = 32_768
    private static let initialChunkSize = 65_536
    private static let maximumChunkSize = 524_288
    private static let minimumAckWindowBytes = 1_048_576
    private static let maximumAckWindowBytes = 8_388_608
    private static let minimumGoodput = 65_536.0

    private var localChunkSize = Self.initialChunkSize
    private var localAckWindowBytes = Self.minimumAckWindowBytes
    private var consecutiveHealthyWindows = 0
    private var cooldownHealthyWindowsRemaining = 0
    private var hasRTTMeasurement = false
    private var hasGoodputMeasurement = false

    private(set) var smoothedRTT: TimeInterval = 0
    private(set) var smoothedGoodput: Double = 0

    init(initialChunkSize: Int? = nil, initialAckWindowBytes: Int? = nil) {
        if let initialChunkSize {
            localChunkSize = min(
                Self.maximumChunkSize,
                max(Self.minimumChunkSize, initialChunkSize)
            )
        }
        if let initialAckWindowBytes {
            localAckWindowBytes = min(
                Self.maximumAckWindowBytes,
                max(Self.minimumAckWindowBytes, initialAckWindowBytes)
            )
        }
    }

    var currentDecision: Decision {
        makeDecision(
            recommendedChunkSize: nil,
            recommendedAckWindowBytes: nil,
            shouldPause: false,
            retryAfterMs: nil
        )
    }

    mutating func record(_ observation: Observation) -> Decision {
        let metricsAreValid = hasValidMetrics(observation)
        let exceedsRTTThreshold = metricsAreValid && isRTTAbnormal(observation.ackRTT)
        if metricsAreValid {
            updateMetrics(with: observation)
        }

        let shouldDecrease = shouldDecrease(
            for: observation,
            metricsAreValid: metricsAreValid,
            exceedsRTTThreshold: exceedsRTTThreshold
        )
        if shouldDecrease {
            decreaseParameters()
        }

        if observation.serverState == .pause || hasInvalidRecommendation(observation) {
            return makeDecision(
                recommendedChunkSize: observation.recommendedChunkSize,
                recommendedAckWindowBytes: observation.recommendedAckWindowBytes,
                shouldPause: true,
                retryAfterMs: observation.retryAfterMs.map { max(0, $0) }
            )
        }

        if !shouldDecrease && isHealthy(
            observation,
            metricsAreValid: metricsAreValid,
            exceedsRTTThreshold: exceedsRTTThreshold
        ) {
            recordHealthyWindow()
        } else if !shouldDecrease {
            consecutiveHealthyWindows = 0
        }

        return makeDecision(
            recommendedChunkSize: observation.recommendedChunkSize,
            recommendedAckWindowBytes: observation.recommendedAckWindowBytes,
            shouldPause: false,
            retryAfterMs: nil
        )
    }

    private mutating func updateMetrics(with observation: Observation) {
        if let latestRTT = observation.ackRTT {
            if hasRTTMeasurement {
                smoothedRTT = 0.8 * smoothedRTT + 0.2 * latestRTT
            } else {
                smoothedRTT = latestRTT
                hasRTTMeasurement = true
            }
        }

        let latestGoodput = Double(observation.windowBytes) / observation.windowDuration
        if hasGoodputMeasurement {
            smoothedGoodput = 0.75 * smoothedGoodput + 0.25 * latestGoodput
        } else {
            smoothedGoodput = latestGoodput
            hasGoodputMeasurement = true
        }
    }

    private func hasValidMetrics(_ observation: Observation) -> Bool {
        guard let latestRTT = observation.ackRTT,
              latestRTT.isFinite,
              latestRTT >= 0,
              observation.windowBytes > 0,
              observation.windowDuration.isFinite,
              observation.windowDuration > 0,
              observation.socketWriteWaitRatio.isFinite,
              (0...1).contains(observation.socketWriteWaitRatio) else {
            return false
        }

        let latestGoodput = Double(observation.windowBytes) / observation.windowDuration
        return latestGoodput.isFinite && latestGoodput > 0
    }

    private func hasInvalidRecommendation(_ observation: Observation) -> Bool {
        let invalidChunk = observation.recommendedChunkSize.map {
            $0 < Self.minimumChunkSize
        } ?? false
        let invalidAckWindow = observation.recommendedAckWindowBytes.map {
            $0 < Self.minimumAckWindowBytes
        } ?? false
        return invalidChunk || invalidAckWindow
    }

    private func isRTTAbnormal(_ latestRTT: TimeInterval?) -> Bool {
        guard hasRTTMeasurement,
              let latestRTT,
              latestRTT.isFinite,
              latestRTT >= 0 else {
            return false
        }
        return latestRTT > max(2 * smoothedRTT, 0.8)
    }

    private func shouldDecrease(
        for observation: Observation,
        metricsAreValid: Bool,
        exceedsRTTThreshold: Bool
    ) -> Bool {
        !metricsAreValid
            || observation.serverState == .slowDown
            || observation.serverState == .error
            || observation.isOffsetBehind
            || observation.didTimeout
            || observation.didDisconnect
            || exceedsRTTThreshold
            || observation.socketWriteWaitRatio > 0.4
    }

    private func isHealthy(
        _ observation: Observation,
        metricsAreValid: Bool,
        exceedsRTTThreshold: Bool
    ) -> Bool {
        metricsAreValid
            && observation.serverState == .normal
            && !observation.isOffsetBehind
            && !observation.didTimeout
            && !observation.didDisconnect
            && !exceedsRTTThreshold
            && observation.socketWriteWaitRatio <= 0.4
            && (observation.retryAfterMs ?? 0) <= 0
    }

    private mutating func decreaseParameters() {
        localChunkSize = max(Self.minimumChunkSize, localChunkSize / 2)
        localAckWindowBytes = max(Self.minimumAckWindowBytes, localAckWindowBytes / 2)
        consecutiveHealthyWindows = 0
        cooldownHealthyWindowsRemaining = 3
    }

    private mutating func recordHealthyWindow() {
        if cooldownHealthyWindowsRemaining > 0 {
            cooldownHealthyWindowsRemaining -= 1
            consecutiveHealthyWindows = 0
            return
        }

        consecutiveHealthyWindows += 1
        guard consecutiveHealthyWindows >= 2 else {
            return
        }

        localChunkSize = min(Self.maximumChunkSize, localChunkSize * 2)
        localAckWindowBytes = min(Self.maximumAckWindowBytes, localAckWindowBytes * 2)
        consecutiveHealthyWindows = 0
    }

    private func makeDecision(
        recommendedChunkSize: Int?,
        recommendedAckWindowBytes: Int?,
        shouldPause: Bool,
        retryAfterMs: Int?
    ) -> Decision {
        let invalidChunk = recommendedChunkSize.map {
            $0 < Self.minimumChunkSize
        } ?? false
        let invalidAckWindow = recommendedAckWindowBytes.map {
            $0 < Self.minimumAckWindowBytes
        } ?? false
        let hasInvalidRecommendation = invalidChunk || invalidAckWindow
        let chunkUpperBound = recommendedChunkSize.map {
            min(Self.maximumChunkSize, max(Self.minimumChunkSize, $0))
        } ?? Self.maximumChunkSize
        let ackWindowUpperBound = recommendedAckWindowBytes.map {
            min(Self.maximumAckWindowBytes, max(Self.minimumAckWindowBytes, $0))
        } ?? Self.maximumAckWindowBytes
        let effectiveChunkSize = hasInvalidRecommendation
            ? Self.minimumChunkSize
            : min(localChunkSize, chunkUpperBound)
        let effectiveAckWindowBytes = hasInvalidRecommendation
            ? Self.minimumAckWindowBytes
            : min(localAckWindowBytes, ackWindowUpperBound)

        return Decision(
            chunkSize: effectiveChunkSize,
            ackWindowBytes: effectiveAckWindowBytes,
            ackTimeout: timeout(forAckWindowBytes: effectiveAckWindowBytes),
            isCoolingDown: cooldownHealthyWindowsRemaining > 0,
            shouldPause: shouldPause || hasInvalidRecommendation,
            retryAfterMs: hasInvalidRecommendation ? max(1, retryAfterMs ?? 250) : retryAfterMs
        )
    }

    private func timeout(forAckWindowBytes ackWindowBytes: Int) -> TimeInterval {
        guard hasRTTMeasurement, hasGoodputMeasurement else {
            return 30
        }

        let transferTime = Double(ackWindowBytes) / max(smoothedGoodput, Self.minimumGoodput)
        return min(60, max(10, 4 * smoothedRTT + 2 * transferTime))
    }
}
