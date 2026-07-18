//
//  ChatAttachmentUploadService.swift
//  chat-storage
//

import AppKit
import Foundation

struct ChatPreparedImageFile {
    let taskId: UUID
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let mimeType: String
    let width: Int?
    let height: Int?
}

enum ChatAttachmentUploadError: LocalizedError {
    case invalidImage
    case unsupportedImageFormat
    case imageFileNotFound
    case uploadConnectionTimeout
    case missingFileId

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片编码失败"
        case .unsupportedImageFormat:
            return "暂不支持该图片格式"
        case .imageFileNotFound:
            return "图片文件不存在"
        case .uploadConnectionTimeout:
            return "图片上传连接超时"
        case .missingFileId:
            return "图片上传成功但服务端未返回文件ID"
        }
    }
}

final class ChatAttachmentUploadService {
    typealias UploadExecutor = (ChatPreparedImageFile, Int64, Int32, String, String) async throws -> Int64?
    private static let uploadPurpose = "CHAT_ATTACHMENT"

    private let uploadExecutor: UploadExecutor
    private let hostProvider: () -> String

    init(
        uploadExecutor: UploadExecutor? = nil,
        hostProvider: @escaping () -> String = { SocketManager.shared.getCurrentServer().0 }
    ) {
        self.hostProvider = hostProvider
        self.uploadExecutor = uploadExecutor ?? { prepared, targetDirId, userId, userName, uploadPurpose in
            try await Self.uploadPreparedImage(
                prepared,
                targetDirId: targetDirId,
                userId: userId,
                userName: userName,
                uploadPurpose: uploadPurpose,
                host: hostProvider()
            )
        }
    }

    func prepareImageFile(_ image: NSImage, taskId: UUID = UUID()) throws -> ChatPreparedImageFile {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ChatAttachmentUploadError.invalidImage
        }

        let directory = Self.tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "chat-image-\(taskId.uuidString).png"
        let fileURL = directory.appendingPathComponent(fileName)
        try pngData.write(to: fileURL, options: .atomic)

        return ChatPreparedImageFile(
            taskId: taskId,
            fileURL: fileURL,
            fileName: fileName,
            fileSize: Int64(pngData.count),
            mimeType: "image/png",
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded())
        )
    }

    func prepareImageFile(fileURL: URL, taskId: UUID = UUID()) throws -> ChatPreparedImageFile {
        guard ChatImageFormat.isSupported(fileName: fileURL.lastPathComponent) else {
            throw ChatAttachmentUploadError.unsupportedImageFormat
        }

        let isScoped = fileURL.startAccessingSecurityScopedResource()
        defer { if isScoped { fileURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ChatAttachmentUploadError.imageFileNotFound
        }

        let directory = Self.tempDirectory()
            .appendingPathComponent("original-\(taskId.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stableFileURL = directory.appendingPathComponent(fileURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: stableFileURL.path) {
            try FileManager.default.removeItem(at: stableFileURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: stableFileURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: stableFileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let image = NSImage(contentsOf: stableFileURL)

        return ChatPreparedImageFile(
            taskId: taskId,
            fileURL: stableFileURL,
            fileName: fileURL.lastPathComponent,
            fileSize: fileSize,
            mimeType: ChatImageFormat.mimeType(forFileName: fileURL.lastPathComponent),
            width: image.map { Int($0.size.width.rounded()) },
            height: image.map { Int($0.size.height.rounded()) }
        )
    }

    func uploadImage(
        _ image: NSImage,
        targetDirId: Int64 = 0,
        userId: Int32,
        userName: String
    ) async throws -> ChatImageAttachment {
        let prepared = try prepareImageFile(image)
        guard let fileId = try await uploadExecutor(
            prepared, targetDirId, userId, userName, Self.uploadPurpose
        ), fileId > 0 else {
            throw ChatAttachmentUploadError.missingFileId
        }

        return ChatImageAttachment(
            fileId: fileId,
            fileName: prepared.fileName,
            fileSize: prepared.fileSize,
            mimeType: prepared.mimeType,
            width: prepared.width,
            height: prepared.height
        )
    }

    func uploadPendingImage(
        _ pendingImage: PendingChatImage,
        targetDirId: Int64 = 0,
        userId: Int32,
        userName: String
    ) async throws -> ChatImageAttachment {
        let original: ChatPreparedImageFile
        if let sourceURL = pendingImage.sourceURL {
            original = try prepareImageFile(fileURL: sourceURL, taskId: pendingImage.id)
        } else {
            original = try prepareImageFile(pendingImage.previewImage, taskId: pendingImage.id)
        }
        guard let originalFileId = try await uploadExecutor(
            original, targetDirId, userId, userName, Self.uploadPurpose
        ), originalFileId > 0 else {
            throw ChatAttachmentUploadError.missingFileId
        }

        let thumbnail = try? prepareDerivedImageFile(
            pendingImage.previewImage,
            taskId: UUID(),
            fileNamePrefix: "chat-thumb",
            maxDimension: 480,
            compressionFactor: 0.82
        )
        let preview = try? prepareDerivedImageFile(
            pendingImage.previewImage,
            taskId: UUID(),
            fileNamePrefix: "chat-preview",
            maxDimension: 2048,
            compressionFactor: 0.9
        )

        let thumbnailUpload = await uploadDerivedImageIfPossible(thumbnail, userId: userId, userName: userName)
        let previewUpload = await uploadDerivedImageIfPossible(preview, userId: userId, userName: userName)

        return ChatImageAttachment(
            fileId: originalFileId,
            fileName: original.fileName,
            fileSize: original.fileSize,
            mimeType: original.mimeType,
            width: original.width,
            height: original.height,
            thumbnailFileId: thumbnailUpload.fileId,
            thumbnailFileSize: thumbnailUpload.fileSize,
            previewFileId: previewUpload.fileId,
            previewFileSize: previewUpload.fileSize
        )
    }

    func uploadImageFile(
        _ fileURL: URL,
        targetDirId: Int64 = 0,
        userId: Int32,
        userName: String
    ) async throws -> ChatImageAttachment {
        let prepared = try prepareImageFile(fileURL: fileURL)
        guard let fileId = try await uploadExecutor(
            prepared, targetDirId, userId, userName, Self.uploadPurpose
        ), fileId > 0 else {
            throw ChatAttachmentUploadError.missingFileId
        }

        return ChatImageAttachment(
            fileId: fileId,
            fileName: prepared.fileName,
            fileSize: prepared.fileSize,
            mimeType: prepared.mimeType,
            width: prepared.width,
            height: prepared.height
        )
    }

    private func prepareDerivedImageFile(
        _ image: NSImage,
        taskId: UUID,
        fileNamePrefix: String,
        maxDimension: CGFloat,
        compressionFactor: CGFloat
    ) throws -> ChatPreparedImageFile {
        let scaledImage = Self.scaled(image, maxDimension: maxDimension)
        guard let tiffData = scaledImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor]) else {
            throw ChatAttachmentUploadError.invalidImage
        }

        let directory = Self.tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "\(fileNamePrefix)-\(taskId.uuidString).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        try jpegData.write(to: fileURL, options: .atomic)

        return ChatPreparedImageFile(
            taskId: taskId,
            fileURL: fileURL,
            fileName: fileName,
            fileSize: Int64(jpegData.count),
            mimeType: "image/jpeg",
            width: Int(scaledImage.size.width.rounded()),
            height: Int(scaledImage.size.height.rounded())
        )
    }

    private func uploadDerivedImageIfPossible(
        _ prepared: ChatPreparedImageFile?,
        userId: Int32,
        userName: String
    ) async -> (fileId: Int64?, fileSize: Int64?) {
        guard let prepared else {
            return (nil, nil)
        }
        do {
            guard let fileId = try await uploadExecutor(prepared, 0, userId, userName, Self.uploadPurpose),
                  fileId > 0 else {
                return (nil, nil)
            }
            return (fileId, prepared.fileSize)
        } catch {
            print("⚠️ 聊天图片派生图上传失败，已回退原图: \(error.localizedDescription)")
            return (nil, nil)
        }
    }

    private static func scaled(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let srcWidth = max(1, image.size.width)
        let srcHeight = max(1, image.size.height)
        let scale = min(maxDimension / srcWidth, maxDimension / srcHeight, 1)
        let size = CGSize(width: srcWidth * scale, height: srcHeight * scale)
        let target = NSImage(size: size)
        target.lockFocus()
        image.draw(
            in: CGRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        target.unlockFocus()
        return target
    }

    private static func tempDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("chat-storage/chat-attachments", isDirectory: true)
    }

    private static func uploadPreparedImage(
        _ prepared: ChatPreparedImageFile,
        targetDirId: Int64,
        userId: Int32,
        userName: String,
        uploadPurpose: String,
        host: String
    ) async throws -> Int64? {
        let socketManager = SocketManager()
        var connected = false

        defer {
            if connected {
                Task { @MainActor in
                    socketManager.disconnect(notifyUI: false)
                }
            }
        }

        await MainActor.run {
            socketManager.disconnect(notifyUI: false)
            socketManager.connect(host: host, port: 10087)
        }

        var attempts = 0
        while socketManager.connectionState != .connected {
            if attempts > 50 {
                throw ChatAttachmentUploadError.uploadConnectionTimeout
            }
            if case .error = socketManager.connectionState {
                throw ChatAttachmentUploadError.uploadConnectionTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        connected = true
        let service = FileTransferService(socketManager: socketManager)
        let fileId = try await service.uploadFile(
            fileUrl: prepared.fileURL,
            targetDirId: targetDirId,
            userId: userId,
            userName: userName,
            taskId: prepared.taskId.uuidString,
            uploadPurpose: uploadPurpose,
            startOffset: 0,
            persistTransferTask: false,
            progressHandler: nil
        )

        if let fileId {
            await FileThumbnailService.shared.remapToFileId(taskId: prepared.taskId.uuidString, fileId: fileId)
        }
        return fileId
    }
}
