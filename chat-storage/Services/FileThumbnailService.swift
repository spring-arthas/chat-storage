//
//  FileThumbnailService.swift
//  chat-storage
//
//  两级缓存（内存 NSCache + 磁盘 JPEG）的缩略图服务。
//
//  查找链：内存命中 → 磁盘命中 → 服务端拉取（图片直接拉字节；视频用 AVAssetResourceLoader 按需拉）
//  写入链：服务端拉取成功后同时写内存 + 磁盘，下次直接命中。
//

import Foundation
import AppKit
import AVFoundation
import ImageIO
import Darwin

enum ThumbnailRemapState: String, Codable {
    case thumbnailPending
    case thumbnailReady
    case thumbnailFailed
    case uploadSucceeded
    case uploadSucceededNoFileId
    case remapPending
    case remapRetrying
    case remapDone
    case remapExhausted
}

struct ThumbnailRemapRecord: Codable, Equatable {
    let taskId: String
    var fileId: Int64?
    var state: ThumbnailRemapState
    var attempts: Int
    var lastError: String?
    var updatedAt: Date
}

private enum FFmpegAvailability {
    case unknown
    case unavailable
    case available(String)
}

struct LocalVideoThumbnailProfile: Equatable {
    let seekPoints: [Int]
    let ffmpegQuality: Int
    let timeoutSeconds: TimeInterval
    let outputWidth: Int
    let outputHeight: Int
}

actor FileThumbnailService {
    static let shared = FileThumbnailService()
    private static let fullHDSize = CGSize(width: 1920, height: 1080)
    private static let fallbackRemoteImageFetchLength: Int64 = 10 * 1024 * 1024
    private static let supportedLocalVideoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "ts", "m2ts", "3gp"
    ]

    // MARK: - 缓存

    private let memCache = NSCache<NSNumber, NSImage>()
    private let previewMemCache = NSCache<NSNumber, NSImage>()
    private let taskMemCache = NSCache<NSString, NSImage>()
    private let diskCacheDir: URL
    private let previewDiskCacheDir: URL
    private let ledgerFilePath: URL

    // MARK: - 并发控制

    /// 同一 fileId 正在加载时，后来的请求直接等待同一个 Task 的结果
    private var inFlight: [Int64: Task<NSImage?, Never>] = [:]
    /// 同时进行的加载任务上限（每个视频任务内部可能再创建多个 socket，不受此限制）
    private var activeCount = 0
    private let maxConcurrent = 3
    private var loadSlotWaiters: [CheckedContinuation<Void, Never>] = []
    private var remapInFlight: Set<String> = []
    private var remapLedger: [String: ThumbnailRemapRecord] = [:]
    private var ffmpegAvailability: FFmpegAvailability = .unknown
    private var prefetchQueue: [Int64: DirectoryItem] = [:]
    private var prefetchWorker: Task<Void, Never>?

    // MARK: - Init

    init(testDiskCacheDir: URL? = nil) {
        if let testDiskCacheDir {
            diskCacheDir = testDiskCacheDir
            previewDiskCacheDir = testDiskCacheDir.appendingPathComponent("image-previews-v2", isDirectory: true)
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            diskCacheDir = caches.appendingPathComponent("chat-storage/thumbnails", isDirectory: true)
            previewDiskCacheDir = caches.appendingPathComponent("chat-storage/image-previews-v2", isDirectory: true)
        }
        ledgerFilePath = diskCacheDir.appendingPathComponent("thumbnail_reconcile_ledger.json")
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: previewDiskCacheDir, withIntermediateDirectories: true)
        memCache.countLimit = 200
        previewMemCache.countLimit = 80
        taskMemCache.countLimit = 300
        remapLedger = Self.loadLedgerFromDisk(at: ledgerFilePath)

        // 启动后补偿：对已知 fileId 但未 remapDone 的记录做后台重试。
        Task {
            await self.recoverPendingRemapsFromLedger()
        }
        // 历史缩略图不再做启动迁移，仅保证新上传视频输出 1080P。
    }

    // MARK: - 磁盘路径

    private func diskPath(for fileId: Int64) -> URL {
        diskCacheDir.appendingPathComponent("\(fileId).jpg")
    }

    private func previewDiskPath(for fileId: Int64) -> URL {
        previewDiskCacheDir.appendingPathComponent("\(fileId).img")
    }

    /// 上传任务进行中时，以 taskId 为 key 的临时磁盘路径
    private func taskDiskPath(for taskId: String) -> URL {
        diskCacheDir.appendingPathComponent("task_\(taskId).jpg")
    }

    private func taskCacheKey(for taskId: String) -> NSString {
        NSString(string: "task_\(taskId)")
    }

    // MARK: - 迁移账本

    private static func loadLedgerFromDisk(at ledgerPath: URL) -> [String: ThumbnailRemapRecord] {
        guard let data = try? Data(contentsOf: ledgerPath) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([String: ThumbnailRemapRecord].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveLedgerToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(remapLedger) else { return }
        try? data.write(to: ledgerFilePath, options: .atomic)
    }

    private func upsertLedger(
        taskId: String,
        fileId: Int64? = nil,
        state: ThumbnailRemapState,
        incrementAttempts: Bool = false,
        lastError: String? = nil
    ) {
        var record = remapLedger[taskId] ?? ThumbnailRemapRecord(
            taskId: taskId,
            fileId: nil,
            state: state,
            attempts: 0,
            lastError: nil,
            updatedAt: Date()
        )
        if let fileId {
            record.fileId = fileId
        }
        record.state = state
        if incrementAttempts {
            record.attempts += 1
        }
        record.lastError = lastError
        record.updatedAt = Date()
        remapLedger[taskId] = record
        saveLedgerToDisk()
    }

    private func shouldAttemptRemap(record: ThumbnailRemapRecord) -> Bool {
        guard record.fileId != nil else { return false }
        switch record.state {
        case .remapDone, .uploadSucceededNoFileId, .remapExhausted:
            return false
        default:
            return true
        }
    }

    private func recoverPendingRemapsFromLedger() async {
        for record in remapLedger.values where shouldAttemptRemap(record: record) {
            guard let fileId = record.fileId else { continue }
            startRemapTaskIfNeeded(taskId: record.taskId, fileId: fileId)
        }
    }

    // MARK: - 核心查询方法

    /// 返回 fileId 对应的缩略图。优先内存→磁盘→网络，结果自动写入两级缓存。
    func thumbnail(for item: DirectoryItem) async -> NSImage? {
        let key = NSNumber(value: item.id)

        // 1. 内存命中
        if let img = memCache.object(forKey: key) {
            if item.isImageFile && !isUsableImageThumbnail(img) {
                memCache.removeObject(forKey: key)
            } else {
                return img
            }
        }

        // 2. 磁盘命中
        let path = diskPath(for: item.id)
        if let data = try? Data(contentsOf: path),
           let img = Self.decodeImageData(data) {
            if item.isImageFile && !isUsableImageThumbnail(img) {
                try? FileManager.default.removeItem(at: path)
            } else {
                memCache.setObject(img, forKey: key)
                return img
            }
        }

        // 3. 已有 in-flight 任务则等待
        if let existing = inFlight[item.id] {
            return await existing.value
        }

        // 4. 并发限制：轮询等待空位
        await waitForLoadSlotIfNeeded()

        // 5. 发起加载
        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            let img = await self.loadFromServer(item)
            await self.finishLoad(fileId: item.id, img: img, path: path, key: key)
            return img
        }
        activeCount += 1
        inFlight[item.id] = task
        let result = await task.value
        return result
    }

    /// 点击聊天图片时加载更清晰的预览图。预览图只在用户主动查看时拉取，避免聊天列表自动下载大图。
    func previewImage(for item: DirectoryItem, forceReload: Bool = false) async -> NSImage? {
        if item.isImageFile {
            return await previewImageFromCacheOrServer(item, forceReload: forceReload)
        }
        return await thumbnail(for: item)
    }

    /// 加载聊天图片大图。优先使用原始图片保证文字清晰；原图缺失时再回退派生预览图。
    func previewImage(for attachment: ChatImageAttachment, forceReload: Bool = false) async -> NSImage? {
        let candidates = attachment.previewCandidateDirectoryItems()
        for (index, item) in candidates.enumerated() {
            if index > 0 {
                print("[ImagePreview] 原图加载失败，回退派生预览图: originalFileId=\(attachment.fileId), fallbackFileId=\(item.id), fileName=\(attachment.fileName)")
            }
            if let image = await previewImage(for: item, forceReload: forceReload) {
                return image
            }
        }
        print("[ImagePreview] 聊天图片大图加载失败: fileId=\(attachment.fileId), previewFileId=\(attachment.previewFileId?.description ?? "nil"), fileName=\(attachment.fileName)")
        return nil
    }

    private func previewImageFromCacheOrServer(_ item: DirectoryItem, forceReload: Bool) async -> NSImage? {
        if forceReload {
            deletePreviewCache(fileId: item.id)
        } else if let cached = cachedPreviewImage(for: item.id) {
            return cached
        }

        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            guard let data = await loadImageDataFromServer(item) else {
                print("[ImagePreview] 图片预览拉取失败: attempt=\(attempt), fileId=\(item.id), fileName=\(item.fileName)")
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                continue
            }

            if let image = Self.decodeImageData(data) {
                previewMemCache.setObject(image, forKey: NSNumber(value: item.id))
                savePreviewImageData(data, for: item.id)
                return image
            }

            print("[ImagePreview] 图片预览解码失败: attempt=\(attempt), fileId=\(item.id), fileName=\(item.fileName), bytes=\(data.count), signature=\(Self.dataSignature(data))")
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }

        return nil
    }

    private func cachedPreviewImage(for fileId: Int64) -> NSImage? {
        let key = NSNumber(value: fileId)
        if let image = previewMemCache.object(forKey: key) {
            return image
        }

        let path = previewDiskPath(for: fileId)
        guard let data = try? Data(contentsOf: path),
              let image = Self.decodeImageData(data) else {
            try? FileManager.default.removeItem(at: path)
            return nil
        }

        previewMemCache.setObject(image, forKey: key)
        return image
    }

    private func savePreviewImageData(_ data: Data, for fileId: Int64) {
        guard !data.isEmpty else { return }
        let path = previewDiskPath(for: fileId)
        try? data.write(to: path, options: .atomic)
    }

    private func deletePreviewCache(fileId: Int64) {
        previewMemCache.removeObject(forKey: NSNumber(value: fileId))
        try? FileManager.default.removeItem(at: previewDiskPath(for: fileId))
    }

    private func finishLoad(fileId: Int64, img: NSImage?, path: URL, key: NSNumber) {
        activeCount -= 1
        inFlight.removeValue(forKey: fileId)
        signalLoadSlotIfNeeded()
        guard let img else { return }
        memCache.setObject(img, forKey: key)
        saveJPEG(img, to: path)
    }

    private func isUsableImageThumbnail(_ image: NSImage) -> Bool {
        max(image.size.width, image.size.height) >= 240
    }

    // MARK: - 预加载（文件列表刷新后批量触发）

    /// 对列表中的图片/视频文件异步预加载缩略图，已缓存则跳过。
    /// 在非 actor 上下文中调用（如 Task {}），所有操作在后台完成，不触碰 UI。
    func prefetch(items: [DirectoryItem]) {
        for item in items where item.isImageFile || item.isVideoFile {
            let key = NSNumber(value: item.id)
            guard memCache.object(forKey: key) == nil,
                  !FileManager.default.fileExists(atPath: diskPath(for: item.id).path),
                  inFlight[item.id] == nil else { continue }
            prefetchQueue[item.id] = item
        }
        startPrefetchWorkerIfNeeded()
    }

    private func startPrefetchWorkerIfNeeded() {
        guard prefetchWorker == nil else { return }
        prefetchWorker = Task { [weak self] in
            await self?.drainPrefetchQueue()
        }
    }

    private func drainPrefetchQueue() async {
        while !Task.isCancelled {
            guard let item = prefetchQueue.values.first else {
                prefetchWorker = nil
                return
            }
            prefetchQueue.removeValue(forKey: item.id)
            _ = await thumbnail(for: item)
        }
        prefetchWorker = nil
    }

    private func waitForLoadSlotIfNeeded() async {
        if activeCount < maxConcurrent { return }
        await withCheckedContinuation { continuation in
            loadSlotWaiters.append(continuation)
        }
    }

    private func signalLoadSlotIfNeeded() {
        guard activeCount < maxConcurrent, !loadSlotWaiters.isEmpty else { return }
        let waiter = loadSlotWaiters.removeFirst()
        waiter.resume()
    }

    // MARK: - 本地文件直接生成缩略图（提交上传任务时调用）

    /// 根据本地文件生成缩略图，以 taskId 为 key 写入磁盘。
    /// 必须在 URL 安全访问权限有效期内调用（即 submit 时机）。
    /// 上传完成拿到 fileId 后，调用 remapToFileId 完成 key 迁移。
    func buildFromLocal(taskId: String, fileUrl: URL, fileName: String) async {
        upsertLedger(taskId: taskId, state: .thumbnailPending)
        let path = taskDiskPath(for: taskId)
        if FileManager.default.fileExists(atPath: path.path) {
            upsertLedger(taskId: taskId, state: .thumbnailReady)
            print("[Thumbnail] 跳过生成，已有临时缓存: taskId=\(taskId)")
            if let fileId = remapLedger[taskId]?.fileId {
                startRemapTaskIfNeeded(taskId: taskId, fileId: fileId)
            }
            return
        }

        let ext = (fileName as NSString).pathExtension.lowercased()
        let isVideoFile = Self.supportedLocalVideoExtensions.contains(ext)
        let img: NSImage?
        if ["jpg", "jpeg", "png", "gif", "bmp"].contains(ext) {
            img = NSImage(contentsOf: fileUrl).map { scaled($0) }
        } else if isVideoFile {
            img = await extractFrameFromLocalVideo(url: fileUrl)
        } else {
            print("[Thumbnail] 不支持的文件类型，跳过: \(fileName)")
            return
        }

        guard let thumbnail = img else {
            upsertLedger(taskId: taskId, state: .thumbnailFailed, lastError: "extract_failed")
            print("[Thumbnail] 本地缩略图提取失败: \(fileName)")
            return
        }
        let normalizedThumbnail: NSImage
        if isVideoFile {
            normalizedThumbnail = Self.isFullHD(thumbnail.size) ? thumbnail : normalizedToFullHD(thumbnail)
        } else {
            normalizedThumbnail = thumbnail
        }
        // 视频缩略图使用更高 JPEG 质量，减少细节损失。
        saveJPEG(normalizedThumbnail, to: path, compressionFactor: isVideoFile ? 0.95 : 0.85)
        taskMemCache.setObject(normalizedThumbnail, forKey: taskCacheKey(for: taskId))
        upsertLedger(taskId: taskId, state: .thumbnailReady)
        print("[Thumbnail] 本地缩略图生成完成: taskId=\(taskId), file=\(fileName)")
        if isVideoFile {
            let diskRecorded = FileManager.default.fileExists(atPath: path.path)
            let memRecorded = taskMemCache.object(forKey: taskCacheKey(for: taskId)) != nil
            if diskRecorded && memRecorded {
                print(Self.thumbnailProcessingCompletedLog(
                    fileName: fileName,
                    thumbnailPath: path.path,
                    taskId: taskId
                ))
            }
        }

        // 若上传结果已返回 fileId，则补偿触发 remap（不阻塞上传主链）。
        if let fileId = remapLedger[taskId]?.fileId {
            startRemapTaskIfNeeded(taskId: taskId, fileId: fileId)
        }
    }

    func markUploadSucceeded(taskId: String, fileId: Int64?) {
        guard let fileId, fileId > 0 else {
            upsertLedger(taskId: taskId, state: .uploadSucceededNoFileId)
            print("[Thumbnail] 上传完成但 fileId 无效，保留 taskId 缓存: taskId=\(taskId), fileId=\(fileId?.description ?? "nil")")
            return
        }
        upsertLedger(taskId: taskId, fileId: fileId, state: .uploadSucceeded)
        startRemapTaskIfNeeded(taskId: taskId, fileId: fileId)
    }

    private func startRemapTaskIfNeeded(taskId: String, fileId: Int64) {
        guard fileId > 0 else { return }
        guard !remapInFlight.contains(taskId) else { return }
        remapInFlight.insert(taskId)
        upsertLedger(taskId: taskId, fileId: fileId, state: .remapPending)
        let service = self
        Task {
            let success = await service.remapToFileIdWithRetry(taskId: taskId, fileId: fileId)
            await service.finishRemapTask(taskId: taskId, success: success, fileId: fileId)
        }
    }

    private func finishRemapTask(taskId: String, success: Bool, fileId: Int64) {
        remapInFlight.remove(taskId)
        if success {
            upsertLedger(taskId: taskId, fileId: fileId, state: .remapDone)
        }
    }

    /// 向后兼容：保留原入口，改为后台重试 remap。
    func remapToFileId(taskId: String, fileId: Int64) {
        markUploadSucceeded(taskId: taskId, fileId: fileId)
    }

    /// 上传完成后，将 taskId-key 的缩略图迁移到 fileId-key。该方法仅在后台任务中调用。
    @discardableResult
    func remapToFileIdWithRetry(
        taskId: String,
        fileId: Int64,
        timeoutSeconds: TimeInterval = 30.0,
        pollIntervalSeconds: TimeInterval = 0.5
    ) async -> Bool {
        guard fileId > 0 else {
            upsertLedger(taskId: taskId, state: .uploadSucceededNoFileId, lastError: "invalid_file_id")
            return false
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if remapToFileIdOnce(taskId: taskId, fileId: fileId) {
                return true
            }
            upsertLedger(taskId: taskId, fileId: fileId, state: .remapRetrying, incrementAttempts: true, lastError: "temp_missing_or_target_exists")
            try? await Task.sleep(nanoseconds: UInt64(max(0.1, pollIntervalSeconds) * 1_000_000_000))
        }
        upsertLedger(taskId: taskId, fileId: fileId, state: .remapExhausted, lastError: "retry_timeout")
        print("[Thumbnail] remap 超时放弃: taskId=\(taskId), fileId=\(fileId)")
        return false
    }

    private func remapToFileIdOnce(taskId: String, fileId: Int64) -> Bool {
        let taskPath = taskDiskPath(for: taskId)
        let filePath = diskPath(for: fileId)

        // 目标已存在时视为成功，避免重复迁移导致失败噪音。
        if FileManager.default.fileExists(atPath: filePath.path) {
            if let img = Self.decodeImage(at: filePath) {
                memCache.setObject(img, forKey: NSNumber(value: fileId))
            }
            taskMemCache.removeObject(forKey: taskCacheKey(for: taskId))
            return true
        }

        guard FileManager.default.fileExists(atPath: taskPath.path) else {
            return false
        }

        do {
            try FileManager.default.moveItem(at: taskPath, to: filePath)
            // 同时写入内存缓存，文件列表下次渲染直接命中
            if let taskImg = taskMemCache.object(forKey: taskCacheKey(for: taskId)) {
                memCache.setObject(taskImg, forKey: NSNumber(value: fileId))
                taskMemCache.removeObject(forKey: taskCacheKey(for: taskId))
            } else if let img = Self.decodeImage(at: filePath) {
                memCache.setObject(img, forKey: NSNumber(value: fileId))
            }
            print("[Thumbnail] remap 完成: taskId=\(taskId) → fileId=\(fileId)")
            return true
        } catch {
            upsertLedger(taskId: taskId, fileId: fileId, state: .remapRetrying, incrementAttempts: true, lastError: error.localizedDescription)
            print("[Thumbnail] remap 失败: \(error)")
            return false
        }
    }

    // MARK: - 从服务端加载

    private func loadFromServer(_ item: DirectoryItem) async -> NSImage? {
        if item.isImageFile {
            return await loadImageFromServer(item)
        } else if item.isVideoFile {
            return await loadVideoThumbnailFromServer(item)
        }
        return nil
    }

    // MARK: - 图片：按文件大小拉取完整图片后解码

    private func loadImageFromServer(_ item: DirectoryItem, maxDimension: CGFloat = 480) async -> NSImage? {
        guard let data = await loadImageDataFromServer(item),
              let img = Self.decodeImageData(data) else {
            return nil
        }
        return scaled(img, maxDimension: maxDimension)
    }

    private func loadImageDataFromServer(_ item: DirectoryItem) async -> Data? {
        let service = VideoStreamingService()
        let collector = ImageDataCollector()
        let fetchLength = Self.remoteImageFetchLength(fileSize: item.fileSize)
        do {
            let receivedBytes = try await service.startCustomVideoStreaming(
                fileId: item.id,
                startOffset: 0,
                length: fetchLength,
                delegate: collector
            )
            if receivedBytes != Int64(collector.collectedData().count) {
                print("[ImagePreview] 图片预览收流字节不一致: fileId=\(item.id), fileName=\(item.fileName), reported=\(receivedBytes), collected=\(collector.collectedData().count)")
            }
        } catch {
            print("[ImagePreview] 图片预览拉流异常: fileId=\(item.id), fileName=\(item.fileName), error=\(error.localizedDescription)")
            return nil
        }
        let data = collector.collectedData()
        guard !data.isEmpty else { return nil }
        if let fileSize = item.fileSize, fileSize > 0, Int64(data.count) < min(fileSize, fetchLength) {
            print("[ImagePreview] 图片预览数据不完整: fileId=\(item.id), fileName=\(item.fileName), expected=\(min(fileSize, fetchLength)), actual=\(data.count)")
            return nil
        }
        return data
    }

    // MARK: - 视频：AVAssetResourceLoader 按需拉取字节

    private func loadVideoThumbnailFromServer(_ item: DirectoryItem) async -> NSImage? {
        // 优先复用在线播放服务的 HTTP Range 地址。AVFoundation 可自行请求文件头、
        // 尾部 moov 和目标帧数据，避免把 requestsAllDataToEnd 请求截断后误报资源不完整。
        do {
            let playInfo = try await VideoPlaybackService.shared.requestPlayUrl(fileId: item.id)
            let asset = AVURLAsset(url: playInfo.playUrl)
            if let image = await generateRemoteVideoThumbnail(
                asset: asset,
                fileName: item.fileName,
                timeoutSeconds: 30
            ) {
                return image
            }
            print("[Thumbnail] HTTP Range 抽帧失败，回退 range_pull: file=\(item.fileName), id=\(item.id)")
        } catch {
            print("[Thumbnail] 获取缩略图播放地址失败，回退 range_pull: file=\(item.fileName), error=\(error.localizedDescription)")
        }

        return await loadVideoThumbnailViaRangePull(item)
    }

    private func loadVideoThumbnailViaRangePull(_ item: DirectoryItem) async -> NSImage? {
        guard let fileSize = item.fileSize, fileSize > 0 else {
            // ⚠️ 诊断日志：fileSize 为 nil 或 0 时无法构建 ResourceLoader（AVFoundation ContentInfo 必须知道文件总大小）
            // 若此日志频繁出现，检查服务端目录接口是否对所有文件都返回了 fileSize 字段。
            print("[Thumbnail] 跳过 \(item.fileName)(id=\(item.id))：fileSize=\(item.fileSize?.description ?? "nil")，无法构建 ResourceLoader")
            return nil
        }

        // 自定义 scheme 触发 ResourceLoader，AVFoundation 不会直接下载该 URL
        guard let assetURL = URL(string: "thumb://video/\(item.id)") else { return nil }

        let asset = AVURLAsset(url: assetURL)
        let loader = VideoThumbnailResourceLoader(
            fileId: item.id,
            fileSize: fileSize,
            fileName: item.fileName
        )
        let loaderQueue = DispatchQueue(label: "thumb.loader.\(item.id)")
        asset.resourceLoader.setDelegate(loader, queue: loaderQueue)

        let image = await generateRemoteVideoThumbnail(
            asset: asset,
            fileName: item.fileName,
            timeoutSeconds: 30
        )
        // AVAssetResourceLoader.setDelegate 只持有 delegate 的弱引用。
        withExtendedLifetime(loader) {}
        return image
    }

    private func generateRemoteVideoThumbnail(
        asset: AVAsset,
        fileName: String,
        timeoutSeconds: UInt64
    ) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 10, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 10, preferredTimescale: 600)

        // 只在开头几秒内采样：0/1/2/3s 数据均在首次 4MB 拉取范围内，不会触发大 chunk 请求。
        // 遇到亮度达标的帧立即短路返回，其余回调继续触发但不会二次 resume。
        let candidateTimes: [CMTime] = [0, 1, 2, 3].map {
            CMTime(seconds: $0, preferredTimescale: 600)
        }

        // 30 秒超时：与 generateCGImagesAsynchronously 竞速
        let cgImage = await withTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let lock = NSLock()
                    var bestCollected: CGImage? = nil   // 亮度最高的备选帧
                    var bestScore: Double = -1
                    var pending = candidateTimes.count
                    var hasResumed = false

                    generator.generateCGImagesAsynchronously(
                        forTimes: candidateTimes.map { NSValue(time: $0) }
                    ) { _, cgImage, _, result, error in
                        lock.lock()
                        if result == .succeeded, let img = cgImage {
                            let score = brightnessScore(img)
                            if score > bestScore {
                                bestScore = score
                                bestCollected = img
                            }
                            // 亮度充足则立即返回，不等后续帧
                            if score > 0.05 && !hasResumed {
                                hasResumed = true
                                lock.unlock()
                                continuation.resume(returning: img)
                                return
                            }
                        } else if result == .failed {
                            print("[Thumbnail] \(fileName) 帧提取失败，result=\(result.rawValue), error=\(error?.localizedDescription ?? "unknown")")
                        }
                        pending -= 1
                        let done = pending == 0 && !hasResumed
                        if done { hasResumed = true }
                        lock.unlock()

                        if done {
                            continuation.resume(returning: bestCollected)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return nil
            }
            // 取第一个返回的结果（帧提取完成或 30 秒超时）
            let first = await group.next()
            group.cancelAll()
            generator.cancelAllCGImageGeneration()
            return first ?? nil
        }

        guard let cgImage else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        return normalizedToFullHD(nsImage)
    }

    // MARK: - 本地视频帧提取

    private func extractFrameFromLocalVideo(url: URL) async -> NSImage? {
        if let ffmpegImage = await extractFrameFromLocalVideoWithFFmpeg(url: url) {
            return ffmpegImage
        }
        return await extractFrameFromLocalVideoWithAVAsset(url: url)
    }

    private func extractFrameFromLocalVideoWithFFmpeg(url: URL) async -> NSImage? {
        guard let ffmpegPath = resolveFFmpegPath() else {
            return nil
        }

        let ext = url.pathExtension.lowercased()
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
        let profile = Self.localVideoThumbnailProfile(fileSize: fileSize, fileExtension: ext)
        let outputURL = diskCacheDir.appendingPathComponent("ffmpeg_\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // 按文件规模/格式探测关键帧，输出统一 1080P 画质。
        for second in profile.seekPoints {
            let args = Self.buildFFmpegArguments(
                inputPath: url.path,
                outputPath: outputURL.path,
                seekSeconds: second,
                outputWidth: profile.outputWidth,
                outputHeight: profile.outputHeight,
                quality: profile.ffmpegQuality
            )

            let success = await runFFmpeg(
                executablePath: ffmpegPath,
                arguments: args,
                timeoutSeconds: profile.timeoutSeconds
            )
            guard success else { continue }
            guard let image = Self.decodeImage(at: outputURL) else { continue }
            print("[Thumbnail] ffmpeg 抽帧成功: file=\(url.lastPathComponent) seek=\(second)s")
            return normalizedToFullHD(image)
        }

        print("[Thumbnail] ffmpeg 抽帧失败，回退 AVAsset: file=\(url.lastPathComponent)")
        return nil
    }

    private func resolveFFmpegPath() -> String? {
        switch ffmpegAvailability {
        case .available(let path):
            return path
        case .unavailable:
            return nil
        case .unknown:
            let fileManager = FileManager.default
            for candidate in Self.ffmpegCandidatePaths(
                bundleResourcePath: Bundle.main.resourceURL?.path,
                bundlePath: Bundle.main.bundlePath,
                privateFrameworksPath: Bundle.main.privateFrameworksPath,
                pathEnv: ProcessInfo.processInfo.environment["PATH"]
            ) {
                if fileManager.isExecutableFile(atPath: candidate) {
                    ffmpegAvailability = .available(candidate)
                    return candidate
                }
            }
            ffmpegAvailability = .unavailable
            return nil
        }
    }

    private func runFFmpeg(executablePath: String, arguments: [String], timeoutSeconds: TimeInterval) async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return false
            }

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning {
                if Date() >= deadline {
                    process.terminate()
                    usleep(200_000)
                    if process.isRunning {
                        process.interrupt()
                    }
                    return false
                }
                usleep(100_000)
            }

            return process.terminationStatus == 0
        }.value
    }

    private func extractFrameFromLocalVideoWithAVAsset(url: URL) async -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        // 用 withTaskGroup 对 withCheckedContinuation 加 10 秒超时兜底。
        // 避免 AVFoundation 回调不触发时 Task 永远挂起。
        let cgImage: CGImage? = await withTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    generator.generateCGImagesAsynchronously(
                        forTimes: [NSValue(time: .zero)]
                    ) { _, cgImage, _, result, _ in
                        if result == .succeeded, let img = cgImage {
                            continuation.resume(returning: img)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s 超时
                generator.cancelAllCGImageGeneration()
                return nil
            }
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }

        guard let cgImage else { return nil }
        return normalizedToFullHD(NSImage(cgImage: cgImage, size: .zero))
    }

    // MARK: - 工具方法

    static func buildFFmpegArguments(
        inputPath: String,
        outputPath: String,
        seekSeconds: Int,
        outputWidth: Int,
        outputHeight: Int,
        quality: Int
    ) -> [String] {
        [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-ss", String(seekSeconds),
            "-i", inputPath,
            "-frames:v", "1",
            "-vf", "scale=\(outputWidth):\(outputHeight):force_original_aspect_ratio=decrease:flags=lanczos,pad=\(outputWidth):\(outputHeight):(ow-iw)/2:(oh-ih)/2:color=black",
            "-q:v", String(quality),
            outputPath
        ]
    }

    static func localVideoThumbnailProfile(fileSize: Int64?, fileExtension: String) -> LocalVideoThumbnailProfile {
        let ext = fileExtension.lowercased()
        let size = max(0, fileSize ?? 0)

        // 超大文件或容器复杂格式：更保守的抽帧点与更高质量。
        if size >= 2_000_000_000 || ["mkv", "mov", "avi", "ts", "m2ts"].contains(ext) {
            return LocalVideoThumbnailProfile(
                seekPoints: [5, 12, 20],
                ffmpegQuality: 2,
                timeoutSeconds: 45,
                outputWidth: 1920,
                outputHeight: 1080
            )
        }
        if size >= 800_000_000 {
            return LocalVideoThumbnailProfile(
                seekPoints: [3, 10, 16],
                ffmpegQuality: 2,
                timeoutSeconds: 35,
                outputWidth: 1920,
                outputHeight: 1080
            )
        }
        if size >= 200_000_000 {
            return LocalVideoThumbnailProfile(
                seekPoints: [3, 8, 12],
                ffmpegQuality: 3,
                timeoutSeconds: 30,
                outputWidth: 1920,
                outputHeight: 1080
            )
        }
        return LocalVideoThumbnailProfile(
            seekPoints: [2, 5, 8],
            ffmpegQuality: 3,
            timeoutSeconds: 20,
            outputWidth: 1920,
            outputHeight: 1080
        )
    }

    static func ffmpegCandidatePaths(
        bundleResourcePath: String?,
        bundlePath: String?,
        privateFrameworksPath: String?,
        pathEnv: String?
    ) -> [String] {
        var candidates: [String] = []

        // App 内置 ffmpeg（优先）
        if let bundleResourcePath, !bundleResourcePath.isEmpty {
            candidates.append(bundleResourcePath + "/ffmpeg")
            candidates.append(bundleResourcePath + "/tools/ffmpeg")
            candidates.append(bundleResourcePath + "/ffmpeg/bin/ffmpeg")
        }
        if let privateFrameworksPath, !privateFrameworksPath.isEmpty {
            candidates.append(privateFrameworksPath + "/ffmpeg")
        }
        if let bundlePath, !bundlePath.isEmpty {
            candidates.append(bundlePath + "/Contents/MacOS/ffmpeg")
            candidates.append(bundlePath + "/Contents/Frameworks/ffmpeg")
            candidates.append(bundlePath + "/Contents/Resources/ffmpeg")
        }

        // 系统路径兜底
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ])

        if let pathEnv, !pathEnv.isEmpty {
            let fromEnv = pathEnv
                .split(separator: ":")
                .map { String($0) + "/ffmpeg" }
            candidates.append(contentsOf: fromEnv)
        }

        // 去重，保持先后优先级。
        var deduped: [String] = []
        for path in candidates where !deduped.contains(path) {
            deduped.append(path)
        }
        return deduped
    }

    private static func thumbnailProcessingCompletedLog(fileName: String, thumbnailPath: String, taskId: String) -> String {
        "[Thumbnail] 视频缩略图处理完成 | 文件名称: \(fileName) | 缩略图文件位置: \(thumbnailPath) | 上传任务Id: \(taskId)"
    }

    private static func isFullHD(_ size: CGSize) -> Bool {
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        return w == 1920 && h == 1080
    }

    private func normalizedToFullHD(_ image: NSImage) -> NSImage {
        let target = NSImage(size: Self.fullHDSize)
        target.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: Self.fullHDSize)).fill()

        let srcSize = image.size
        let srcW = max(1, srcSize.width)
        let srcH = max(1, srcSize.height)
        let scale = min(Self.fullHDSize.width / srcW, Self.fullHDSize.height / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawX = (Self.fullHDSize.width - drawW) / 2.0
        let drawY = (Self.fullHDSize.height - drawH) / 2.0

        image.draw(
            in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        target.unlockFocus()
        return target
    }

    private func saveJPEG(_ image: NSImage, to url: URL, compressionFactor: Double = 0.8) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
        else { return }
        try? jpeg.write(to: url)
    }

    func deleteFromCache(fileId: Int64) {
        let key = NSNumber(value: fileId)
        memCache.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: diskPath(for: fileId))
        deletePreviewCache(fileId: fileId)
    }

    /// 返回可以安全清理的缩略图磁盘缓存大小。
    /// task_ 前缀文件与迁移账本属于上传/补偿流程，必须保留。
    func clearableCacheSize() -> Int64 {
        let thumbnailBytes = Self.fileSize(in: diskCacheDir) { file in
            file.pathExtension == "jpg" && !file.lastPathComponent.hasPrefix("task_")
        }
        let previewBytes = Self.fileSize(in: previewDiskCacheDir) { _ in true }
        return thumbnailBytes + previewBytes
    }

    /// 清理普通缩略图和图片预览，保留上传任务临时图及迁移账本。
    @discardableResult
    func clearAllCache() -> Int64 {
        let clearableBytes = clearableCacheSize()
        memCache.removeAllObjects()
        previewMemCache.removeAllObjects()
        // taskMemCache 与上传任务/缩略图 remap 共用，清理时保留以免打断进行中的任务。
        let files = (try? FileManager.default.contentsOfDirectory(
            at: diskCacheDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" && !file.lastPathComponent.hasPrefix("task_") {
            try? FileManager.default.removeItem(at: file)
        }
        let previewFiles = (try? FileManager.default.contentsOfDirectory(
            at: previewDiskCacheDir, includingPropertiesForKeys: nil)) ?? []
        for file in previewFiles {
            try? FileManager.default.removeItem(at: file)
        }
        print("[Thumbnail] 普通缩略图缓存已清理，共释放约 \(clearableBytes) 字节")
        return clearableBytes
    }

    private static func fileSize(in directory: URL, where predicate: (URL) -> Bool) -> Int64 {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.reduce(into: Int64(0)) { total, file in
            guard predicate(file),
                  let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true else { return }
            total += Int64(values.fileSize ?? 0)
        }
    }

    // MARK: - Test Hooks

    static func debugFFmpegArguments(
        inputPath: String,
        outputPath: String,
        seekSeconds: Int,
        outputWidth: Int = 1920,
        outputHeight: Int = 1080,
        quality: Int = 2
    ) -> [String] {
        buildFFmpegArguments(
            inputPath: inputPath,
            outputPath: outputPath,
            seekSeconds: seekSeconds,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            quality: quality
        )
    }

    static func debugLocalVideoThumbnailProfile(fileSize: Int64?, fileExtension: String) -> LocalVideoThumbnailProfile {
        localVideoThumbnailProfile(fileSize: fileSize, fileExtension: fileExtension)
    }

    static func debugRemoteImageFetchLength(fileSize: Int64?) -> Int64 {
        remoteImageFetchLength(fileSize: fileSize)
    }

    private static func remoteImageFetchLength(fileSize: Int64?) -> Int64 {
        guard let fileSize, fileSize > 0 else {
            return fallbackRemoteImageFetchLength
        }
        return fileSize
    }

    private static func decodeImageData(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [
                    kCGImageSourceShouldCache: true,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
              ) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private static func decodeImage(at url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decodeImageData(data)
    }

    private static func dataSignature(_ data: Data) -> String {
        data.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func debugIsFullHD(width: CGFloat, height: CGFloat) -> Bool {
        isFullHD(CGSize(width: width, height: height))
    }

    static func debugThumbnailProcessingCompletedLog(fileName: String, thumbnailPath: String, taskId: String) -> String {
        thumbnailProcessingCompletedLog(fileName: fileName, thumbnailPath: thumbnailPath, taskId: taskId)
    }

    static func debugFFmpegCandidatePaths(pathEnv: String?) -> [String] {
        ffmpegCandidatePaths(
            bundleResourcePath: nil,
            bundlePath: nil,
            privateFrameworksPath: nil,
            pathEnv: pathEnv
        )
    }

    static func debugFFmpegCandidatePaths(
        bundleResourcePath: String?,
        bundlePath: String?,
        privateFrameworksPath: String?,
        pathEnv: String?
    ) -> [String] {
        ffmpegCandidatePaths(
            bundleResourcePath: bundleResourcePath,
            bundlePath: bundlePath,
            privateFrameworksPath: privateFrameworksPath,
            pathEnv: pathEnv
        )
    }

    func debugMarkThumbnailReady(taskId: String) {
        upsertLedger(taskId: taskId, state: .thumbnailReady)
    }

    func debugMarkUploadSucceeded(taskId: String, fileId: Int64?) {
        guard let fileId else {
            upsertLedger(taskId: taskId, state: .uploadSucceededNoFileId)
            return
        }
        upsertLedger(taskId: taskId, fileId: fileId, state: .uploadSucceeded)
    }

    func debugLedgerRecord(taskId: String) -> ThumbnailRemapRecord? {
        remapLedger[taskId]
    }

    func debugPendingRemapTaskIds() -> [String] {
        remapLedger.values
            .filter { shouldAttemptRemap(record: $0) }
            .map { $0.taskId }
            .sorted()
    }
}

// MARK: - 亮度评分（越高越好，用于过滤黑屏帧）

/// 将图像缩到 16×16 后计算平均亮度，范围 0.0（全黑）～ 1.0（全白）。
/// 采样分辨率低，运行很快，足以区分有效画面与黑屏。
private func brightnessScore(_ image: CGImage) -> Double {
    let side = 16
    guard let ctx = CGContext(
        data: nil, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 0 }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let ptr = ctx.data else { return 0 }
    let buf = ptr.bindMemory(to: UInt8.self, capacity: side * side * 4)
    var sum: Double = 0
    for i in 0..<(side * side) {
        let b = i * 4
        sum += 0.299 * Double(buf[b]) + 0.587 * Double(buf[b+1]) + 0.114 * Double(buf[b+2])
    }
    return sum / (255.0 * Double(side * side))
}

// MARK: - 缩放辅助（独立函数，可在 actor 外调用）

private func scaled(_ image: NSImage, maxDimension: CGFloat = 480) -> NSImage {
    let srcWidth = max(1, image.size.width)
    let srcHeight = max(1, image.size.height)
    let scale = min(maxDimension / srcWidth, maxDimension / srcHeight, 1)
    let size = CGSize(width: srcWidth * scale, height: srcHeight * scale)
    let target = NSImage(size: size)
    target.lockFocus()
    image.draw(in: CGRect(origin: .zero, size: size),
               from: .zero,
               operation: .copy,
               fraction: 1.0)
    target.unlockFocus()
    return target
}

// MARK: - ImageDataCollector

private final class ImageDataCollector: VideoStreamLoaderDelegate {
    private var buffer = Data()
    private let lock = NSLock()

    func didReceiveContentInfo(totalSize: Int64, mimeType: String) {}
    func didReceiveVideoData(_ data: Data, range: Range<Int64>) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }
    func didFinishLoading() {}
    func didFail(with error: Error) {}

    func collectedData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
