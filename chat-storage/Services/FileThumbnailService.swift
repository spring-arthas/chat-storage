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

actor FileThumbnailService {
    static let shared = FileThumbnailService()

    // MARK: - 缓存

    private let memCache = NSCache<NSNumber, NSImage>()
    private let diskCacheDir: URL

    // MARK: - 并发控制

    /// 同一 fileId 正在加载时，后来的请求直接等待同一个 Task 的结果
    private var inFlight: [Int64: Task<NSImage?, Never>] = [:]
    /// 同时进行的加载任务上限（每个视频任务内部可能再创建多个 socket，不受此限制）
    private var activeCount = 0
    private let maxConcurrent = 3

    // MARK: - Init

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDir = caches.appendingPathComponent("chat-storage/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
        memCache.countLimit = 200
    }

    // MARK: - 磁盘路径

    private func diskPath(for fileId: Int64) -> URL {
        diskCacheDir.appendingPathComponent("\(fileId).jpg")
    }

    /// 上传任务进行中时，以 taskId 为 key 的临时磁盘路径
    private func taskDiskPath(for taskId: String) -> URL {
        diskCacheDir.appendingPathComponent("task_\(taskId).jpg")
    }

    // MARK: - 核心查询方法

    /// 返回 fileId 对应的缩略图。优先内存→磁盘→网络，结果自动写入两级缓存。
    func thumbnail(for item: DirectoryItem) async -> NSImage? {
        let key = NSNumber(value: item.id)

        // 1. 内存命中
        if let img = memCache.object(forKey: key) { return img }

        // 2. 磁盘命中
        let path = diskPath(for: item.id)
        if let img = NSImage(contentsOf: path) {
            memCache.setObject(img, forKey: key)
            return img
        }

        // 3. 已有 in-flight 任务则等待
        if let existing = inFlight[item.id] {
            return await existing.value
        }

        // 4. 并发限制：轮询等待空位
        while activeCount >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

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

    private func finishLoad(fileId: Int64, img: NSImage?, path: URL, key: NSNumber) {
        activeCount -= 1
        inFlight.removeValue(forKey: fileId)
        guard let img else { return }
        memCache.setObject(img, forKey: key)
        saveJPEG(img, to: path)
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
            Task { await thumbnail(for: item) }
        }
    }

    // MARK: - 本地文件直接生成缩略图（提交上传任务时调用）

    /// 根据本地文件生成缩略图，以 taskId 为 key 写入磁盘。
    /// 必须在 URL 安全访问权限有效期内调用（即 submit 时机）。
    /// 上传完成拿到 fileId 后，调用 remapToFileId 完成 key 迁移。
    func buildFromLocal(taskId: String, fileUrl: URL, fileName: String) async {
        let path = taskDiskPath(for: taskId)
        guard !FileManager.default.fileExists(atPath: path.path) else {
            print("[Thumbnail] 跳过生成，已有临时缓存: taskId=\(taskId)")
            return
        }

        let ext = (fileName as NSString).pathExtension.lowercased()
        let img: NSImage?
        if ["jpg", "jpeg", "png", "gif", "bmp"].contains(ext) {
            img = NSImage(contentsOf: fileUrl).map { scaled($0) }
        } else if ["mp4", "m4v", "mov", "avi", "mkv"].contains(ext) {
            img = await extractFrameFromLocalVideo(url: fileUrl)
        } else {
            print("[Thumbnail] 不支持的文件类型，跳过: \(fileName)")
            return
        }

        guard let thumbnail = img else {
            print("[Thumbnail] 本地缩略图提取失败: \(fileName)")
            return
        }
        saveJPEG(thumbnail, to: path)
        print("[Thumbnail] 本地缩略图生成完成: taskId=\(taskId), file=\(fileName)")
    }

    /// 上传完成后，将 taskId-key 的磁盘缩略图迁移到 fileId-key，供文件列表直接命中。
    func remapToFileId(taskId: String, fileId: Int64) {
        let taskPath = taskDiskPath(for: taskId)
        let filePath = diskPath(for: fileId)

        // fileId-key 已存在则无需迁移
        guard FileManager.default.fileExists(atPath: taskPath.path),
              !FileManager.default.fileExists(atPath: filePath.path) else {
            print("[Thumbnail] remap 跳过: taskId=\(taskId), fileId=\(fileId), taskPath存在=\(FileManager.default.fileExists(atPath: taskPath.path)), fileIdPath存在=\(FileManager.default.fileExists(atPath: filePath.path))")
            return
        }

        do {
            try FileManager.default.moveItem(at: taskPath, to: filePath)
            // 同时写入内存缓存，文件列表下次渲染直接命中
            if let img = NSImage(contentsOf: filePath) {
                memCache.setObject(img, forKey: NSNumber(value: fileId))
            }
            print("[Thumbnail] remap 完成: taskId=\(taskId) → fileId=\(fileId)")
        } catch {
            print("[Thumbnail] remap 失败: \(error)")
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

    // MARK: - 图片：拉取前 256KB 字节后解码

    private func loadImageFromServer(_ item: DirectoryItem) async -> NSImage? {
        let service = VideoStreamingService()
        let collector = ImageDataCollector()
        do {
            try await service.startCustomVideoStreaming(
                fileId: item.id,
                startOffset: 0,
                length: 262144,  // 256 KB，足以覆盖大多数图片完整数据
                delegate: collector
            )
        } catch {
            return nil
        }
        let data = collector.collectedData()
        guard let img = NSImage(data: data) else { return nil }
        return scaled(img)
    }

    // MARK: - 视频：AVAssetResourceLoader 按需拉取字节

    private func loadVideoThumbnailFromServer(_ item: DirectoryItem) async -> NSImage? {
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
                    ) { _, cgImage, _, result, _ in
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
                            print("[Thumbnail] \(item.fileName) 帧提取失败，result=\(result.rawValue)")
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
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return nil
            }
            // 取第一个返回的结果（帧提取完成或 30 秒超时）
            let first = await group.next()
            group.cancelAll()
            generator.cancelAllCGImageGeneration()
            // ⚠️ 关键修复：强制 loader 存活到整个 withTaskGroup 闭包结束。
            // AVAssetResourceLoader.setDelegate 只持有 delegate 的 weak 引用。
            // 若 loader（局部变量）在 AVFoundation 发出 DataRequest 之前被 ARC
            // 释放，delegate 变为 nil，所有请求无人响应，导致帧提取始终失败。
            withExtendedLifetime(loader) {}
            return first ?? nil
        }

        guard let cgImage else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        return scaled(nsImage)
    }

    // MARK: - 本地视频帧提取

    private func extractFrameFromLocalVideo(url: URL) async -> NSImage? {
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
        return scaled(NSImage(cgImage: cgImage, size: .zero))
    }

    // MARK: - 工具方法

    private func saveJPEG(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return }
        try? jpeg.write(to: url)
    }

    func deleteFromCache(fileId: Int64) {
        let key = NSNumber(value: fileId)
        memCache.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: diskPath(for: fileId))
    }

    func clearAllCache() {
        memCache.removeAllObjects()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: diskCacheDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" {
            try? FileManager.default.removeItem(at: file)
        }
        print("[Thumbnail] 缓存已清空，共删除 \(files.count) 个文件")
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

private func scaled(_ image: NSImage, to size: CGSize = CGSize(width: 40, height: 40)) -> NSImage {
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
