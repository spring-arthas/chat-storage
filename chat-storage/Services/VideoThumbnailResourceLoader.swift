//
//  VideoThumbnailResourceLoader.swift
//  chat-storage
//
//  AVAssetResourceLoaderDelegate 实现，桥接 AVFoundation 的按需字节请求
//  与 VideoStreamingService 的服务端 range_pull 协议。
//
//  AVFoundation 提取视频帧时会自行决定需要哪些字节段（无论 moov 在头还是尾），
//  本类将这些请求逐一转换为独立的 range_pull 网络请求，并将数据交还 AVFoundation。
//
//  实战约束（大文件 moov 在尾部）：
//  若 allToEnd 请求只返回头部少量字节并长期保持开放，AVFoundation 在某些文件上
//  不会继续发出后续 range 请求，最终帧提取失败。
//  当前策略：每个请求返回当前可得字节后立即 finishLoading()，交由 AVFoundation
//  继续发起下一段请求（包含可能的尾部元数据请求）。
//

import Foundation
import AVFoundation

final class VideoThumbnailResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let fileId: Int64
    private let fileSize: Int64
    private let fileName: String

    /// 每个 loadingRequest 对应一个独立的 streaming service 实例（独立 socket）
    private var activeServices: [ObjectIdentifier: VideoStreamingService] = [:]

    /// 头尾预取与后续 request 的字节段缓存
    private var cachedSegments: [CachedSegment] = []
    /// 只执行一次的头尾预取任务
    private var prefetchTask: Task<Void, Never>?

    private let lock = NSLock()

    init(fileId: Int64, fileSize: Int64, fileName: String) {
        self.fileId = fileId
        self.fileSize = fileSize
        self.fileName = fileName
    }

    deinit {
        lock.lock()
        let services = activeServices.values
        activeServices.removeAll()
        lock.unlock()
        for service in services {
            service.cancel()
        }
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        // ① 回答 ContentInfo 查询（AVFoundation 首先问"文件多大、什么格式"）
        //    注意：某些 AVFoundation 版本会将 ContentInfo 和第一个 DataRequest
        //    均包含在同一个 loadingRequest 中。因此这里只填写内容信息，
        //    不调用 finishLoading()，而是继续尝试处理 DataRequest。
        if let contentInfoRequest = loadingRequest.contentInformationRequest {
            contentInfoRequest.contentLength = fileSize
            contentInfoRequest.isByteRangeAccessSupported = true
            contentInfoRequest.contentType = contentType(for: fileName)
            print("[Thumbnail] ContentInfo 响应 fileSize=\(fileSize) fileName=\(fileName)")
            // 如果没有伴随的 DataRequest，可以立即完成。
            if loadingRequest.dataRequest == nil {
                loadingRequest.finishLoading()
                return true
            }
            // 否则不 return，继续处理下面的 DataRequest。
        }

        guard let dataRequest = loadingRequest.dataRequest else {
            // 既无 contentInfoRequest 也无 dataRequest，不支持
            return false
        }

        let requestedOffset = dataRequest.requestedOffset
        // 单次请求上限 4MB，防止单次拉取过多数据
        let maxBytesPerRequest: Int64 = 4 * 1024 * 1024
        let available = max(0, fileSize - requestedOffset)
        let requestedLength: Int64
        if dataRequest.requestsAllDataToEndOfResource {
            requestedLength = min(maxBytesPerRequest, available)
        } else {
            requestedLength = min(Int64(dataRequest.requestedLength), available)
        }

        guard requestedLength > 0 else {
            // 超出文件尾部，立即完成
            loadingRequest.finishLoading()
            return true
        }

        print("[Thumbnail] DataRequest offset=\(requestedOffset) length=\(requestedLength) allToEnd=\(dataRequest.requestsAllDataToEndOfResource)")

        let key = ObjectIdentifier(loadingRequest)

        Task {
            // 方案 A：固定预取文件头 + 文件尾，适配 moov 在尾部的大文件。
            await self.ensureHeadTailPrefetched(maxBytesPerRequest: maxBytesPerRequest)

            if let cached = self.cachedData(offset: requestedOffset, length: requestedLength) {
                print("[Thumbnail] DataRequest 命中缓存 \(cached.count) 字节, offset=\(requestedOffset)")
                dataRequest.respond(with: cached)
                loadingRequest.finishLoading()
                if dataRequest.requestsAllDataToEndOfResource
                    && (requestedOffset + Int64(cached.count) < fileSize) {
                    print("[Thumbnail] DataRequest 分段完成 offset=\(requestedOffset) 共\(cached.count)字节，等待后续range请求")
                } else {
                    print("[Thumbnail] DataRequest 完整完成 offset=\(requestedOffset) 共\(cached.count)字节")
                }
                return
            }

            let service = VideoStreamingService()
            self.lock.lock()
            self.activeServices[key] = service
            self.lock.unlock()
            let collector = DataCollector()

            do {
                try await service.startCustomVideoStreaming(
                    fileId: fileId,
                    startOffset: requestedOffset,
                    length: requestedLength,
                    delegate: collector
                )
                let data = collector.collectedData()
                print("[Thumbnail] DataRequest 收到 \(data.count) 字节, offset=\(requestedOffset)")
                self.cacheDataSegment(offset: requestedOffset, data: data)
                dataRequest.respond(with: data)
                loadingRequest.finishLoading()
                if dataRequest.requestsAllDataToEndOfResource
                    && (requestedOffset + Int64(data.count) < fileSize) {
                    print("[Thumbnail] DataRequest 分段完成 offset=\(requestedOffset) 共\(data.count)字节，等待后续range请求")
                } else {
                    print("[Thumbnail] DataRequest 完整完成 offset=\(requestedOffset) 共\(data.count)字节")
                }
            } catch {
                print("[Thumbnail] DataRequest 错误: \(error)")
                loadingRequest.finishLoading(with: error)
            }
            self.lock.lock()
            self.activeServices.removeValue(forKey: key)
            self.lock.unlock()
        }

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let key = ObjectIdentifier(loadingRequest)
        lock.lock()
        let service = activeServices.removeValue(forKey: key)
        lock.unlock()
        // AVFoundation 已取消请求，不再 finishLoading(with:) 以免放大为全局失败。
        service?.cancel()
        print("[Thumbnail] didCancel: 清理请求 key=\(key)")
    }

    // MARK: - Helpers

    struct ByteRangeRequest {
        let offset: Int64
        let length: Int64
    }

    private struct CachedSegment {
        let offset: Int64
        let data: Data
        var endExclusive: Int64 { offset + Int64(data.count) }
    }

    static func prefetchRanges(fileSize: Int64, maxBytesPerRequest: Int64) -> [ByteRangeRequest] {
        guard fileSize > 0, maxBytesPerRequest > 0 else { return [] }
        let chunk = min(fileSize, maxBytesPerRequest)
        let head = ByteRangeRequest(offset: 0, length: chunk)
        if fileSize <= chunk {
            return [head]
        }
        let tailOffset = fileSize - chunk
        if tailOffset == 0 {
            return [head]
        }
        let tail = ByteRangeRequest(offset: tailOffset, length: chunk)
        return [head, tail]
    }

    private func ensureHeadTailPrefetched(maxBytesPerRequest: Int64) async {
        let ranges = Self.prefetchRanges(fileSize: fileSize, maxBytesPerRequest: maxBytesPerRequest)
        guard !ranges.isEmpty else { return }

        let taskToAwait: Task<Void, Never>
        lock.lock()
        if let existing = prefetchTask {
            taskToAwait = existing
            lock.unlock()
            await taskToAwait.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            for range in ranges {
                if let cached = self.cachedData(offset: range.offset, length: range.length), !cached.isEmpty {
                    continue
                }
                do {
                    let data = try await self.fetchData(offset: range.offset, length: range.length)
                    self.cacheDataSegment(offset: range.offset, data: data)
                    print("[Thumbnail] 预取完成 offset=\(range.offset) size=\(data.count)")
                } catch {
                    print("[Thumbnail] 预取失败 offset=\(range.offset) length=\(range.length): \(error)")
                }
            }
            self.lock.lock()
            self.prefetchTask = nil
            self.lock.unlock()
        }
        prefetchTask = task
        taskToAwait = task
        lock.unlock()
        await taskToAwait.value
    }

    private func fetchData(offset: Int64, length: Int64) async throws -> Data {
        let service = VideoStreamingService()
        let collector = DataCollector()
        try await service.startCustomVideoStreaming(
            fileId: fileId,
            startOffset: offset,
            length: length,
            delegate: collector
        )
        return collector.collectedData()
    }

    private func cacheDataSegment(offset: Int64, data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        let exists = cachedSegments.contains(where: { $0.offset == offset && $0.data.count == data.count })
        if !exists {
            cachedSegments.append(CachedSegment(offset: offset, data: data))
            if cachedSegments.count > 8 {
                cachedSegments.removeFirst(cachedSegments.count - 8)
            }
        }
        lock.unlock()
    }

    private func cachedData(offset: Int64, length: Int64) -> Data? {
        guard length > 0 else { return Data() }
        lock.lock()
        defer { lock.unlock() }
        guard let segment = cachedSegments.first(where: { segment in
            offset >= segment.offset && (offset + length) <= segment.endExclusive
        }) else {
            return nil
        }
        let start = Int(offset - segment.offset)
        let end = start + Int(length)
        return segment.data.subdata(in: start..<end)
    }

    /// 返回 AVAssetResourceLoadingContentInformationRequest 需要的 UTI 字符串（不是 MIME 类型）
    private func contentType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v": return "public.mpeg-4"
        case "mov":        return "com.apple.quicktime-movie"
        case "avi":        return "public.avi"
        case "mkv":        return "org.matroska.mkv"
        default:           return "public.mpeg-4"
        }
    }
}

// MARK: - DataCollector

/// 收集 VideoStreamingService 回调的所有数据片段
private final class DataCollector: VideoStreamLoaderDelegate {
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
