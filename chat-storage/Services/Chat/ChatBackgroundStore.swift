import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ChatBackgroundStore {
    static let shared = ChatBackgroundStore()

    enum StoreError: LocalizedError, Equatable {
        case invalidIdentity
        case invalidImage
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidIdentity:
                return "账号或好友标识无效。"
            case .invalidImage:
                return "所选文件不是有效的图片。"
            case .encodingFailed:
                return "无法处理所选图片。"
            }
        }
    }

    private let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "chat-storage"
            self.rootDirectory = applicationSupport
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent("ChatBackgrounds", isDirectory: true)
        }
    }

    func backgroundURL(accountId: Int64, friendId: Int64) -> URL {
        rootDirectory
            .appendingPathComponent(String(accountId), isDirectory: true)
            .appendingPathComponent(String(friendId), isDirectory: true)
            .appendingPathComponent("background.jpg", isDirectory: false)
    }

    func loadBackgroundData(accountId: Int64, friendId: Int64) -> Data? {
        guard Self.hasValidIdentity(accountId: accountId, friendId: friendId) else {
            return nil
        }

        let url = backgroundURL(accountId: accountId, friendId: friendId)
        guard
            let data = try? Data(contentsOf: url),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else {
            return nil
        }
        return data
    }

    func importBackground(from sourceURL: URL, accountId: Int64, friendId: Int64) throws -> Data {
        guard Self.hasValidIdentity(accountId: accountId, friendId: friendId) else {
            throw StoreError.invalidIdentity
        }

        let data = try Self.normalizedJPEGData(from: sourceURL)
        let destinationURL = backgroundURL(accountId: accountId, friendId: friendId)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
        return data
    }

    func removeBackground(accountId: Int64, friendId: Int64) throws {
        guard Self.hasValidIdentity(accountId: accountId, friendId: friendId) else {
            throw StoreError.invalidIdentity
        }

        let url = backgroundURL(accountId: accountId, friendId: friendId)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private static func hasValidIdentity(accountId: Int64, friendId: Int64) -> Bool {
        accountId > 0 && friendId > 0
    }

    private static func normalizedJPEGData(from sourceURL: URL) throws -> Data {
        guard
            let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw StoreError.invalidImage
        }

        let longestEdge = max(pixelWidth.intValue, pixelHeight.intValue)
        guard longestEdge > 0 else {
            throw StoreError.invalidImage
        }
        let thumbnailSize = min(longestEdge, 3_840)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw StoreError.invalidImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw StoreError.encodingFailed
        }
        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.88
        ]
        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw StoreError.encodingFailed
        }
        return output as Data
    }
}
