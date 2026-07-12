import Foundation

public final class FileDownloadService {
    private let socketManager: SocketManager
    private let writeQueue = DispatchQueue(label: "com.chatstorage.file-download-write", qos: .utility)
    private let cancelState = ManagedCriticalState(false)
    private let pauseThreshold = 100
    private let resumeThreshold = 40
    private let idleTimeoutSeconds: TimeInterval = 45.0

    public init(socketManager: SocketManager) {
        self.socketManager = socketManager
    }

    public func cancel() {
        cancelState.withCriticalRegion { $0 = true }
    }

    public func stopDownload() {
        cancel()
        socketManager.disconnect(notifyUI: false)
    }

    public func downloadFile(
        task: StorageTransferTask,
        startOffset: Int64,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        guard let currentUser = AuthenticationService.shared.currentUser,
              let transferToken = currentUser.transferToken,
              !transferToken.isEmpty else {
            throw FileTransferError.serverError("文件传输凭证无效，请重新登录")
        }

        cancelState.withCriticalRegion { $0 = false }
        let finalFileURL = task.fileUrl
        let partFileURL = Self.partFileURL(for: finalFileURL)
        let fileManager = FileManager.default
        let directory = finalFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        _ = DownloadDirectoryManager.shared.startAccess()
        defer { DownloadDirectoryManager.shared.stopAccess() }

        try migrateLegacyPartialFileIfNeeded(
            finalFileURL: finalFileURL,
            partFileURL: partFileURL,
            expectedSize: task.fileSize,
            persistedOffset: startOffset
        )

        let existingPartSize = Self.fileSize(at: partFileURL)
        let resolvedOffset = Self.debugResolveResumeOffset(
            persistedOffset: startOffset,
            localPartSize: existingPartSize,
            remoteFileSize: task.fileSize
        )
        if existingPartSize != resolvedOffset {
            try resetPartFile(partFileURL)
        } else if !fileManager.fileExists(atPath: partFileURL.path) {
            fileManager.createFile(atPath: partFileURL.path, contents: nil)
        }

        let fileHandle = try FileHandle(forWritingTo: partFileURL)
        try fileHandle.seek(toOffset: UInt64(resolvedOffset))
        let fileHandleClosed = ManagedCriticalState(false)
        defer {
            let shouldClose = fileHandleClosed.withCriticalRegion { closed in
                if closed { return false }
                closed = true
                return true
            }
            if shouldClose { try? fileHandle.close() }
            socketManager.resumeInputEvents()
        }

        let taskId = task.id.uuidString
        PersistenceManager.shared.saveTask(
            taskId: taskId,
            fileUrl: finalFileURL,
            fileName: task.name,
            fileSize: task.fileSize,
            targetDirId: task.targetDirId,
            userId: Int32(task.userId),
            userName: task.userName,
            status: "下载中",
            progress: task.fileSize > 0 ? Double(resolvedOffset) / Double(task.fileSize) : 0,
            uploadedBytes: resolvedOffset,
            md5: "DOWNLOAD_FILE_ID_\(task.remoteFileId)"
        )

        let request: [String: Any] = [
            "fileId": task.remoteFileId,
            "taskId": taskId,
            "startOffset": resolvedOffset,
            "userId": currentUser.id,
            "userName": currentUser.username,
            "transferToken": transferToken
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request)

        let state = ManagedCriticalState(DownloadRuntimeState(
            receivedSize: resolvedOffset,
            totalSize: task.fileSize,
            pendingWrites: 0,
            lastUpdateTime: Date(),
            lastBytes: resolvedOffset
        ))
        let completion = DownloadCompletionGate()
        let handlerToken = ManagedCriticalState<UUID?>(nil)
        let idleTimer = DownloadIdleTimer(timeout: idleTimeoutSeconds)

        func finish(_ result: Result<Void, Error>, disconnect: Bool = true) {
            guard completion.finish(result) else { return }
            idleTimer.cancel()
            if let token = handlerToken.withCriticalRegion({ $0 }) {
                socketManager.unregisterStreamHandler(token: token)
            }
            socketManager.resumeInputEvents()
            if disconnect {
                socketManager.disconnect(notifyUI: false)
            }
        }

        func scheduleFailure(_ error: Error) {
            writeQueue.async {
                finish(.failure(error))
            }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                idleTimer.touch {
                    scheduleFailure(SocketError.timeout)
                }

                let types: Set<FrameTypeEnum> = [.metaFrame, .dataFrame, .endFrame, .fileResponse, .ackFrame]
                let token = socketManager.registerStreamHandler(for: types) { [weak self] frame in
                    guard let self else { return false }
                    idleTimer.touch {
                        scheduleFailure(SocketError.timeout)
                    }
                    if self.cancelState.withCriticalRegion({ $0 }) {
                        scheduleFailure(CancellationError())
                        return false
                    }

                    switch frame.type {
                    case .ackFrame, .metaFrame:
                        guard let dict = try? JSONSerialization.jsonObject(with: frame.data) as? [String: Any] else {
                            scheduleFailure(FileTransferError.invalidResponse)
                            return false
                        }
                        if let status = dict["status"] as? String, status == "error" || status == "fail" {
                            scheduleFailure(FileTransferError.serverError(dict["message"] as? String ?? "下载失败"))
                            return false
                        }
                        guard let remoteSize = Self.int64Value(dict["fileSize"]),
                              let serverOffset = Self.int64Value(dict["startOffset"]),
                              serverOffset == resolvedOffset else {
                            scheduleFailure(FileTransferError.serverError("服务端下载元数据不完整或断点不一致"))
                            return false
                        }
                        state.withCriticalRegion { runtime in
                            runtime.totalSize = remoteSize
                        }
                        let ready: [String: Any] = ["taskId": taskId, "status": "ready"]
                        do {
                            let readyData = try JSONSerialization.data(withJSONObject: ready)
                            try self.socketManager.sendFrame(Frame(type: .ackFrame, data: readyData, flags: 0))
                            let progress = remoteSize > 0 ? Double(resolvedOffset) / Double(remoteSize) : 1.0
                            progressHandler(progress, "准备中...")
                        } catch {
                            scheduleFailure(error)
                            return false
                        }
                        return true

                    case .dataFrame:
                        let data = frame.data
                        let pending = state.withCriticalRegion { runtime -> Int in
                            runtime.pendingWrites += 1
                            return runtime.pendingWrites
                        }
                        if pending >= self.pauseThreshold {
                            self.socketManager.pauseInputEvents()
                        }
                        self.writeQueue.async {
                            guard !completion.isCompleted else { return }
                            do {
                                try fileHandle.write(contentsOf: data)
                                let update = state.withCriticalRegion { runtime -> DownloadProgressUpdate? in
                                    runtime.receivedSize += Int64(data.count)
                                    runtime.pendingWrites = max(0, runtime.pendingWrites - 1)
                                    let now = Date()
                                    guard now.timeIntervalSince(runtime.lastUpdateTime) >= 0.5 else { return nil }
                                    let deltaTime = now.timeIntervalSince(runtime.lastUpdateTime)
                                    let deltaBytes = runtime.receivedSize - runtime.lastBytes
                                    let progress = runtime.totalSize > 0
                                        ? Double(runtime.receivedSize) / Double(runtime.totalSize) : 0
                                    runtime.lastUpdateTime = now
                                    runtime.lastBytes = runtime.receivedSize
                                    return DownloadProgressUpdate(
                                        receivedSize: runtime.receivedSize,
                                        progress: progress,
                                        speed: Self.formatSpeed(Double(deltaBytes) / max(deltaTime, 0.001)),
                                        pendingWrites: runtime.pendingWrites
                                    )
                                }
                                let pendingAfterWrite = state.withCriticalRegion { $0.pendingWrites }
                                if pendingAfterWrite <= self.resumeThreshold {
                                    self.socketManager.resumeInputEvents()
                                }
                                if let update {
                                    progressHandler(update.progress, update.speed)
                                    PersistenceManager.shared.updateProgress(
                                        taskId: taskId,
                                        progress: update.progress,
                                        uploadedBytes: update.receivedSize,
                                        status: "下载中"
                                    )
                                }
                            } catch {
                                finish(.failure(error))
                            }
                        }
                        return true

                    case .endFrame:
                        guard let end = try? JSONSerialization.jsonObject(with: frame.data) as? [String: Any],
                              (end["status"] as? String) == "success",
                              let sentBytes = Self.int64Value(end["sentBytes"]),
                              let endOffset = Self.int64Value(end["endOffset"]) else {
                            scheduleFailure(FileTransferError.invalidResponse)
                            return false
                        }
                        self.writeQueue.async {
                            do {
                                try fileHandle.synchronize()
                                let shouldClose = fileHandleClosed.withCriticalRegion { closed in
                                    if closed { return false }
                                    closed = true
                                    return true
                                }
                                if shouldClose { try fileHandle.close() }

                                let runtime = state.withCriticalRegion { $0 }
                                let localSize = Self.fileSize(at: partFileURL)
                                let receivedThisRequest = runtime.receivedSize - resolvedOffset
                                guard sentBytes == receivedThisRequest,
                                      endOffset == runtime.receivedSize,
                                      Self.debugIsComplete(localSize: localSize, remoteFileSize: runtime.totalSize) else {
                                    throw FileTransferError.serverError(
                                        "下载完整性校验失败: local=\(localSize), remote=\(runtime.totalSize), sent=\(sentBytes)"
                                    )
                                }

                                if fileManager.fileExists(atPath: finalFileURL.path) {
                                    _ = try fileManager.replaceItemAt(finalFileURL, withItemAt: partFileURL)
                                } else {
                                    try fileManager.moveItem(at: partFileURL, to: finalFileURL)
                                }
                                progressHandler(1.0, "完成")
                                PersistenceManager.shared.updateProgress(
                                    taskId: taskId,
                                    progress: 1.0,
                                    uploadedBytes: runtime.totalSize,
                                    status: "已完成"
                                )
                                finish(.success(()))
                            } catch {
                                finish(.failure(error))
                            }
                        }
                        return false

                    case .fileResponse:
                        if let dict = try? FrameParser.decodeAsDictionary(frame),
                           let code = dict["code"] as? Int, code != 200 {
                            scheduleFailure(FileTransferError.serverError(dict["message"] as? String ?? "下载失败"))
                            return false
                        }
                        return true

                    default:
                        return true
                    }
                }
                handlerToken.withCriticalRegion { $0 = token }

                do {
                    let requestFrame = Frame(type: .metaFrame, data: requestData, flags: 0)
                    try socketManager.sendFrame(requestFrame)
                } catch {
                    finish(.failure(error))
                }
            }
        } onCancel: {
            self.cancel()
            self.socketManager.disconnect(notifyUI: false)
            self.writeQueue.async {
                finish(.failure(CancellationError()), disconnect: false)
            }
        }
    }

    static func debugResolveResumeOffset(
        persistedOffset: Int64,
        localPartSize: Int64,
        remoteFileSize: Int64
    ) -> Int64 {
        guard remoteFileSize >= 0, localPartSize >= 0, localPartSize <= remoteFileSize else { return 0 }
        _ = persistedOffset
        return localPartSize
    }

    static func debugIsComplete(localSize: Int64, remoteFileSize: Int64) -> Bool {
        remoteFileSize >= 0 && localSize == remoteFileSize
    }

    private static func partFileURL(for finalURL: URL) -> URL {
        finalURL.appendingPathExtension("part")
    }

    private static func fileSize(at url: URL) -> Int64 {
        guard let number = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return 0
        }
        return number.int64Value
    }

    private func migrateLegacyPartialFileIfNeeded(
        finalFileURL: URL,
        partFileURL: URL,
        expectedSize: Int64,
        persistedOffset: Int64
    ) throws {
        let manager = FileManager.default
        guard persistedOffset > 0,
              !manager.fileExists(atPath: partFileURL.path),
              manager.fileExists(atPath: finalFileURL.path) else { return }
        let legacySize = Self.fileSize(at: finalFileURL)
        if legacySize > 0 && (expectedSize <= 0 || legacySize < expectedSize) {
            try manager.moveItem(at: finalFileURL, to: partFileURL)
        }
    }

    private func resetPartFile(_ url: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
        manager.createFile(atPath: url.path, contents: nil)
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 { return String(format: "%.0f B/s", bytesPerSecond) }
        if bytesPerSecond < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSecond / 1024) }
        return String(format: "%.1f MB/s", bytesPerSecond / 1024 / 1024)
    }
}

private struct DownloadRuntimeState {
    var receivedSize: Int64
    var totalSize: Int64
    var pendingWrites: Int
    var lastUpdateTime: Date
    var lastBytes: Int64
}

private struct DownloadProgressUpdate {
    let receivedSize: Int64
    let progress: Double
    let speed: String
    let pendingWrites: Int
}

private final class DownloadCompletionGate {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completed = false

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    @discardableResult
    func finish(_ result: Result<Void, Error>) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return false
        }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        return true
    }
}

private final class DownloadIdleTimer {
    private let lock = NSLock()
    private let timeout: TimeInterval
    private var workItem: DispatchWorkItem?

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func touch(onTimeout: @escaping () -> Void) {
        lock.lock()
        workItem?.cancel()
        let item = DispatchWorkItem(block: onTimeout)
        workItem = item
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: item)
    }

    func cancel() {
        lock.lock()
        workItem?.cancel()
        workItem = nil
        lock.unlock()
    }
}
