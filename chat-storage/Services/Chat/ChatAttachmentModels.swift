//
//  ChatAttachmentModels.swift
//  chat-storage
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ChatAttachment: Codable, Equatable, Identifiable, Sendable {
    let kind: String
    let fileId: Int64
    let fileName: String
    let fileSize: Int64
    let mimeType: String
    let width: Int?
    let height: Int?
    let thumbnailFileId: Int64?
    let thumbnailFileSize: Int64?
    let previewFileId: Int64?
    let previewFileSize: Int64?

    var id: Int64 { fileId }
    var isLocalPending: Bool { fileId < 0 }
    var isImage: Bool { kind.caseInsensitiveCompare("image") == .orderedSame }
    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else {
            return nil
        }
        return CGFloat(width) / CGFloat(height)
    }

    var isVeryTallImage: Bool {
        guard let aspectRatio else {
            return false
        }
        return aspectRatio <= 1.0 / 3.0
    }

    init(
        kind: String = "image",
        fileId: Int64,
        fileName: String,
        fileSize: Int64,
        mimeType: String,
        width: Int? = nil,
        height: Int? = nil,
        thumbnailFileId: Int64? = nil,
        thumbnailFileSize: Int64? = nil,
        previewFileId: Int64? = nil,
        previewFileSize: Int64? = nil
    ) {
        self.kind = kind
        self.fileId = fileId
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.thumbnailFileId = thumbnailFileId
        self.thumbnailFileSize = thumbnailFileSize
        self.previewFileId = previewFileId
        self.previewFileSize = previewFileSize
    }

    func contentString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: [], debugDescription: "图片附件 JSON 无法转为 UTF-8 字符串"))
        }
        return string
    }

    static func parse(_ content: String) -> ChatAttachment? {
        guard let data = content.data(using: .utf8) else {
            return nil
        }
        guard let attachment = try? JSONDecoder().decode(ChatAttachment.self, from: data) else {
            return nil
        }
        return attachment.isImage && attachment.fileId > 0 ? attachment : nil
    }

    func directoryItem() -> DirectoryItem {
        directoryItem(fileId: fileId, fileSize: fileSize, fileName: fileName)
    }

    func thumbnailDirectoryItem() -> DirectoryItem {
        directoryItem(
            fileId: thumbnailFileId ?? fileId,
            fileSize: thumbnailFileSize ?? fileSize,
            fileName: thumbnailFileId == nil ? fileName : "thumb-\(fileName)"
        )
    }

    func bubbleThumbnailDirectoryItem() -> DirectoryItem? {
        if let thumbnailFileId, thumbnailFileId > 0 {
            return directoryItem(
                fileId: thumbnailFileId,
                fileSize: thumbnailFileSize ?? 0,
                fileName: "thumb-\(fileName)"
            )
        }
        if let previewFileId, previewFileId > 0 {
            return directoryItem(
                fileId: previewFileId,
                fileSize: previewFileSize ?? 0,
                fileName: "preview-\(fileName)"
            )
        }
        return nil
    }

    func previewDirectoryItem() -> DirectoryItem {
        directoryItem(
            fileId: previewFileId ?? fileId,
            fileSize: previewFileSize ?? fileSize,
            fileName: previewFileId == nil ? fileName : "preview-\(fileName)"
        )
    }

    func previewCandidateDirectoryItems() -> [DirectoryItem] {
        let preferred = previewDirectoryItem()
        let original = directoryItem()
        guard preferred.id != original.id else {
            return [original]
        }
        return [original, preferred]
    }

    func bubblePreviewSize(
        maxWidth: CGFloat = 320,
        maxHeight: CGFloat = 360,
        minWidth: CGFloat = 160,
        minHeight: CGFloat = 120
    ) -> CGSize {
        guard let aspectRatio else {
            return CGSize(width: min(maxWidth, 220), height: min(maxHeight, 172))
        }

        if isVeryTallImage {
            return CGSize(width: maxWidth, height: maxHeight)
        }

        var targetWidth = maxWidth
        var targetHeight = targetWidth / aspectRatio
        if targetHeight > maxHeight {
            targetHeight = maxHeight
            targetWidth = targetHeight * aspectRatio
        }
        if targetWidth < minWidth {
            targetWidth = minWidth
            targetHeight = targetWidth / aspectRatio
        }
        if targetHeight < minHeight {
            targetHeight = minHeight
            targetWidth = targetHeight * aspectRatio
        }

        return CGSize(
            width: min(maxWidth, max(minWidth, targetWidth)).rounded(),
            height: min(maxHeight, max(minHeight, targetHeight)).rounded()
        )
    }

    private func directoryItem(fileId: Int64, fileSize: Int64, fileName: String) -> DirectoryItem {
        DirectoryItem(
            id: fileId,
            pId: 0,
            fileName: fileName,
            childFileList: nil,
            hasChild: false,
            fileSize: fileSize,
            isFile: true,
            uploadTime: nil,
            directoryName: isImage ? "聊天图片" : "聊天附件"
        )
    }
}

typealias ChatImageAttachment = ChatAttachment

struct PendingChatAttachment: Identifiable {
    let id: UUID
    let kind: String
    let previewImage: NSImage?
    let sourceURL: URL?
    let fileName: String
    let fileSize: Int64?
    let mimeType: String

    var isImage: Bool { kind == "image" }

    var localAttachmentId: Int64 {
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "")
        if let value = Int64(String(hex.prefix(15)), radix: 16) {
            return -max(1, value)
        }
        let fallback = abs(id.uuidString.hashValue % 1_000_000_000) + 1
        return -Int64(fallback)
    }

    func localAttachment() -> ChatAttachment {
        ChatAttachment(
            kind: kind,
            fileId: localAttachmentId,
            fileName: fileName,
            fileSize: fileSize ?? 0,
            mimeType: mimeType,
            width: previewImage.map { Int($0.size.width.rounded()) },
            height: previewImage.map { Int($0.size.height.rounded()) }
        )
    }

    static func pasted(_ image: NSImage, id: UUID = UUID()) -> PendingChatAttachment {
        let fileName = "chat-image-\(id.uuidString).png"
        let stableURL: URL?
        let stableFileSize: Int64?
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let target = stableDirectory(for: id).appendingPathComponent(fileName)
            do {
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try pngData.write(to: target, options: .atomic)
                stableURL = target
                stableFileSize = Int64(pngData.count)
            } catch {
                stableURL = nil
                stableFileSize = nil
            }
        } else {
            stableURL = nil
            stableFileSize = nil
        }
        return PendingChatAttachment(
            id: id,
            kind: "image",
            previewImage: image,
            sourceURL: stableURL,
            fileName: fileName,
            fileSize: stableFileSize,
            mimeType: "image/png"
        )
    }

    static func file(url: URL, id: UUID = UUID()) throws -> PendingChatAttachment {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ChatAttachmentUploadError.imageFileNotFound
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        guard let fileSize, fileSize > 0 else {
            throw ChatAttachmentUploadError.sourceFileEmpty(url.lastPathComponent)
        }
        let isImage = ChatImageFormat.isSupported(fileName: url.lastPathComponent)
        let image = isImage ? NSImage(contentsOf: url) : nil
        if isImage && image == nil {
            throw ChatAttachmentUploadError.invalidImage
        }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? (isImage ? ChatImageFormat.mimeType(forFileName: url.lastPathComponent) : "application/octet-stream")

        let stableDirectory = stableDirectory(for: id)
        try FileManager.default.createDirectory(at: stableDirectory, withIntermediateDirectories: true)
        let stableURL = stableDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: stableURL.path) {
            try FileManager.default.removeItem(at: stableURL)
        }
        try FileManager.default.copyItem(at: url, to: stableURL)

        return PendingChatAttachment(
            id: id,
            kind: isImage ? "image" : "file",
            previewImage: image,
            sourceURL: stableURL,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            mimeType: mimeType
        )
    }

    static func restored(
        id: UUID,
        kind: String,
        sourceURL: URL,
        fileName: String,
        fileSize: Int64,
        mimeType: String
    ) -> PendingChatAttachment? {
        let preview = kind == "image" ? NSImage(contentsOf: sourceURL) : nil
        return PendingChatAttachment(
            id: id,
            kind: kind,
            previewImage: preview,
            sourceURL: sourceURL,
            fileName: fileName,
            fileSize: fileSize,
            mimeType: mimeType
        )
    }

    private static func stableDirectory(for id: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("chat-storage/chat-attachments", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }
}

typealias PendingChatImage = PendingChatAttachment

@MainActor
final class ChatPendingImageStore {
    static let shared = ChatPendingImageStore()

    private var images: [Int64: NSImage] = [:]

    private init() {}

    func store(_ pendingAttachments: [PendingChatAttachment]) {
        for attachment in pendingAttachments where attachment.isImage {
            if let previewImage = attachment.previewImage {
                images[attachment.localAttachmentId] = previewImage
            }
        }
    }

    func image(for localAttachmentId: Int64) -> NSImage? {
        images[localAttachmentId]
    }

    func remove(localAttachmentIds: [Int64]) {
        for id in localAttachmentIds {
            images.removeValue(forKey: id)
        }
    }
}

enum ChatMixedMessageError: LocalizedError, Equatable {
    case emptyContent
    case tooManyImages
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "消息内容不能为空"
        case .tooManyImages:
            return "单条消息最多发送9个附件"
        case .invalidJSON:
            return "图文消息编码失败"
        }
    }
}

struct ChatMixedMessageContent: Codable, Equatable, Sendable {
    static let maxAttachmentCount = 9
    static let maxImageCount = maxAttachmentCount

    let kind: String
    let version: Int
    let text: String
    let attachments: [ChatAttachment]

    init(
        kind: String = "mixed",
        version: Int = 2,
        text: String,
        attachments: [ChatAttachment]
    ) throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else {
            throw ChatMixedMessageError.emptyContent
        }
        guard attachments.count <= Self.maxAttachmentCount else {
            throw ChatMixedMessageError.tooManyImages
        }
        self.kind = kind
        self.version = version
        self.text = text
        self.attachments = attachments
    }

    func contentString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ChatMixedMessageError.invalidJSON
        }
        return string
    }

    static func parse(_ content: String) -> ChatMixedMessageContent? {
        guard let data = content.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ChatMixedMessageContent.self, from: data),
              payload.kind == "mixed",
              payload.version >= 1,
              !payload.attachments.isEmpty,
              payload.attachments.count <= Self.maxAttachmentCount,
              payload.attachments.allSatisfy({ ($0.isImage || $0.kind == "file") && $0.fileId != 0 }) else {
            return nil
        }
        return payload
    }
}

enum ChatMessagePayload: Equatable, Sendable {
    case text(String)
    case image(ChatImageAttachment)
    case mixed(ChatMixedMessageContent)

    static func parse(content: String, msgType: String) -> ChatMessagePayload {
        let normalizedType = msgType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let canParseMixed = normalizedType.isEmpty || normalizedType == "MIXED"
        let canParseImage = normalizedType.isEmpty || normalizedType == "IMAGE"

        if canParseMixed, let mixed = ChatMixedMessageContent.parse(content) {
            return .mixed(mixed)
        }
        if canParseImage, let image = ChatImageAttachment.parse(content) {
            return .image(image)
        }
        return .text(content)
    }

    var text: String {
        switch self {
        case .text(let value):
            return value
        case .image:
            return ""
        case .mixed(let payload):
            return payload.text
        }
    }

    var images: [ChatImageAttachment] {
        switch self {
        case .text:
            return []
        case .image(let attachment):
            return [attachment]
        case .mixed(let payload):
            return payload.attachments.filter(\.isImage)
        }
    }

    var files: [ChatAttachment] {
        switch self {
        case .text, .image:
            return []
        case .mixed(let payload):
            return payload.attachments.filter { !$0.isImage }
        }
    }

    var attachments: [ChatAttachment] {
        switch self {
        case .text:
            return []
        case .image(let attachment):
            return [attachment]
        case .mixed(let payload):
            return payload.attachments
        }
    }

    var displayText: String {
        switch self {
        case .text(let value):
            return value
        case .image:
            return "[图片]"
        case .mixed(let payload):
            let imageCount = payload.attachments.filter(\.isImage).count
            let fileCount = payload.attachments.count - imageCount
            let attachmentText: String
            if imageCount > 0 && fileCount > 0 {
                attachmentText = "[\(imageCount)张图片，\(fileCount)个文件]"
            } else if imageCount > 0 {
                attachmentText = imageCount == 1 ? "[图片]" : "[\(imageCount)张图片]"
            } else {
                attachmentText = fileCount == 1 ? "[文件]" : "[\(fileCount)个文件]"
            }
            let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? attachmentText : "\(attachmentText) \(trimmed)"
        }
    }
}

enum ChatImageFormat {
    private static let mimeTypesByExtension: [String: String] = [
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "heic": "image/heic",
        "heif": "image/heif",
        "webp": "image/webp",
        "gif": "image/gif",
        "bmp": "image/bmp",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "avif": "image/avif",
        "jfif": "image/jpeg",
        "jp2": "image/jp2"
    ]

    static func isSupported(fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return mimeTypesByExtension[ext] != nil
    }

    static func mimeType(forFileName fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return mimeTypesByExtension[ext] ?? "application/octet-stream"
    }
}
