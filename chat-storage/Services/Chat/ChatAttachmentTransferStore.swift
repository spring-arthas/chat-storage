//
//  ChatAttachmentTransferStore.swift
//  chat-storage
//

import CoreData
import Combine
import Foundation

enum ChatAttachmentTransferState: String, Codable {
    case waiting
    case uploading
    case succeeded
    case failed
    case paused
    case removed
}

enum ChatAttachmentBatchState: String, Codable {
    case uploading
    case partialFailure
    case readyToSend
    case sendingMessage
    case sent
    case failedToSend
    case cancelled
}

enum ChatAttachmentDownloadState: String, Codable {
    case notDownloaded
    case downloading
    case paused
    case failed
    case completed
}

struct ChatAttachmentBatchSnapshot: Identifiable, Equatable {
    var id: String { clientMsgId }
    let clientMsgId: String
    let friendId: Int64
    var text: String
    var content: String
    var state: ChatAttachmentBatchState
    var errorMessage: String?
    var quoteMsgId: Int64?
    var quoteMsgContent: String?
    var quoteMsgSenderName: String?
    var avatar: String?
    let createdAt: Date
}

struct ChatAttachmentTransferSnapshot: Identifiable, Equatable {
    var id: String { recordId }
    let recordId: String
    let clientMsgId: String
    let friendId: Int64
    let attachmentId: UUID
    let localAttachmentId: Int64
    let orderIndex: Int
    let kind: String
    let fileName: String
    let fileSize: Int64
    let mimeType: String
    let localPath: String
    let taskId: String
    var state: ChatAttachmentTransferState
    var progress: Double
    var errorMessage: String?
    var result: ChatAttachment?
}

struct ChatAttachmentDownloadSnapshot: Identifiable, Equatable {
    var id: String { taskId }
    let taskId: String
    let fileId: Int64
    let fileName: String
    let fileSize: Int64
    let targetPath: String
    var state: ChatAttachmentDownloadState
    var progress: Double
    var errorMessage: String?
}

@MainActor
final class ChatAttachmentTransferStore: ObservableObject {
    static let shared = ChatAttachmentTransferStore()

    @Published private(set) var batches: [String: ChatAttachmentBatchSnapshot] = [:]
    @Published private(set) var transfers: [String: [Int64: ChatAttachmentTransferSnapshot]] = [:]
    @Published private(set) var downloads: [Int64: ChatAttachmentDownloadSnapshot] = [:]

    private let context: NSManagedObjectContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        restoreFromPersistentStore()
    }

    func createBatch(
        clientMsgId: String,
        friendId: Int64,
        text: String,
        content: String,
        quoteMsgId: Int64?,
        quoteMsgContent: String?,
        quoteMsgSenderName: String?,
        avatar: String?,
        attachments: [PendingChatAttachment]
    ) {
        let createdAt = Date()
        let snapshot = ChatAttachmentBatchSnapshot(
            clientMsgId: clientMsgId,
            friendId: friendId,
            text: text,
            content: content,
            state: .uploading,
            errorMessage: nil,
            quoteMsgId: quoteMsgId,
            quoteMsgContent: quoteMsgContent,
            quoteMsgSenderName: quoteMsgSenderName,
            avatar: avatar,
            createdAt: createdAt
        )
        batches[clientMsgId] = snapshot
        upsertBatch(snapshot)

        var batchTransfers: [Int64: ChatAttachmentTransferSnapshot] = [:]
        for (orderIndex, attachment) in attachments.enumerated() {
            guard let sourceURL = attachment.sourceURL else { continue }
            let localId = attachment.localAttachmentId
            let transfer = ChatAttachmentTransferSnapshot(
                recordId: Self.recordId(clientMsgId: clientMsgId, localAttachmentId: localId),
                clientMsgId: clientMsgId,
                friendId: friendId,
                attachmentId: attachment.id,
                localAttachmentId: localId,
                orderIndex: orderIndex,
                kind: attachment.kind,
                fileName: attachment.fileName,
                fileSize: attachment.fileSize ?? 0,
                mimeType: attachment.mimeType,
                localPath: sourceURL.path,
                taskId: attachment.id.uuidString,
                state: .waiting,
                progress: 0,
                errorMessage: nil,
                result: nil
            )
            batchTransfers[localId] = transfer
            upsertTransfer(transfer)
        }
        transfers[clientMsgId] = batchTransfers
    }

    func updateBatchContent(_ clientMsgId: String, content: String) {
        guard var batch = batches[clientMsgId] else { return }
        batch.content = content
        batches[clientMsgId] = batch
        upsertBatch(batch)
    }

    func updateBatchState(
        _ clientMsgId: String,
        state: ChatAttachmentBatchState,
        errorMessage: String? = nil
    ) {
        guard var batch = batches[clientMsgId] else { return }
        batch.state = state
        batch.errorMessage = errorMessage
        batches[clientMsgId] = batch
        upsertBatch(batch)
    }

    func updateTransfer(
        clientMsgId: String,
        localAttachmentId: Int64,
        state: ChatAttachmentTransferState,
        progress: Double? = nil,
        errorMessage: String? = nil,
        result: ChatAttachment? = nil
    ) {
        guard var transfer = transfers[clientMsgId]?[localAttachmentId] else { return }
        transfer.state = state
        if let progress {
            transfer.progress = min(1, max(0, progress))
        }
        transfer.errorMessage = errorMessage
        if let result {
            transfer.result = result
            transfer.progress = 1
        }
        transfers[clientMsgId]?[localAttachmentId] = transfer
        upsertTransfer(transfer)
    }

    func markRemoved(clientMsgId: String, localAttachmentId: Int64) {
        updateTransfer(
            clientMsgId: clientMsgId,
            localAttachmentId: localAttachmentId,
            state: .removed,
            errorMessage: nil
        )
    }

    func transfer(clientMsgId: String, localAttachmentId: Int64) -> ChatAttachmentTransferSnapshot? {
        transfers[clientMsgId]?[localAttachmentId]
    }

    func transfer(localAttachmentId: Int64) -> ChatAttachmentTransferSnapshot? {
        for batchTransfers in transfers.values {
            if let transfer = batchTransfers[localAttachmentId] {
                return transfer
            }
        }
        return nil
    }

    func transfer(clientMsgId: String?, attachment: ChatAttachment) -> ChatAttachmentTransferSnapshot? {
        guard let clientMsgId, let values = transfers[clientMsgId]?.values else { return nil }
        if attachment.isLocalPending {
            return transfers[clientMsgId]?[attachment.fileId]
        }
        return values.first { $0.result?.fileId == attachment.fileId }
    }

    func retainedTransfers(clientMsgId: String) -> [ChatAttachmentTransferSnapshot] {
        guard let values = transfers[clientMsgId]?.values else { return [] }
        return values
            .filter { $0.state != .removed }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    func allRetainedTransfersSucceeded(clientMsgId: String) -> Bool {
        let retained = retainedTransfers(clientMsgId: clientMsgId)
        return !retained.isEmpty && retained.allSatisfy { $0.state == .succeeded && $0.result != nil }
    }

    @discardableResult
    func markServerRejectedAttachment(
        clientMsgId: String,
        fileId: Int64,
        field: String?,
        message: String
    ) -> Bool {
        guard let batchTransfers = transfers[clientMsgId],
              let matched = batchTransfers.values.first(where: { transfer in
                  guard let result = transfer.result else { return false }
                  return result.fileId == fileId
                      || result.thumbnailFileId == fileId
                      || result.previewFileId == fileId
              }) else {
            return false
        }

        var failed = matched
        failed.state = .failed
        failed.progress = 0
        let fieldDescription = field.map { "[\($0)] " } ?? ""
        failed.errorMessage = fieldDescription + message
        transfers[clientMsgId]?[failed.localAttachmentId] = failed
        upsertTransfer(failed)
        return true
    }

    func pendingAttachment(clientMsgId: String, localAttachmentId: Int64) -> PendingChatAttachment? {
        guard let transfer = transfer(clientMsgId: clientMsgId, localAttachmentId: localAttachmentId) else {
            return nil
        }
        return PendingChatAttachment.restored(
            id: transfer.attachmentId,
            kind: transfer.kind,
            sourceURL: URL(fileURLWithPath: transfer.localPath),
            fileName: transfer.fileName,
            fileSize: transfer.fileSize,
            mimeType: transfer.mimeType
        )
    }

    func pendingAttachments(clientMsgId: String) -> [PendingChatAttachment] {
        retainedTransfers(clientMsgId: clientMsgId).compactMap { transfer in
            guard transfer.state != .succeeded else { return nil }
            return pendingAttachment(clientMsgId: clientMsgId, localAttachmentId: transfer.localAttachmentId)
        }
    }

    func unsentBatches(friendId: Int64) -> [ChatAttachmentBatchSnapshot] {
        batches.values
            .filter { $0.friendId == friendId && $0.state != .sent && $0.state != .cancelled }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func registerDownload(task: StorageTransferTask, attachment: ChatAttachment) {
        let snapshot = ChatAttachmentDownloadSnapshot(
            taskId: task.id.uuidString,
            fileId: attachment.fileId,
            fileName: attachment.fileName,
            fileSize: attachment.fileSize,
            targetPath: task.fileUrl.path,
            state: .downloading,
            progress: 0,
            errorMessage: nil
        )
        downloads[attachment.fileId] = snapshot
        upsertDownload(snapshot)
    }

    func updateDownload(taskId: String, status: String, progress: Double, errorMessage: String?) {
        guard let existing = downloads.values.first(where: { $0.taskId == taskId }) else { return }
        var snapshot = existing
        snapshot.progress = min(1, max(0, progress))
        snapshot.errorMessage = errorMessage
        let normalized = status.lowercased()
        if normalized.contains("完成") || normalized == "completed" {
            snapshot.state = .completed
            snapshot.progress = 1
        } else if normalized.contains("失败") || normalized.contains("错误") || normalized == "failed" {
            snapshot.state = .failed
        } else if normalized.contains("暂停") || normalized == "paused" {
            snapshot.state = .paused
        } else {
            snapshot.state = .downloading
        }
        downloads[snapshot.fileId] = snapshot
        upsertDownload(snapshot)
    }

    func download(for fileId: Int64) -> ChatAttachmentDownloadSnapshot? {
        downloads[fileId]
    }

    /// 返回仍可能被失败重传、继续发送流程使用的聊天附件本地原文件。
    /// 这些路径不能在清理缓存时删除。
    func protectedLocalAttachmentPaths() -> Set<String> {
        Set(
            transfers.values
                .flatMap { $0.values }
                .filter { $0.state != .succeeded && $0.state != .removed }
                .filter { !$0.localPath.isEmpty }
                .map { URL(fileURLWithPath: $0.localPath).standardizedFileURL.path }
        )
    }

    private func restoreFromPersistentStore() {
        context.performAndWait {
            restoreBatches()
            restoreTransfers()
            restoreDownloads()
            saveContext()
        }
    }

    private func restoreBatches() {
        for object in fetch(entityName: "ChatAttachmentBatchEntity") {
            guard let clientMsgId = object.value(forKey: "clientMsgId") as? String else { continue }
            let rawState = object.value(forKey: "status") as? String ?? ChatAttachmentBatchState.partialFailure.rawValue
            var state = ChatAttachmentBatchState(rawValue: rawState) ?? .partialFailure
            if state == .uploading {
                state = .partialFailure
                object.setValue(state.rawValue, forKey: "status")
            }
            batches[clientMsgId] = ChatAttachmentBatchSnapshot(
                clientMsgId: clientMsgId,
                friendId: Self.int64(object.value(forKey: "friendId")),
                text: object.value(forKey: "text") as? String ?? "",
                content: object.value(forKey: "content") as? String ?? "",
                state: state,
                errorMessage: object.value(forKey: "errorMessage") as? String,
                quoteMsgId: Self.optionalInt64(object.value(forKey: "quoteMsgId")),
                quoteMsgContent: object.value(forKey: "quoteMsgContent") as? String,
                quoteMsgSenderName: object.value(forKey: "quoteMsgSenderName") as? String,
                avatar: object.value(forKey: "avatar") as? String,
                createdAt: object.value(forKey: "createdAt") as? Date ?? Date()
            )
        }
    }

    private func restoreTransfers() {
        for object in fetch(entityName: "ChatAttachmentTransferEntity") {
            guard let recordId = object.value(forKey: "recordId") as? String,
                  let clientMsgId = object.value(forKey: "clientMsgId") as? String,
                  let attachmentIdString = object.value(forKey: "attachmentId") as? String,
                  let attachmentId = UUID(uuidString: attachmentIdString) else { continue }
            let localId = Self.int64(object.value(forKey: "localAttachmentId"))
            let rawState = object.value(forKey: "status") as? String ?? ChatAttachmentTransferState.paused.rawValue
            var state = ChatAttachmentTransferState(rawValue: rawState) ?? .paused
            if state == .uploading {
                state = .paused
                object.setValue(state.rawValue, forKey: "status")
            }
            let result: ChatAttachment?
            if let resultData = object.value(forKey: "resultJSON") as? Data {
                result = try? decoder.decode(ChatAttachment.self, from: resultData)
            } else {
                result = nil
            }
            let snapshot = ChatAttachmentTransferSnapshot(
                recordId: recordId,
                clientMsgId: clientMsgId,
                friendId: Self.int64(object.value(forKey: "friendId")),
                attachmentId: attachmentId,
                localAttachmentId: localId,
                orderIndex: Int(Self.int64(object.value(forKey: "orderIndex"))),
                kind: object.value(forKey: "kind") as? String ?? "file",
                fileName: object.value(forKey: "fileName") as? String ?? "附件",
                fileSize: Self.int64(object.value(forKey: "fileSize")),
                mimeType: object.value(forKey: "mimeType") as? String ?? "application/octet-stream",
                localPath: object.value(forKey: "localPath") as? String ?? "",
                taskId: object.value(forKey: "taskId") as? String ?? attachmentId.uuidString,
                state: state,
                progress: Self.double(object.value(forKey: "progress")),
                errorMessage: object.value(forKey: "errorMessage") as? String,
                result: result
            )
            transfers[clientMsgId, default: [:]][localId] = snapshot
        }
    }

    private func restoreDownloads() {
        for object in fetch(entityName: "ChatAttachmentDownloadEntity") {
            guard let taskId = object.value(forKey: "taskId") as? String else { continue }
            let fileId = Self.int64(object.value(forKey: "fileId"))
            var state = ChatAttachmentDownloadState(
                rawValue: object.value(forKey: "status") as? String ?? ""
            ) ?? .paused
            if state == .downloading {
                state = .paused
                object.setValue(state.rawValue, forKey: "status")
            }
            downloads[fileId] = ChatAttachmentDownloadSnapshot(
                taskId: taskId,
                fileId: fileId,
                fileName: object.value(forKey: "fileName") as? String ?? "附件",
                fileSize: Self.int64(object.value(forKey: "fileSize")),
                targetPath: object.value(forKey: "targetPath") as? String ?? "",
                state: state,
                progress: Self.double(object.value(forKey: "progress")),
                errorMessage: object.value(forKey: "errorMessage") as? String
            )
        }
    }

    private func upsertBatch(_ snapshot: ChatAttachmentBatchSnapshot) {
        context.performAndWait {
            let object = self.fetchOne(
                entityName: "ChatAttachmentBatchEntity",
                key: "clientMsgId",
                value: snapshot.clientMsgId
            ) ?? NSEntityDescription.insertNewObject(forEntityName: "ChatAttachmentBatchEntity", into: self.context)
            object.setValue(snapshot.clientMsgId, forKey: "clientMsgId")
            object.setValue(snapshot.friendId, forKey: "friendId")
            object.setValue(snapshot.text, forKey: "text")
            object.setValue(snapshot.content, forKey: "content")
            object.setValue(snapshot.state.rawValue, forKey: "status")
            object.setValue(snapshot.errorMessage, forKey: "errorMessage")
            object.setValue(snapshot.quoteMsgId, forKey: "quoteMsgId")
            object.setValue(snapshot.quoteMsgContent, forKey: "quoteMsgContent")
            object.setValue(snapshot.quoteMsgSenderName, forKey: "quoteMsgSenderName")
            object.setValue(snapshot.avatar, forKey: "avatar")
            object.setValue(snapshot.createdAt, forKey: "createdAt")
            self.saveContext()
        }
    }

    private func upsertTransfer(_ snapshot: ChatAttachmentTransferSnapshot) {
        context.performAndWait {
            let object = self.fetchOne(
                entityName: "ChatAttachmentTransferEntity",
                key: "recordId",
                value: snapshot.recordId
            ) ?? NSEntityDescription.insertNewObject(forEntityName: "ChatAttachmentTransferEntity", into: self.context)
            object.setValue(snapshot.recordId, forKey: "recordId")
            object.setValue(snapshot.clientMsgId, forKey: "clientMsgId")
            object.setValue(snapshot.friendId, forKey: "friendId")
            object.setValue(snapshot.attachmentId.uuidString, forKey: "attachmentId")
            object.setValue(snapshot.localAttachmentId, forKey: "localAttachmentId")
            object.setValue(Int32(snapshot.orderIndex), forKey: "orderIndex")
            object.setValue(snapshot.kind, forKey: "kind")
            object.setValue(snapshot.fileName, forKey: "fileName")
            object.setValue(snapshot.fileSize, forKey: "fileSize")
            object.setValue(snapshot.mimeType, forKey: "mimeType")
            object.setValue(snapshot.localPath, forKey: "localPath")
            object.setValue(snapshot.taskId, forKey: "taskId")
            object.setValue(snapshot.state.rawValue, forKey: "status")
            object.setValue(snapshot.progress, forKey: "progress")
            object.setValue(snapshot.errorMessage, forKey: "errorMessage")
            object.setValue(snapshot.result.flatMap { try? self.encoder.encode($0) }, forKey: "resultJSON")
            self.saveContext()
        }
    }

    private func upsertDownload(_ snapshot: ChatAttachmentDownloadSnapshot) {
        context.performAndWait {
            let object = self.fetchOne(
                entityName: "ChatAttachmentDownloadEntity",
                key: "taskId",
                value: snapshot.taskId
            ) ?? NSEntityDescription.insertNewObject(forEntityName: "ChatAttachmentDownloadEntity", into: self.context)
            object.setValue(snapshot.taskId, forKey: "taskId")
            object.setValue(snapshot.fileId, forKey: "fileId")
            object.setValue(snapshot.fileName, forKey: "fileName")
            object.setValue(snapshot.fileSize, forKey: "fileSize")
            object.setValue(snapshot.targetPath, forKey: "targetPath")
            object.setValue(snapshot.state.rawValue, forKey: "status")
            object.setValue(snapshot.progress, forKey: "progress")
            object.setValue(snapshot.errorMessage, forKey: "errorMessage")
            self.saveContext()
        }
    }

    private func fetch(entityName: String) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return (try? context.fetch(request)) ?? []
    }

    private func fetchOne(entityName: String, key: String, value: String) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "%K == %@", key, value)
        return try? context.fetch(request).first
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("❌ [ChatAttachmentTransferStore] 持久化失败: \(error.localizedDescription)")
        }
    }

    private static func recordId(clientMsgId: String, localAttachmentId: Int64) -> String {
        "\(clientMsgId):\(localAttachmentId)"
    }

    private static func optionalInt64(_ value: Any?) -> Int64? {
        let resolved = int64(value)
        return resolved == 0 ? nil : resolved
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? Int32 { return Int64(value) }
        return 0
    }

    private static func double(_ value: Any?) -> Double {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        return 0
    }
}
