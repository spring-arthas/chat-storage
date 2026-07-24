//
//  CacheCleanupService.swift
//  chat-storage
//

import Combine
import Foundation

enum CacheSizeFormatter {
    static func string(fromByteCount bytes: Int64) -> String {
        guard bytes != 0 else { return "0" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct CacheStorageSummary: Equatable {
    var thumbnailsBytes: Int64 = 0
    var videoBytes: Int64 = 0
    var uploadMD5Bytes: Int64 = 0
    var chatAttachmentsBytes: Int64 = 0

    var totalBytes: Int64 {
        thumbnailsBytes + videoBytes + uploadMD5Bytes + chatAttachmentsBytes
    }
}

struct CacheCleanupResult: Equatable {
    let clearedBytes: Int64
    let skippedBytes: Int64
    let failedPaths: [String]

    var hasFailures: Bool { !failedPaths.isEmpty }
}

/// 统一管理客户端可清理缓存。
///
/// 这里明确不触碰头像 NSCache、Core Data 记录、云盘任务、下载目录和服务端文件。
@MainActor
final class CacheCleanupService: ObservableObject {
    static let shared = CacheCleanupService()

    @Published private(set) var summary = CacheStorageSummary()
    @Published private(set) var isWorking = false

    private let fileManager = FileManager.default

    private init() {}

    func refreshSummary() async {
        let thumbnails = await FileThumbnailService.shared.clearableCacheSize()
        let videos = VideoStreamCacheManager.shared.inactiveTemporaryCacheSize()
        let md5 = FileTransferService.uploadMD5CacheSize()
        let attachments = chatAttachmentClearableSize()
        summary = CacheStorageSummary(
            thumbnailsBytes: thumbnails,
            videoBytes: videos,
            uploadMD5Bytes: md5,
            chatAttachmentsBytes: attachments
        )
    }

    @discardableResult
    func clearCaches() async -> CacheCleanupResult {
        guard !isWorking else {
            return CacheCleanupResult(clearedBytes: 0, skippedBytes: 0, failedPaths: [])
        }

        isWorking = true
        defer { isWorking = false }

        let thumbnails = await FileThumbnailService.shared.clearAllCache()
        let videos = VideoStreamCacheManager.shared.clearInactiveTemporaryCaches()
        let md5 = FileTransferService.clearUploadMD5Cache()
        let attachments = clearChatAttachmentCache()
        let result = CacheCleanupResult(
            clearedBytes: thumbnails + videos + md5 + attachments.clearedBytes,
            skippedBytes: attachments.skippedBytes,
            failedPaths: attachments.failedPaths
        )

        await refreshSummary()
        return result
    }

    private static var chatAttachmentCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("chat-storage/chat-attachments", isDirectory: true)
    }

    private static var chatAttachmentStableDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("chat-storage/chat-attachments", isDirectory: true)
    }

    private func chatAttachmentClearableSize() -> Int64 {
        let protectedPaths = ChatAttachmentTransferStore.shared.protectedLocalAttachmentPaths()
        let stableBytes = clearableBytes(
            in: Self.chatAttachmentStableDirectory,
            excluding: protectedPaths
        )

        let hasTransferWork = ChatAttachmentTransferCoordinator.shared.hasPendingOrActiveJobs
        let cacheBytes = hasTransferWork
            ? 0
            : clearableBytes(in: Self.chatAttachmentCacheDirectory, excluding: [])
        return stableBytes + cacheBytes
    }

    private func clearChatAttachmentCache() -> (clearedBytes: Int64, skippedBytes: Int64, failedPaths: [String]) {
        let protectedPaths = ChatAttachmentTransferStore.shared.protectedLocalAttachmentPaths()
        var clearedBytes: Int64 = 0
        var skippedBytes: Int64 = 0
        var failedPaths: [String] = []

        let stableResult = clearDirectory(
            Self.chatAttachmentStableDirectory,
            excluding: protectedPaths
        )
        clearedBytes += stableResult.clearedBytes
        skippedBytes += stableResult.skippedBytes
        failedPaths.append(contentsOf: stableResult.failedPaths)

        let cacheDirectory = Self.chatAttachmentCacheDirectory
        if ChatAttachmentTransferCoordinator.shared.hasPendingOrActiveJobs {
            skippedBytes += directorySize(cacheDirectory)
        } else {
            let cacheResult = clearDirectory(cacheDirectory, excluding: [])
            clearedBytes += cacheResult.clearedBytes
            skippedBytes += cacheResult.skippedBytes
            failedPaths.append(contentsOf: cacheResult.failedPaths)
        }

        return (clearedBytes, skippedBytes, failedPaths)
    }

    private func clearDirectory(
        _ directory: URL,
        excluding protectedPaths: Set<String>
    ) -> (clearedBytes: Int64, skippedBytes: Int64, failedPaths: [String]) {
        guard fileManager.fileExists(atPath: directory.path) else {
            return (0, 0, [])
        }

        var clearedBytes: Int64 = 0
        var skippedBytes: Int64 = 0
        var failedPaths: [String] = []
        let children = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for child in children {
            let childPath = child.standardizedFileURL.path
            let isDirectory = isDirectory(child)
            if isDirectory {
                let containsProtectedPath = protectedPaths.contains { protected in
                    protected == childPath || protected.hasPrefix(childPath + "/")
                }
                if !containsProtectedPath {
                    let size = directorySize(child)
                    do {
                        try fileManager.removeItem(at: child)
                        clearedBytes += size
                    } catch {
                        skippedBytes += size
                        failedPaths.append(child.path)
                    }
                    continue
                }

                let nested = clearDirectory(child, excluding: protectedPaths)
                clearedBytes += nested.clearedBytes
                skippedBytes += nested.skippedBytes
                failedPaths.append(contentsOf: nested.failedPaths)
                continue
            }

            let size = fileSize(child)
            if protectedPaths.contains(childPath) {
                skippedBytes += size
                continue
            }
            do {
                try fileManager.removeItem(at: child)
                clearedBytes += size
            } catch {
                skippedBytes += size
                failedPaths.append(child.path)
            }
        }

        return (clearedBytes, skippedBytes, failedPaths)
    }

    private func clearableBytes(in directory: URL, excluding protectedPaths: Set<String>) -> Int64 {
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var total: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            guard !isDirectory(file),
                  !protectedPaths.contains(file.standardizedFileURL.path) else { continue }
            total += fileSize(file)
        }
        return total
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private func directorySize(_ directory: URL) -> Int64 {
        clearableBytes(in: directory, excluding: [])
    }

    private func fileSize(_ file: URL) -> Int64 {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return 0 }
        return Int64(size)
    }
}
