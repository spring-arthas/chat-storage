//
//  ChatAttachmentUploadService.swift
//  chat-storage
//

import AppKit
import Foundation
import UniformTypeIdentifiers

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
    case sourceFileEmpty(String)
    case sourceFileSizeChanged(fileName: String, expected: Int64, actual: Int64)
    case uploadConnectionTimeout
    case missingFileId

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片编码失败"
        case .unsupportedImageFormat:
            return "暂不支持该图片格式"
        case .imageFileNotFound:
            return "附件本地副本不存在，请重新选择文件"
        case .sourceFileEmpty(let fileName):
            return "附件“\(fileName)”为空文件，请重新选择"
        case .sourceFileSizeChanged(let fileName, let expected, let actual):
            return "附件“\(fileName)”大小已变化（记录 \(expected) 字节，实际 \(actual) 字节），请重新选择"
        case .uploadConnectionTimeout:
            return "附件上传连接超时"
        case .missingFileId:
            return "附件上传成功但服务端未返回文件ID"
        }
    }
}

/// 一条聊天消息独占的上传会话。会话内所有物理文件顺序复用同一条 10087 连接。
final class ChatAttachmentUploadSession {
    let batchId: String

    private let host: String
    private let socketManager: SocketManager
    private lazy var transferService = FileTransferService(socketManager: socketManager)
    private var closed = false

    init(
        batchId: String,
        host: String = SocketManager.shared.getCurrentServer().0,
        socketManager: SocketManager = SocketManager()
    ) {
        self.batchId = batchId
        self.host = host
        self.socketManager = socketManager
    }

    func upload(
        _ prepared: ChatPreparedImageFile,
        targetDirId: Int64,
        userId: Int32,
        userName: String,
        progressHandler: ((Double, String) -> Void)? = nil,
        statusHandler: ((String) -> Void)? = nil
    ) async throws -> Int64? {
        statusHandler?("连接服务器")
        try await ensureConnected()
        return try await transferService.uploadFile(
            fileUrl: prepared.fileURL,
            targetDirId: targetDirId,
            userId: userId,
            userName: userName,
            taskId: prepared.taskId.uuidString,
            uploadPurpose: "CHAT_ATTACHMENT",
            connectionReuse: true,
            batchId: batchId,
            startOffset: 0,
            persistTransferTask: false,
            progressHandler: progressHandler,
            statusHandler: statusHandler
        )
    }

    func reconnect() async throws {
        await MainActor.run {
            socketManager.disconnect(notifyUI: false)
        }
        closed = false
        try await Task.sleep(nanoseconds: 50_000_000)
        try await connectAndWaitUntilWritable()
    }

    func close() async {
        guard !closed else { return }
        closed = true
        await MainActor.run {
            socketManager.disconnect(notifyUI: false)
        }
    }

    private func ensureConnected() async throws {
        if socketManager.isTransportReady {
            return
        }
        closed = false
        try await connectAndWaitUntilWritable()
    }

    private func connectAndWaitUntilWritable() async throws {
        await MainActor.run {
            socketManager.disconnect(notifyUI: false)
            socketManager.connect(host: host, port: 10087)
        }

        var attempts = 0
        while !socketManager.isTransportReady {
            if attempts > 50 {
                throw ChatAttachmentUploadError.uploadConnectionTimeout
            }
            if case .error = socketManager.connectionState {
                throw ChatAttachmentUploadError.uploadConnectionTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
    }
}

final class ChatAttachmentUploadService {
    typealias UploadExecutor = (ChatPreparedImageFile, Int64, Int32, String, String) async throws -> Int64?
    private static let uploadPurpose = "CHAT_ATTACHMENT"

    private let uploadExecutor: UploadExecutor
    private let session: ChatAttachmentUploadSession?
    private let hostProvider: () -> String

    init(
        session: ChatAttachmentUploadSession? = nil,
        uploadExecutor: UploadExecutor? = nil,
        hostProvider: @escaping () -> String = { SocketManager.shared.getCurrentServer().0 }
    ) {
        self.session = session
        self.hostProvider = hostProvider
        if let uploadExecutor {
            self.uploadExecutor = uploadExecutor
        } else if let session {
            self.uploadExecutor = { prepared, targetDirId, userId, userName, _ in
                try await session.upload(
                    prepared,
                    targetDirId: targetDirId,
                    userId: userId,
                    userName: userName
                )
            }
        } else {
            self.uploadExecutor = { prepared, targetDirId, userId, userName, uploadPurpose in
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

    func prepareImageFile(
        fileURL: URL,
        expectedFileSize: Int64? = nil,
        taskId: UUID = UUID()
    ) throws -> ChatPreparedImageFile {
        guard ChatImageFormat.isSupported(fileName: fileURL.lastPathComponent) else {
            throw ChatAttachmentUploadError.unsupportedImageFormat
        }

        let isScoped = fileURL.startAccessingSecurityScopedResource()
        defer { if isScoped { fileURL.stopAccessingSecurityScopedResource() } }

        let sourceFileSize = try Self.validatedFileSize(fileURL, expectedFileSize: expectedFileSize)

        let directory = Self.tempDirectory()
            .appendingPathComponent("original-\(taskId.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stableFileURL = directory.appendingPathComponent(fileURL.lastPathComponent)
        if fileURL.standardizedFileURL != stableFileURL.standardizedFileURL {
            if FileManager.default.fileExists(atPath: stableFileURL.path) {
                try FileManager.default.removeItem(at: stableFileURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: stableFileURL)
        }

        let fileSize = fileURL.standardizedFileURL == stableFileURL.standardizedFileURL
            ? sourceFileSize
            : try Self.validatedFileSize(stableFileURL, expectedFileSize: sourceFileSize)
        let image = NSImage(contentsOf: stableFileURL)
        guard image != nil else {
            throw ChatAttachmentUploadError.invalidImage
        }

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
        guard let fileId = try await uploadPrepared(
            prepared,
            targetDirId: targetDirId,
            userId: userId,
            userName: userName
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
        userName: String,
        progressHandler: ((Double, String) -> Void)? = nil,
        statusHandler: ((String) -> Void)? = nil
    ) async throws -> ChatImageAttachment {
        guard pendingImage.isImage else {
            throw ChatAttachmentUploadError.invalidImage
        }
        let original: ChatPreparedImageFile
        if let sourceURL = pendingImage.sourceURL {
            original = try prepareImageFile(
                fileURL: sourceURL,
                expectedFileSize: pendingImage.fileSize,
                taskId: pendingImage.id
            )
        } else {
            guard let previewImage = pendingImage.previewImage else {
                throw ChatAttachmentUploadError.imageFileNotFound
            }
            original = try prepareImageFile(previewImage, taskId: pendingImage.id)
        }
        guard let previewImage = pendingImage.previewImage ?? NSImage(contentsOf: original.fileURL) else {
            throw ChatAttachmentUploadError.invalidImage
        }
        guard let originalFileId = try await uploadPrepared(
            original,
            targetDirId: targetDirId,
            userId: userId,
            userName: userName,
            progressHandler: progressHandler,
            statusHandler: statusHandler
        ), originalFileId > 0 else {
            throw ChatAttachmentUploadError.missingFileId
        }

        let thumbnail = try? prepareDerivedImageFile(
            previewImage,
            taskId: UUID(),
            fileNamePrefix: "chat-thumb",
            maxDimension: 480,
            compressionFactor: 0.82
        )
        let preview: ChatPreparedImageFile?
        if Self.shouldGenerateDerivedPreview(for: previewImage) {
            preview = try? prepareDerivedImageFile(
                previewImage,
                taskId: UUID(),
                fileNamePrefix: "chat-preview",
                maxDimension: 2048,
                compressionFactor: 0.9
            )
        } else {
            preview = nil
        }

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

    func uploadPendingAttachment(
        _ pendingAttachment: PendingChatAttachment,
        targetDirId: Int64 = 0,
        userId: Int32,
        userName: String,
        progressHandler: ((Double, String) -> Void)? = nil,
        statusHandler: ((String) -> Void)? = nil
    ) async throws -> ChatAttachment {
        if pendingAttachment.isImage {
            return try await uploadPendingImage(
                pendingAttachment,
                targetDirId: targetDirId,
                userId: userId,
                userName: userName,
                progressHandler: progressHandler,
                statusHandler: statusHandler
            )
        }

        guard let sourceURL = pendingAttachment.sourceURL else {
            throw ChatAttachmentUploadError.imageFileNotFound
        }
        let prepared = try prepareAttachmentFile(
            fileURL: sourceURL,
            expectedFileSize: pendingAttachment.fileSize,
            mimeType: pendingAttachment.mimeType,
            taskId: pendingAttachment.id
        )
        guard let fileId = try await uploadPrepared(
            prepared,
            targetDirId: targetDirId,
            userId: userId,
            userName: userName,
            progressHandler: progressHandler,
            statusHandler: statusHandler
        ), fileId > 0 else {
            throw ChatAttachmentUploadError.missingFileId
        }
        return ChatAttachment(
            kind: "file",
            fileId: fileId,
            fileName: prepared.fileName,
            fileSize: prepared.fileSize,
            mimeType: prepared.mimeType
        )
    }

    func uploadImageFile(
        _ fileURL: URL,
        targetDirId: Int64 = 0,
        userId: Int32,
        userName: String
    ) async throws -> ChatImageAttachment {
        let prepared = try prepareImageFile(fileURL: fileURL)
        guard let fileId = try await uploadPrepared(
            prepared,
            targetDirId: targetDirId,
            userId: userId,
            userName: userName
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

    private func prepareAttachmentFile(
        fileURL: URL,
        expectedFileSize: Int64?,
        mimeType: String,
        taskId: UUID
    ) throws -> ChatPreparedImageFile {
        let isScoped = fileURL.startAccessingSecurityScopedResource()
        defer { if isScoped { fileURL.stopAccessingSecurityScopedResource() } }

        let sourceFileSize = try Self.validatedFileSize(fileURL, expectedFileSize: expectedFileSize)
        let directory = Self.tempDirectory()
            .appendingPathComponent("attachment-\(taskId.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stableFileURL = directory.appendingPathComponent(fileURL.lastPathComponent)
        if fileURL.standardizedFileURL != stableFileURL.standardizedFileURL {
            if FileManager.default.fileExists(atPath: stableFileURL.path) {
                try FileManager.default.removeItem(at: stableFileURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: stableFileURL)
        }
        let fileSize = fileURL.standardizedFileURL == stableFileURL.standardizedFileURL
            ? sourceFileSize
            : try Self.validatedFileSize(stableFileURL, expectedFileSize: sourceFileSize)
        let resolvedMimeType = mimeType.isEmpty
            ? UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            : mimeType
        return ChatPreparedImageFile(
            taskId: taskId,
            fileURL: stableFileURL,
            fileName: fileURL.lastPathComponent,
            fileSize: fileSize,
            mimeType: resolvedMimeType,
            width: nil,
            height: nil
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
            guard let fileId = try await uploadPrepared(
                prepared,
                targetDirId: 0,
                userId: userId,
                userName: userName
            ),
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

    private static func shouldGenerateDerivedPreview(for image: NSImage) -> Bool {
        let width = max(1, image.size.width)
        return image.size.height / width < 3
    }

    private func uploadPrepared(
        _ prepared: ChatPreparedImageFile,
        targetDirId: Int64,
        userId: Int32,
        userName: String,
        progressHandler: ((Double, String) -> Void)? = nil,
        statusHandler: ((String) -> Void)? = nil
    ) async throws -> Int64? {
        if let session {
            return try await session.upload(
                prepared,
                targetDirId: targetDirId,
                userId: userId,
                userName: userName,
                progressHandler: progressHandler,
                statusHandler: statusHandler
            )
        }
        return try await uploadExecutor(prepared, targetDirId, userId, userName, Self.uploadPurpose)
    }

    private static func tempDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("chat-storage/chat-attachments", isDirectory: true)
    }

    private static func validatedFileSize(_ fileURL: URL, expectedFileSize: Int64?) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ChatAttachmentUploadError.imageFileNotFound
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let actualFileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard actualFileSize > 0 else {
            throw ChatAttachmentUploadError.sourceFileEmpty(fileURL.lastPathComponent)
        }
        if let expectedFileSize, expectedFileSize > 0, expectedFileSize != actualFileSize {
            throw ChatAttachmentUploadError.sourceFileSizeChanged(
                fileName: fileURL.lastPathComponent,
                expected: expectedFileSize,
                actual: actualFileSize
            )
        }
        return actualFileSize
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
        while !socketManager.isTransportReady {
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
