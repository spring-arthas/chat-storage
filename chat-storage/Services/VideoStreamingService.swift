//
//  VideoStreamingService.swift
//  chat-storage
//
//  Created by HLJY on 2026/3/17.
//

import Foundation

/// 视频流服务。
/// 为了避免和主业务连接的帧处理互相干扰，每一次视频流请求都使用独立的 SocketManager。
final class VideoStreamingService {
    private let socketManager: SocketManager
    private let targetHost: String
    private let targetPort: UInt32

    private let stateLock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var isCancelled = false
    private var hasCompleted = false
    private var hasDisconnectedSocket = false

    init(host: String, port: UInt32 = 10088) {
        self.targetHost = host
        self.targetPort = port
        self.socketManager = SocketManager()
    }

    convenience init() {
        let (host, _) = SocketManager.shared.getCurrentServer()
        self.init(host: host)
    }

    deinit {
        cancel()
    }

    func startCustomVideoStreaming(
        fileId: Int64,
        startOffset: Int64,
        delegate: VideoStreamLoaderDelegate
    ) async throws {
        try await connectIfNeeded()

        let taskId = UUID().uuidString
        let request: [String: Any] = [
            "fileId": fileId,
            "taskId": taskId,
            "startOffset": startOffset,
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            throw DirectoryError.invalidData
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                storeContinuation(continuation)
                var receivedSize = startOffset

                let types: Set<FrameTypeEnum> = [.metaFrame, .dataFrame, .endFrame, .fileResponse, .ackFrame]
                socketManager.registerStreamHandler(for: types) { [weak self] frame in
                    guard let self = self else { return false }

                    if self.currentlyCancelled {
                        self.complete(.failure(CancellationError()))
                        return false
                    }

                    switch frame.type {
                    case .ackFrame, .metaFrame:
                        if let jsonString = String(data: frame.data, encoding: .utf8),
                           let data = jsonString.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                            if let status = dict["status"] as? String, (status == "error" || status == "fail") {
                                let msg = dict["message"] as? String ?? "未知错误"
                                let error = DirectoryError.serverError(code: -1, message: msg)
                                delegate.didFail(with: error)
                                self.complete(.failure(error))
                                return false
                            }

                            if let size = Self.int64Value(from: dict["fileSize"]) {
                                delegate.didReceiveContentInfo(totalSize: size, mimeType: "video/mp4")

                                let readyAck: [String: Any] = ["taskId": taskId, "status": "ready"]
                                if let readyData = try? JSONSerialization.data(withJSONObject: readyAck) {
                                    let readyFrame = Frame(type: .ackFrame, data: readyData, flags: 0x00)
                                    try? self.socketManager.sendFrame(readyFrame)
                                }
                            }
                        }
                        return true

                    case .dataFrame:
                        let data = frame.data
                        let range = receivedSize..<(receivedSize + Int64(data.count))
                        delegate.didReceiveVideoData(data, range: range)
                        receivedSize += Int64(data.count)
                        return !self.currentlyCancelled

                    case .endFrame:
                        delegate.didFinishLoading()
                        self.complete(.success(()))
                        return false

                    case .fileResponse:
                        if let dict = try? FrameParser.decodeAsDictionary(frame),
                           let code = dict["code"] as? Int, code != 200 {
                            let msg = dict["message"] as? String ?? "Stream Fail"
                            let error = DirectoryError.serverError(code: code, message: msg)
                            delegate.didFail(with: error)
                            self.complete(.failure(error))
                            return false
                        }
                        return true

                    default:
                        return true
                    }
                }
                
                // 已经注册好 handler 后，再发送请求帧，防止竞态条件导致第一包响应被丢弃
                do {
                    let requestFrame = Frame(type: .metaFrame, data: requestData, flags: 0x00)
                    try self.socketManager.sendFrame(requestFrame)
                } catch {
                    self.complete(.failure(error))
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        stateLock.lock()
        if hasCompleted || isCancelled {
            stateLock.unlock()
            return
        }

        isCancelled = true
        let continuation = self.continuation
        self.continuation = nil
        hasCompleted = true
        let shouldDisconnect = !hasDisconnectedSocket
        hasDisconnectedSocket = true
        stateLock.unlock()

        if shouldDisconnect {
            disconnectSocket()
        }
        continuation?.resume(throwing: CancellationError())
    }

    private var currentlyCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCancelled
    }

    private func storeContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        stateLock.lock()
        self.continuation = continuation
        stateLock.unlock()
    }

    private func complete(_ result: Result<Void, Error>) {
        stateLock.lock()
        guard !hasCompleted else {
            stateLock.unlock()
            return
        }

        hasCompleted = true
        let continuation = self.continuation
        self.continuation = nil
        let shouldDisconnect = !hasDisconnectedSocket
        hasDisconnectedSocket = true
        stateLock.unlock()

        if shouldDisconnect {
            disconnectSocket()
        }

        guard let continuation else { return }
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func connectIfNeeded() async throws {
        if socketManager.connectionState == .connected {
            return
        }

        let host = self.targetHost
        let port = self.targetPort
        await MainActor.run {
            // 直接调用 connect()，不通过 switchConnection()，
            // 避免 switchConnection 内部的 Thread.sleep(0.1) 阻塞主 RunLoop。
            // VideoStreamingService 的 SocketManager 始终是全新实例，无需先 disconnect。
            self.socketManager.connect(host: host, port: port)
        }

        var attempts = 0
        while attempts < 50 {
            switch socketManager.connectionState {
            case .connected:
                return
            case .error(let message):
                throw DirectoryError.serverError(code: -1, message: message)
            default:
                attempts += 1
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        throw SocketError.timeout
    }

    private func disconnectSocket() {
        // 同步断开，避免旧连接与新连接并存导致内存叠加
        socketManager.disconnect(notifyUI: false)
    }

    private static func int64Value(from value: Any?) -> Int64? {
        switch value {
        case let intValue as Int64:
            return intValue
        case let intValue as Int:
            return Int64(intValue)
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string)
        default:
            return nil
        }
    }
}
