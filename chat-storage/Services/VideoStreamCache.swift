import Foundation
import Darwin

// MARK: - VideoStreamCache

/// 管理单个视频文件的磁盘缓存与后台拉流。
/// 从 offset=0 顺序写入临时文件，用高水位线判断区间可用性。
final class VideoStreamCache {
    let fileId: Int64
    let fileSize: Int64
    let tempFileURL: URL

    /// 所有文件 I/O 操作必须在此串行队列上执行，保证线程安全和写后可见性。
    private let cacheIOQueue: DispatchQueue

    private var writeHandle: FileHandle?
    /// 已写入的字节数，仅在 cacheIOQueue 上读写。
    private var writtenBytes: Int64 = 0
    private(set) var isFullyLoaded = false
    private(set) var isInvalid = false

    private var downloadTask: Task<Void, Never>?

    init(fileId: Int64, fileSize: Int64) {
        self.fileId = fileId
        self.fileSize = fileSize
        self.cacheIOQueue = DispatchQueue(
            label: "com.chatstorage.cache-io.\(fileId)",
            qos: .utility
        )
        self.tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video_\(fileId).cache")

        // 清理可能残留的旧临时文件（crash 残留）
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
        // deinit 只做轻量清理，不在此处删文件（cancel() 负责）
        try? writeHandle?.close()
    }

    // MARK: - 后台下载

    func startDownload(fileName: String) {
        guard !isInvalid else { return }

        downloadTask = Task { [weak self] in
            guard let self else { return }
            let service = VideoStreamingService()
            let delegate = CacheWriterDelegate(cache: self)
            do {
                try await service.startCustomVideoStreaming(
                    fileId: self.fileId,
                    startOffset: 0,
                    delegate: delegate
                )
            } catch is CancellationError {
                // 正常取消路径
            } catch {
                self.markInvalid()
                print("❌ [VideoStreamCache] 后台下载失败: \(error)")
            }
        }
    }

    // MARK: - 缓存查询与读取

    /// 检查请求区间是否已完全写入磁盘。
    func isRangeAvailable(_ range: ClosedRange<Int64>) -> Bool {
        cacheIOQueue.sync {
            isFullyLoaded || writtenBytes > range.upperBound
        }
    }

    /// 从磁盘读取指定字节区间（同步，在 cacheIOQueue 上执行）。
    /// 调用前必须确认 isRangeAvailable 返回 true。
    func readData(range: ClosedRange<Int64>) throws -> Data {
        try cacheIOQueue.sync {
            guard !isInvalid else {
                throw VideoStreamCacheError.invalid
            }

            let offset = range.lowerBound
            let count = Int(range.upperBound - range.lowerBound + 1)

            // 用 pread 原子读，避免 seek + read 两步竞态
            let fd = open(tempFileURL.path, O_RDONLY)
            guard fd >= 0 else {
                throw VideoStreamCacheError.fileReadFailed
            }
            defer { close(fd) }

            var buffer = [UInt8](repeating: 0, count: count)
            let bytesRead = Darwin.pread(fd, &buffer, count, off_t(offset))
            guard bytesRead == count else {
                throw VideoStreamCacheError.fileReadFailed
            }

            return Data(buffer)
        }
    }

    // MARK: - 写入回调（由 CacheWriterDelegate 调用）

    func appendData(_ data: Data) {
        cacheIOQueue.async { [weak self] in
            guard let self, !self.isInvalid, let handle = self.writeHandle else { return }
            do {
                try handle.write(contentsOf: data)
                self.writtenBytes += Int64(data.count)
            } catch {
                print("❌ [VideoStreamCache] 写入失败，缓存失效: \(error)")
                self.isInvalid = true
            }
        }
    }

    func markFullyLoaded() {
        cacheIOQueue.async { [weak self] in
            guard let self else { return }
            self.isFullyLoaded = true
            try? self.writeHandle?.close()
            self.writeHandle = nil
            print("✅ [VideoStreamCache] fileId=\(self.fileId) 全量缓存完成，共 \(self.writtenBytes) 字节")
        }
    }

    func markInvalid() {
        cacheIOQueue.async { [weak self] in
            self?.isInvalid = true
        }
    }

    // MARK: - 取消与清理

    func cancel() {
        downloadTask?.cancel()
        cacheIOQueue.async { [weak self] in
            guard let self else { return }
            try? self.writeHandle?.close()
            self.writeHandle = nil
            try? FileManager.default.removeItem(at: self.tempFileURL)
            print("🧹 [VideoStreamCache] fileId=\(self.fileId) 临时文件已清理")
        }
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

    func didFinishLoading() {
        cache?.markFullyLoaded()
    }

    func didFail(with error: Error) {
        cache?.markInvalid()
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

    /// 启动指定文件的缓存任务（幂等，已有缓存则直接返回）。
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

    /// 停止并清理指定文件的缓存。
    func stop(fileId: Int64) {
        lock.lock()
        let cache = caches.removeValue(forKey: fileId)
        lock.unlock()

        cache?.cancel()
        print("⏹️ [VideoStreamCacheManager] 停止缓存 fileId=\(fileId)")
    }
}

// MARK: - Error

enum VideoStreamCacheError: Error {
    case invalid
    case fileReadFailed
}
