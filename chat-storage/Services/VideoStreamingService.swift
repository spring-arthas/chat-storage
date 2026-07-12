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
    private let streamTimeoutSeconds: TimeInterval

    private let stateLock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var isCancelled = false
    private var hasCompleted = false
    private var hasDisconnectedSocket = false
    private var activeStreamHandlerToken: UUID?
    private var requestGeneration: UInt64 = 0

    init(host: String, port: UInt32 = 10088, streamTimeoutSeconds: TimeInterval = 45.0) {
        self.targetHost = host
        self.targetPort = port
        self.streamTimeoutSeconds = streamTimeoutSeconds
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
        length: Int64,
        delegate: VideoStreamLoaderDelegate
    ) async throws -> Int64 {
        let generation = prepareForNewRequest()
        try await connectIfNeeded()

        guard let currentUser = AuthenticationService.shared.currentUser,
              let transferToken = currentUser.transferToken,
              !transferToken.isEmpty else {
            throw FileTransferError.serverError("文件传输凭证无效，请重新登录")
        }

        let taskId = UUID().uuidString
        let requestId = UUID().uuidString
        let windowLength = max(1, length)
        let request: [String: Any] = [
            "op": "range_pull",
            "protocolVersion": 2,
            "fileId": fileId,
            "taskId": taskId,
            "requestId": requestId,
            "startOffset": startOffset,
            "length": windowLength,
            "userId": currentUser.id,
            "userName": currentUser.username,
            "transferToken": transferToken,
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            throw DirectoryError.invalidData
        }

        var receivedBytesInWindow: Int64 = 0
        var hasSentReadyAck = false
        var hasReportedContentInfo = false
        var loggedEndFrameAsDataFallback = false

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard self.storeContinuation(continuation, for: generation) else { return }
                var receivedSize = startOffset

                let types: Set<FrameTypeEnum> = [.metaFrame, .dataFrame, .endFrame, .fileResponse, .ackFrame]
                let token = socketManager.registerStreamHandler(for: types) { [weak self] frame in
                    guard let self = self else { return false }
                    guard self.isGenerationCurrent(generation) else { return false }

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

                            if let size = Self.int64Value(from: dict["fileSize"]), !hasReportedContentInfo {
                                hasReportedContentInfo = true
                                delegate.didReceiveContentInfo(totalSize: size, mimeType: "video/mp4")

                                // 兼容旧服务端：旧协议需要客户端发送 ready 才开始推流。
                                // 新协议(range_pull)通常不需要该确认帧。
                                let isRangePullAck = dict["chunkSize"] != nil || (dict["requestId"] as? String) != nil
                                if !isRangePullAck && !hasSentReadyAck {
                                    hasSentReadyAck = true
                                    let readyAck: [String: Any] = ["taskId": taskId, "status": "ready"]
                                    if let readyData = try? JSONSerialization.data(withJSONObject: readyAck) {
                                        let readyFrame = Frame(type: .ackFrame, data: readyData, flags: 0x00)
                                        try? self.socketManager.sendFrame(readyFrame)
                                    }
                                }
                            }
                        }
                        return true

                    case .dataFrame:
                        let data = frame.data
                        let range = receivedSize..<(receivedSize + Int64(data.count))
                        delegate.didReceiveVideoData(data, range: range)
                        receivedSize += Int64(data.count)
                        receivedBytesInWindow += Int64(data.count)
                        return !self.currentlyCancelled

                    case .endFrame:
                        // 兼容服务端实现差异：
                        // 若 END_FRAME 载荷是二进制块（常见 65536），按数据帧处理而不是结束信号。
                        if !frame.data.isEmpty {
                            let jsonDict: [String: Any]? = {
                                guard let jsonString = String(data: frame.data, encoding: .utf8),
                                      let data = jsonString.data(using: .utf8) else { return nil }
                                return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? nil
                            }()

                            let looksLikeControlEnd = {
                                guard let dict = jsonDict else { return false }
                                return dict["status"] != nil || dict["totalBytes"] != nil || dict["sentBytes"] != nil || dict["eof"] != nil || dict["message"] != nil
                            }()

                            if !looksLikeControlEnd {
                                if !loggedEndFrameAsDataFallback {
                                    loggedEndFrameAsDataFallback = true
                                    print("⚠️ [VideoStreamingService] END_FRAME 载荷疑似数据块，启用兼容回退为数据帧处理")
                                }
                                let data = frame.data
                                let range = receivedSize..<(receivedSize + Int64(data.count))
                                delegate.didReceiveVideoData(data, range: range)
                                receivedSize += Int64(data.count)
                                receivedBytesInWindow += Int64(data.count)
                                return !self.currentlyCancelled
                            }

                            if let dict = jsonDict,
                               let status = dict["status"] as? String,
                               status == "error" || status == "fail" {
                                let msg = dict["message"] as? String ?? "窗口拉流失败"
                                let code = (dict["code"] as? Int) ?? -1
                                let error = DirectoryError.serverError(code: code, message: msg)
                                delegate.didFail(with: error)
                                self.complete(.failure(error))
                                return false
                            }
                        }
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
                self.replaceStreamHandlerToken(token, for: generation)
                self.startStreamTimeout(for: generation, seconds: self.streamTimeoutSeconds)
                
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

        return receivedBytesInWindow
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
        let token = activeStreamHandlerToken
        activeStreamHandlerToken = nil
        let shouldDisconnect = !hasDisconnectedSocket
        hasDisconnectedSocket = true
        stateLock.unlock()

        if let token {
            socketManager.unregisterStreamHandler(token: token)
        }
        if shouldDisconnect {
            disconnectSocket()
        }
        continuation?.resume(throwing: CancellationError())
    }

    @discardableResult
    private func prepareForNewRequest() -> UInt64 {
        stateLock.lock()
        // 每个窗口请求都是独立生命周期，必须重置状态机
        requestGeneration += 1
        let generation = requestGeneration
        isCancelled = false
        hasCompleted = false
        hasDisconnectedSocket = false
        continuation = nil
        let previousToken = activeStreamHandlerToken
        activeStreamHandlerToken = nil
        stateLock.unlock()

        if let previousToken {
            socketManager.unregisterStreamHandler(token: previousToken)
        }
        return generation
    }

    private var currentlyCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCancelled
    }

    private func storeContinuation(_ continuation: CheckedContinuation<Void, Error>, for generation: UInt64) -> Bool {
        stateLock.lock()
        guard requestGeneration == generation else {
            stateLock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        stateLock.unlock()
        return true
    }

    private func replaceStreamHandlerToken(_ token: UUID, for generation: UInt64) {
        var tokenToUnregister: UUID?
        stateLock.lock()
        if requestGeneration == generation {
            tokenToUnregister = activeStreamHandlerToken
            activeStreamHandlerToken = token
            stateLock.unlock()
            if let tokenToUnregister, tokenToUnregister != token {
                socketManager.unregisterStreamHandler(token: tokenToUnregister)
            }
        } else {
            stateLock.unlock()
            socketManager.unregisterStreamHandler(token: token)
        }
    }

    private func isGenerationCurrent(_ generation: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requestGeneration == generation
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
        let token = activeStreamHandlerToken
        activeStreamHandlerToken = nil
        // 成功窗口请求保持连接复用；失败时断开并在下一次请求重连。
        let shouldDisconnect: Bool
        switch result {
        case .success:
            shouldDisconnect = false
        case .failure:
            shouldDisconnect = !hasDisconnectedSocket
            if shouldDisconnect {
                hasDisconnectedSocket = true
            }
        }
        stateLock.unlock()

        if let token {
            socketManager.unregisterStreamHandler(token: token)
        }
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

    private func startStreamTimeout(for generation: UInt64, seconds: TimeInterval) {
        guard seconds > 0 else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self else { return }
            guard self.isGenerationCurrent(generation) else { return }
            self.complete(.failure(SocketError.timeout))
        }
    }

    private func connectIfNeeded() async throws {
        if isSocketReadyForStreaming() {
            return
        }
        if socketManager.connectionState == .connected {
            socketManager.disconnect(notifyUI: false)
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
            if isSocketReadyForStreaming() {
                return
            }

            if case .error(let message) = socketManager.connectionState {
                throw DirectoryError.serverError(code: -1, message: message)
            }

            attempts += 1
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        throw SocketError.timeout
    }

    private func isSocketReadyForStreaming() -> Bool {
        guard socketManager.connectionState == .connected,
              let inputStream = socketManager.inputStream,
              let outputStream = socketManager.outputStream else {
            return false
        }

        let inputReady: Set<Stream.Status> = [.open, .reading]
        let outputReady: Set<Stream.Status> = [.open, .writing]
        return inputReady.contains(inputStream.streamStatus) &&
               outputReady.contains(outputStream.streamStatus)
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
