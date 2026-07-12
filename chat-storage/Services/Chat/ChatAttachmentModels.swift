//
//  ChatAttachmentModels.swift
//  chat-storage
//

import AppKit
import Foundation

struct ChatImageAttachment: Codable, Equatable, Identifiable {
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

    static func parse(_ content: String) -> ChatImageAttachment? {
        guard let data = content.data(using: .utf8) else {
            return nil
        }
        guard let attachment = try? JSONDecoder().decode(ChatImageAttachment.self, from: data) else {
            return nil
        }
        return attachment.kind == "image" && attachment.fileId > 0 ? attachment : nil
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

    func previewDirectoryItem() -> DirectoryItem {
        directoryItem(
            fileId: previewFileId ?? fileId,
            fileSize: previewFileSize ?? fileSize,
            fileName: previewFileId == nil ? fileName : "preview-\(fileName)"
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
            directoryName: "聊天图片"
        )
    }
}

struct PendingChatImage: Identifiable {
    let id: UUID
    let previewImage: NSImage
    let sourceURL: URL?
    let fileName: String
    let fileSize: Int64?
    let mimeType: String

    var localAttachmentId: Int64 {
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "")
        if let value = Int64(String(hex.prefix(15)), radix: 16) {
            return -max(1, value)
        }
        let fallback = abs(id.uuidString.hashValue % 1_000_000_000) + 1
        return -Int64(fallback)
    }

    func localAttachment() -> ChatImageAttachment {
        ChatImageAttachment(
            fileId: localAttachmentId,
            fileName: fileName,
            fileSize: fileSize ?? 0,
            mimeType: mimeType,
            width: Int(previewImage.size.width.rounded()),
            height: Int(previewImage.size.height.rounded())
        )
    }

    static func pasted(_ image: NSImage, id: UUID = UUID()) -> PendingChatImage {
        PendingChatImage(
            id: id,
            previewImage: image,
            sourceURL: nil,
            fileName: "chat-image-\(id.uuidString).png",
            fileSize: nil,
            mimeType: "image/png"
        )
    }

    static func file(url: URL, id: UUID = UUID()) throws -> PendingChatImage {
        guard ChatImageFormat.isSupported(fileName: url.lastPathComponent) else {
            throw ChatAttachmentUploadError.unsupportedImageFormat
        }

        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ChatAttachmentUploadError.imageFileNotFound
        }
        guard let image = NSImage(contentsOf: url) else {
            throw ChatAttachmentUploadError.invalidImage
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value

        return PendingChatImage(
            id: id,
            previewImage: image,
            sourceURL: url,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            mimeType: ChatImageFormat.mimeType(forFileName: url.lastPathComponent)
        )
    }
}

@MainActor
final class ChatPendingImageStore {
    static let shared = ChatPendingImageStore()

    private var images: [Int64: NSImage] = [:]

    private init() {}

    func store(_ pendingImages: [PendingChatImage]) {
        for pendingImage in pendingImages {
            images[pendingImage.localAttachmentId] = pendingImage.previewImage
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
            return "单条消息最多发送9张图片"
        case .invalidJSON:
            return "图文消息编码失败"
        }
    }
}

struct ChatMixedMessageContent: Codable, Equatable {
    static let maxImageCount = 9

    let kind: String
    let version: Int
    let text: String
    let attachments: [ChatImageAttachment]

    init(
        kind: String = "mixed",
        version: Int = 1,
        text: String,
        attachments: [ChatImageAttachment]
    ) throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else {
            throw ChatMixedMessageError.emptyContent
        }
        guard attachments.count <= Self.maxImageCount else {
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
              payload.attachments.count <= Self.maxImageCount else {
            return nil
        }
        return payload
    }
}

enum ChatMessagePayload: Equatable {
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
            let imageText = payload.attachments.count == 1 ? "[图片]" : "[\(payload.attachments.count)张图片]"
            let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? imageText : "\(imageText) \(trimmed)"
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
        "tiff": "image/tiff"
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
