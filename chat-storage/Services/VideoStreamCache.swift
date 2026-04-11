import Foundation
import Darwin

// MARK: - RangeWaiter

/// 一个等待后台流写盘到指定区间的请求。
/// 当 notifyWaiters() 检测到区间可用时调用 serve()，超时则调用 cancel()。
private struct RangeWaiter {
    let range: ClosedRange<Int64>
    let serve: () -> Void    // 区间数据就绪后由调用方负责从磁盘读取并发送
    let cancel: () -> Void   // 超时或缓存失效时通知调用方关闭连接
    let timeoutAt: Date

    static let defaultTimeoutSeconds: Double = 20.0
}

// MARK: - VideoStreamCache

/// 管理单个视频文件的磁盘缓存与后台拉流。
///
/// 设计原则：
///   - 整个播放周期只维护 **一条** 后台 TCP 流（VideoStreamingService）
///   - 流从 `downloadStartOffset` 顺序写入临时磁盘文件
///   - 暂停不停流：后台流与播放状态解耦，暂停时继续写盘
///   - Range 未命中：注册 RangeWaiter，等后台流写到对应位置后自动唤醒，不新建连接
///   - 大幅 seek：重置文件并从新位置重启后台流
final class VideoStreamCache {
    let fileId: Int64
    let fileSize: Int64
    let tempFileURL: URL

    /// 所有文件 I/O 及 waiters 操作必须在此串行队列上执行。
    private let cacheIOQueue: DispatchQueue

    private var writeHandle: FileHandle?
    /// 相对于 downloadStartOffset 已写入的字节数，仅在 cacheIOQueue 上读写。
    private(set) var writtenBytes: Int64 = 0
    /// 当前后台流的起始偏移量（大幅 seek 后会更新）。
    private(set) var downloadStartOffset: Int64 = 0
    private(set) var isFullyLoaded = false
    private(set) var isInvalid = false

    /// 文件名，由 startDownload 设置，供 restartDownload 复用。
    private(set) var fileName: String = ""
    private var allowsSequentialCompletionLog = true
    private var hasPrintedSequentialCompletionLog = false

    private var downloadTask: Task<Void, Never>?
    private var streamingService: VideoStreamingService?

    /// 等待后台流写盘的 Range 请求列表，在 cacheIOQueue 上访问。
    private var waiters: [RangeWaiter] = []

    init(fileId: Int64, fileSize: Int64) {
        self.fileId = fileId
        self.fileSize = fileSize
        self.cacheIOQueue = DispatchQueue(
            label: "com.chatstorage.cache-io.\(fileId)",
            qos: .utility
        )
        self.tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video_\(fileId).cache")

        try? FileManager.default.removeItem(at: tempFileURL)
        FileManager.default.createFile(atPath: tempFileURL.path, contents: nil)

        do {
            writeHandle = try FileHandle(forWritingTo: tempFileURL)
        } catch {
            print("❌ [VideoStreamCache] 无法打开写文件句柄: \(error)")
            isInvalid = true
        }
    }

    deinit {
        try? writeHandle?.close()
        try? FileManager.default.removeItem(at: tempFileURL)
    }

    // MARK: - 后台下载

    func startDownload(fileName: String) {
        self.fileName = fileName
        self.allowsSequentialCompletionLog = true
        self.hasPrintedSequentialCompletionLog = false
        guard !isInvalid else { return }
        launchDownloadTask(from: 0)
    }

    /// 当前后台流已下载到的绝对偏移量（downloadStartOffset + writtenBytes）。
    var currentDownloadPosition: Int64 {
        cacheIOQueue.sync { downloadStartOffset + writtenBytes }
    }

    // MARK: - 缓存查询

    /// 判断请求区间是否已完全写入磁盘。
    func isRangeAvailable(_ range: ClosedRange<Int64>) -> Bool {
        cacheIOQueue.sync { isRangeAvailableUnsafe(range) }
    }

    // MARK: - 磁盘读取

    /// 从磁盘读取指定字节区间（同步）。调用前必须确认 isRangeAvailable 为 true。
    func readData(range: ClosedRange<Int64>) throws -> Data {
        try cacheIOQueue.sync {
            guard !isInvalid else { throw VideoStreamCacheError.invalid }
            guard range.lowerBound >= downloadStartOffset else { throw VideoStreamCacheError.outOfRange }

            let fileOffset = range.lowerBound - downloadStartOffset
            let count = Int(range.upperBound - range.lowerBound + 1)
            guard count > 0 else { return Data() }

            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: tempFileURL)
            } catch {
                throw VideoStreamCacheError.fileReadFailed
            }
            defer { try? handle.close() }

            do {
                try handle.seek(toOffset: UInt64(fileOffset))
            } catch {
                throw VideoStreamCacheError.fileReadFailed
            }

            let maxChunkSize = 1 * 1024 * 1024
            var remaining = count
            var result = Data()
            result.reserveCapacity(count)

            while remaining > 0 {
                let chunk = min(maxChunkSize, remaining)
                let part = try handle.read(upToCount: chunk) ?? Data()
                guard !part.isEmpty else { throw VideoStreamCacheError.fileReadFailed }
                result.append(part)
                remaining -= part.count
            }

            return result
        }
    }

    // MARK: - Waiter 注册（Range 未命中时使用）

    /// 注册一个等待指定区间的请求。当后台流写到该区间时自动调用 serve()。
    /// 超时（20s）或缓存失效时调用 cancel()。
    func registerWaiter(
        for range: ClosedRange<Int64>,
        serve: @escaping () -> Void,
        cancel cancelCallback: @escaping () -> Void
    ) {
        let waiter = RangeWaiter(
            range: range,
            serve: serve,
            cancel: cancelCallback,
            timeoutAt: Date().addingTimeInterval(RangeWaiter.defaultTimeoutSeconds)
        )
        cacheIOQueue.async { [weak self] in
            guard let self else { cancelCallback(); return }
            self.waiters.append(waiter)
            // 写盘时已注册的 Waiter 可能已满足，立即检查一次
            self.notifyWaiters()
        }
    }

    /// 大幅 seek：原子地重置后台流并注册新 Waiter，避免竞态条件。
    func restartDownloadAndRegisterWaiter(
        from newOffset: Int64,
        for range: ClosedRange<Int64>,
        serve: @escaping () -> Void,
        cancel cancelCallback: @escaping () -> Void
    ) {
        // 取消旧的下载任务（Swift Task 取消是线程安全的）
        let oldTask = downloadTask
        downloadTask = nil
        oldTask?.cancel()

        cacheIOQueue.async { [weak self] in
            guard let self else { cancelCallback(); return }

            // 取消所有旧 Waiter
            let oldWaiters = self.waiters
            self.waiters = []
            oldWaiters.forEach { $0.cancel() }

            // 标记失效，阻止旧任务的 appendData 继续写入
            self.isInvalid = true

            // 重建临时文件
            try? self.writeHandle?.close()
            self.writeHandle = nil
            try? FileManager.default.removeItem(at: self.tempFileURL)
            FileManager.default.createFile(atPath: self.tempFileURL.path, contents: nil)

            do {
                self.writeHandle = try FileHandle(forWritingTo: self.tempFileURL)
                self.writtenBytes = 0
                self.downloadStartOffset = newOffset
                self.isFullyLoaded = false
                self.isInvalid = false
                self.allowsSequentialCompletionLog = false
                self.hasPrintedSequentialCompletionLog = false

                // 注册新 Waiter，然后启动下载
                let waiter = RangeWaiter(
                    range: range,
                    serve: serve,
                    cancel: cancelCallback,
                    timeoutAt: Date().addingTimeInterval(RangeWaiter.defaultTimeoutSeconds)
                )
                self.waiters.append(waiter)

                self.launchDownloadTaskOnIOQueue(from: newOffset)
            } catch {
                self.isInvalid = true
                cancelCallback()
                print("❌ [VideoStreamCache] 重启时创建文件句柄失败: \(error)")
            }
        }
    }

    // MARK: - 写入回调（由 CacheWriterDelegate 调用）

    func appendData(_ data: Data) {
        cacheIOQueue.async { [weak self] in
            guard let self, !self.isInvalid, let handle = self.writeHandle else { return }
            do {
                try handle.write(contentsOf: data)
                self.writtenBytes += Int64(data.count)
                self.notifyWaiters()
            } catch {
                print("❌ [VideoStreamCache] 写入失败: \(error)")
                self.isInvalid = true
                self.cancelAllWaiters()
            }
        }
    }

    func markFullyLoaded() {
        cacheIOQueue.async { [weak self] in
            guard let self else { return }
            self.isFullyLoaded = true
            try? self.writeHandle?.close()
            self.writeHandle = nil
            self.notifyWaiters()
            print("✅ [VideoStreamCache] fileId=\(self.fileId) 全量缓存完成，共 \(self.writtenBytes) 字节")
            guard !self.hasPrintedSequentialCompletionLog,
                  let message = Self.completionLogMessage(
                    fileName: self.fileName,
                    fileSize: self.fileSize,
                    writtenBytes: self.writtenBytes,
                    downloadStartOffset: self.downloadStartOffset,
                    allowsSequentialCompletionLog: self.allowsSequentialCompletionLog
                  ) else {
                return
            }
            self.hasPrintedSequentialCompletionLog = true
            print(message)
        }
    }

    func markInvalid() {
        cacheIOQueue.async { [weak self] in
            guard let self else { return }
            self.isInvalid = true
            self.cancelAllWaiters()
        }
    }

    func disableSequentialCompletionLog() {
        cacheIOQueue.async { [weak self] in
            self?.allowsSequentialCompletionLog = false
        }
    }

    // MARK: - 取消与清理

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        streamingService?.cancel()
        streamingService = nil

        let url = tempFileURL
        let handle = writeHandle
        writeHandle = nil

        cacheIOQueue.async { [weak self] in
            self?.cancelAllWaiters()
            try? handle?.close()
            try? FileManager.default.removeItem(at: url)
            print("🧹 [VideoStreamCache] 临时文件已清理: \(url.lastPathComponent)")
        }
    }

    // MARK: - 私有方法

    /// 启动新的下载 Task（从任意线程调用，Task 在内部管理）。
    private func launchDownloadTask(from offset: Int64) {
        let fid = fileId
        let name = fileName
        let totalSize = fileSize
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let windowSize: Int64 = 1 * 1024 * 1024 // 1MB 窗口，兼顾 seek 响应与内存占用
                var nextOffset = offset
                var service = VideoStreamingService()
                self.streamingService = service
                while !Task.isCancelled && nextOffset < totalSize {
                    let requestLength = min(windowSize, totalSize - nextOffset)
                    let received = try await self.pullWindowWithRetry(
                        service: &service,
                        fileId: fid,
                        startOffset: nextOffset,
                        length: requestLength
                    )
                    guard received > 0 else { throw VideoStreamCacheError.fileReadFailed }
                    nextOffset += received
                }
                if !Task.isCancelled {
                    self.markFullyLoaded()
                }
            } catch is CancellationError {
                // 正常取消路径
            } catch {
                self.markInvalid()
                print("❌ [VideoStreamCache] 后台下载失败 [\(name)]: \(error)")
            }
            self.streamingService = nil
        }
    }

    /// 在 cacheIOQueue 上启动新的下载 Task（已在 cacheIOQueue 上调用时使用）。
    private func launchDownloadTaskOnIOQueue(from offset: Int64) {
        let fid = fileId
        let name = fileName
        let totalSize = fileSize
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let windowSize: Int64 = 1 * 1024 * 1024
                var nextOffset = offset
                var service = VideoStreamingService()
                self.streamingService = service
                while !Task.isCancelled && nextOffset < totalSize {
                    let requestLength = min(windowSize, totalSize - nextOffset)
                    let received = try await self.pullWindowWithRetry(
                        service: &service,
                        fileId: fid,
                        startOffset: nextOffset,
                        length: requestLength
                    )
                    guard received > 0 else { throw VideoStreamCacheError.fileReadFailed }
                    nextOffset += received
                }
                if !Task.isCancelled {
                    self.markFullyLoaded()
                }
            } catch is CancellationError { }
            catch {
                self.markInvalid()
                print("❌ [VideoStreamCache] 重启后台下载失败 [\(name)]: \(error)")
            }
            self.streamingService = nil
        }
    }

    private func pullWindowWithRetry(
        service: inout VideoStreamingService,
        fileId: Int64,
        startOffset: Int64,
        length: Int64
    ) async throws -> Int64 {
        let maxRetries = 3
        var lastError: Error?

        for attempt in 1...maxRetries {
            try Task.checkCancellation()
            let delegate = CacheWriterDelegate(cache: self)
            do {
                let received = try await service.startCustomVideoStreaming(
                    fileId: fileId,
                    startOffset: startOffset,
                    length: length,
                    delegate: delegate
                )
                if received > 0 {
                    return received
                }
                lastError = VideoStreamCacheError.fileReadFailed
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                service.cancel()
                service = VideoStreamingService()
                self.streamingService = service
            }

            if attempt < maxRetries {
                print("⚠️ [VideoStreamCache] 窗口拉流重试 \(attempt)/\(maxRetries) offset=\(startOffset) length=\(length)")
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        throw lastError ?? VideoStreamCacheError.fileReadFailed
    }

    /// 检查并唤醒所有已满足的 Waiter，同时清除超时的 Waiter。
    /// 必须在 cacheIOQueue 上调用。
    private func notifyWaiters() {
        guard !waiters.isEmpty else { return }
        let now = Date()
        var remaining: [RangeWaiter] = []
        for waiter in waiters {
            if isRangeAvailableUnsafe(waiter.range) {
                waiter.serve()
            } else if now > waiter.timeoutAt {
                print("⏰ [VideoStreamCache] Waiter 超时，range=\(waiter.range)")
                waiter.cancel()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }

    /// 取消所有 Waiter。必须在 cacheIOQueue 上调用。
    private func cancelAllWaiters() {
        let old = waiters
        waiters = []
        old.forEach { $0.cancel() }
    }

    /// 无锁版本的 isRangeAvailable，必须在 cacheIOQueue 上调用。
    private func isRangeAvailableUnsafe(_ range: ClosedRange<Int64>) -> Bool {
        guard range.lowerBound >= downloadStartOffset else { return false }
        let relativeEnd = range.upperBound - downloadStartOffset
        return isFullyLoaded || writtenBytes > relativeEnd
    }

    static func completionLogMessage(
        fileName: String,
        fileSize: Int64,
        writtenBytes: Int64,
        downloadStartOffset: Int64,
        allowsSequentialCompletionLog: Bool
    ) -> String? {
        guard allowsSequentialCompletionLog, downloadStartOffset == 0, writtenBytes == fileSize else {
            return nil
        }

        return "✅ [VideoStreamCache] 本次视频文件拉流完成，可以正常拖动播放，文件名称=\(fileName)，文件总流字节大小=\(fileSize)，已拉取的大小=\(writtenBytes)"
    }
}

// MARK: - CacheWriterDelegate

private final class CacheWriterDelegate: VideoStreamLoaderDelegate {
    weak var cache: VideoStreamCache?

    init(cache: VideoStreamCache) {
        self.cache = cache
    }

    func didReceiveContentInfo(totalSize: Int64, mimeType: String) {}

    func didReceiveVideoData(_ data: Data, range: Range<Int64>) {
        cache?.appendData(data)
    }

    // V2 协议下 END_FRAME 仅表示单个窗口结束，不代表全量文件已结束。
    func didFinishLoading() {}

    func didFail(with error: Error) {
        // 失败由外层窗口重试逻辑兜底；仅在重试耗尽后由调用方 markInvalid。
        print("❌ [CacheWriterDelegate] 流失败: \(error)")
    }
}

// MARK: - VideoStreamCacheManager

/// 全局管理所有活跃视频缓存的单例。
final class VideoStreamCacheManager {
    static let shared = VideoStreamCacheManager()

    private var caches: [Int64: VideoStreamCache] = [:]
    private let lock = NSLock()

    private init() {}

    func start(fileId: Int64, fileSize: Int64, fileName: String) {
        lock.lock()
        defer { lock.unlock() }

        guard caches[fileId] == nil else { return }

        let cache = VideoStreamCache(fileId: fileId, fileSize: fileSize)
        guard !cache.isInvalid else { return }

        caches[fileId] = cache
        cache.startDownload(fileName: fileName)
        print("▶️ [VideoStreamCacheManager] 启动缓存 fileId=\(fileId) size=\(fileSize)")
    }

    func cache(for fileId: Int64) -> VideoStreamCache? {
        lock.lock()
        defer { lock.unlock() }
        return caches[fileId]
    }

    func stop(fileId: Int64) {
        lock.lock()
        let cache = caches.removeValue(forKey: fileId)
        lock.unlock()

        cache?.cancel()
        print("⏹️ [VideoStreamCacheManager] 停止缓存 fileId=\(fileId)")
    }

    func disableSequentialCompletionLog(fileId: Int64) {
        lock.lock()
        let cache = caches[fileId]
        lock.unlock()

        cache?.disableSequentialCompletionLog()
    }
}

// MARK: - Error

enum VideoStreamCacheError: Error {
    case invalid
    case fileReadFailed
    case outOfRange
}
