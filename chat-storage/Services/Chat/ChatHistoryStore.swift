import CoreData
import Foundation

struct ChatHistoryBounds: Equatable {
    let oldestMessageId: Int64?
    let latestMessageId: Int64?
}

struct ChatHistoryLocalPage {
    let messages: [ChatMessage]
    let hasMore: Bool
}

final class ChatHistoryStore {
    static let shared = ChatHistoryStore(container: PersistenceController.shared.container)

    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer) {
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func fetchLatest(accountId: Int64, friendId: Int64, limit: Int) async throws -> [ChatMessage] {
        let context = self.context
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ChatMessageEntity")
            request.predicate = Self.conversationPredicate(accountId: accountId, friendId: friendId)
            request.sortDescriptors = [NSSortDescriptor(key: "messageId", ascending: false)]
            request.fetchLimit = max(1, limit)
            return try context.fetch(request).reversed().compactMap(Self.makeMessage)
        }
    }

    func fetchOlder(
        accountId: Int64,
        friendId: Int64,
        beforeMessageId: Int64,
        limit: Int
    ) async throws -> ChatHistoryLocalPage {
        let context = self.context
        let pageLimit = max(1, limit)
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ChatMessageEntity")
            request.predicate = NSPredicate(
                format: "accountId == %lld AND friendId == %lld AND messageDeleted == NO AND messageId < %lld",
                accountId,
                friendId,
                beforeMessageId
            )
            request.sortDescriptors = [NSSortDescriptor(key: "messageId", ascending: false)]
            request.fetchLimit = pageLimit + 1

            let rows = try context.fetch(request).compactMap(Self.makeMessage)
            let hasMore = rows.count > pageLimit
            return ChatHistoryLocalPage(
                messages: Array(rows.prefix(pageLimit).reversed()),
                hasMore: hasMore
            )
        }
    }

    func fetchNewer(
        accountId: Int64,
        friendId: Int64,
        afterMessageId: Int64,
        limit: Int
    ) async throws -> ChatHistoryLocalPage {
        let context = self.context
        let pageLimit = max(1, limit)
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ChatMessageEntity")
            request.predicate = NSPredicate(
                format: "accountId == %lld AND friendId == %lld AND messageDeleted == NO AND messageId > %lld",
                accountId,
                friendId,
                afterMessageId
            )
            request.sortDescriptors = [NSSortDescriptor(key: "messageId", ascending: true)]
            request.fetchLimit = pageLimit + 1

            let rows = try context.fetch(request).compactMap(Self.makeMessage)
            return ChatHistoryLocalPage(
                messages: Array(rows.prefix(pageLimit)),
                hasMore: rows.count > pageLimit
            )
        }
    }

    func upsert(accountId: Int64, friendId: Int64, items: [ChatHistoryItemDto]) async throws {
        let records = items.compactMap { item -> StoredChatMessage? in
            guard item.id > 0 else { return nil }
            return StoredChatMessage(
                messageId: item.id,
                clientMsgId: item.clientMsgId,
                senderId: item.senderId,
                receiverId: item.receiverId,
                content: item.content,
                msgType: item.msgType.isEmpty ? "TEXT" : item.msgType,
                status: item.retracted ? 4 : 2,
                quoteMsgId: item.quoteMsgId,
                quoteMsgContent: item.quoteMsgContent,
                quoteMsgSenderName: item.quoteMsgSenderName,
                gmtCreated: item.gmtCreated ?? 0,
                groupTime: item.groupTime,
                msgTimeStr: item.msgTimeStr,
                retracted: item.retracted,
                deleted: item.deleted
            )
        }
        try await upsert(accountId: accountId, friendId: friendId, records: records)
    }

    func upsert(accountId: Int64, friendId: Int64, messages: [ChatMessage]) async throws {
        let records = messages.compactMap { message -> StoredChatMessage? in
            guard let messageId = message.messageId, messageId > 0 else { return nil }
            return StoredChatMessage(
                messageId: messageId,
                clientMsgId: message.clientMsgId,
                senderId: message.isMe ? Int32(accountId) : Int32(friendId),
                receiverId: message.isMe ? Int32(friendId) : Int32(accountId),
                content: message.content,
                msgType: message.type,
                status: Self.persistedStatus(message.sendStatus),
                quoteMsgId: message.quoteMsgId,
                quoteMsgContent: message.quoteMsgContent,
                quoteMsgSenderName: message.quoteMsgSenderName,
                gmtCreated: Int64(message.timestamp.timeIntervalSince1970 * 1_000),
                groupTime: message.groupTime,
                msgTimeStr: message.msgTimeStr,
                retracted: message.retracted,
                deleted: false
            )
        }
        try await upsert(accountId: accountId, friendId: friendId, records: records)
    }

    func deleteConversation(accountId: Int64, friendId: Int64) async throws {
        let context = self.context
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ChatMessageEntity")
            request.predicate = Self.allConversationRowsPredicate(accountId: accountId, friendId: friendId)
            for object in try context.fetch(request) {
                context.delete(object)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func bounds(accountId: Int64, friendId: Int64) async throws -> ChatHistoryBounds {
        let context = self.context
        return try await context.perform {
            let request = NSFetchRequest<NSDictionary>(entityName: "ChatMessageEntity")
            request.resultType = .dictionaryResultType
            request.predicate = Self.conversationPredicate(accountId: accountId, friendId: friendId)

            let minimum = NSExpressionDescription()
            minimum.name = "oldest"
            minimum.expression = NSExpression(forFunction: "min:", arguments: [NSExpression(forKeyPath: "messageId")])
            minimum.expressionResultType = .integer64AttributeType

            let maximum = NSExpressionDescription()
            maximum.name = "latest"
            maximum.expression = NSExpression(forFunction: "max:", arguments: [NSExpression(forKeyPath: "messageId")])
            maximum.expressionResultType = .integer64AttributeType

            request.propertiesToFetch = [minimum, maximum]
            let result = try context.fetch(request).first
            return ChatHistoryBounds(
                oldestMessageId: (result?["oldest"] as? NSNumber)?.int64Value,
                latestMessageId: (result?["latest"] as? NSNumber)?.int64Value
            )
        }
    }

    private func upsert(accountId: Int64, friendId: Int64, records: [StoredChatMessage]) async throws {
        guard !records.isEmpty else { return }
        let context = self.context
        try await context.perform {
            let keys = records.map { Self.recordKey(accountId: accountId, friendId: friendId, messageId: $0.messageId) }
            let request = NSFetchRequest<NSManagedObject>(entityName: "ChatMessageEntity")
            request.predicate = NSPredicate(format: "recordKey IN %@", keys)
            let existing = try context.fetch(request)
            var objectsByKey = Dictionary(uniqueKeysWithValues: existing.compactMap { object in
                (object.value(forKey: "recordKey") as? String).map { ($0, object) }
            })

            for record in records {
                let key = Self.recordKey(accountId: accountId, friendId: friendId, messageId: record.messageId)
                let object = objectsByKey[key]
                    ?? NSEntityDescription.insertNewObject(forEntityName: "ChatMessageEntity", into: context)
                objectsByKey[key] = object
                Self.apply(record, accountId: accountId, friendId: friendId, recordKey: key, to: object)
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    private static func conversationPredicate(accountId: Int64, friendId: Int64) -> NSPredicate {
        NSPredicate(
            format: "accountId == %lld AND friendId == %lld AND messageDeleted == NO",
            accountId,
            friendId
        )
    }

    private static func allConversationRowsPredicate(accountId: Int64, friendId: Int64) -> NSPredicate {
        NSPredicate(format: "accountId == %lld AND friendId == %lld", accountId, friendId)
    }

    private static func recordKey(accountId: Int64, friendId: Int64, messageId: Int64) -> String {
        "\(accountId):\(friendId):\(messageId)"
    }

    private static func apply(
        _ record: StoredChatMessage,
        accountId: Int64,
        friendId: Int64,
        recordKey: String,
        to object: NSManagedObject
    ) {
        object.setValue(recordKey, forKey: "recordKey")
        object.setValue(accountId, forKey: "accountId")
        object.setValue(friendId, forKey: "friendId")
        object.setValue(record.messageId, forKey: "messageId")
        object.setValue(record.clientMsgId, forKey: "clientMsgId")
        object.setValue(record.senderId, forKey: "senderId")
        object.setValue(record.receiverId, forKey: "receiverId")
        object.setValue(record.content, forKey: "content")
        object.setValue(record.msgType, forKey: "msgType")
        object.setValue(record.status, forKey: "status")
        object.setValue(record.quoteMsgId, forKey: "quoteMsgId")
        object.setValue(record.quoteMsgContent, forKey: "quoteMsgContent")
        object.setValue(record.quoteMsgSenderName, forKey: "quoteMsgSenderName")
        object.setValue(record.gmtCreated, forKey: "gmtCreated")
        object.setValue(record.groupTime, forKey: "groupTime")
        object.setValue(record.msgTimeStr, forKey: "msgTimeStr")
        object.setValue(record.retracted, forKey: "retracted")
        object.setValue(record.deleted, forKey: "messageDeleted")
    }

    private static func makeMessage(_ object: NSManagedObject) -> ChatMessage? {
        guard let messageId = (object.value(forKey: "messageId") as? NSNumber)?.int64Value else {
            return nil
        }
        let accountId = (object.value(forKey: "accountId") as? NSNumber)?.int64Value ?? 0
        let senderId = (object.value(forKey: "senderId") as? NSNumber)?.int64Value ?? 0
        let milliseconds = (object.value(forKey: "gmtCreated") as? NSNumber)?.int64Value ?? 0
        let persistedStatus = (object.value(forKey: "status") as? NSNumber)?.intValue ?? 2
        let retracted = (object.value(forKey: "retracted") as? NSNumber)?.boolValue ?? false
        return ChatMessage(
            messageId: messageId,
            clientMsgId: object.value(forKey: "clientMsgId") as? String,
            content: object.value(forKey: "content") as? String ?? "",
            isMe: senderId == accountId,
            timestamp: milliseconds > 0
                ? Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
                : Date.distantPast,
            type: object.value(forKey: "msgType") as? String ?? "TEXT",
            sendStatus: retracted ? .retracted : messageStatus(persistedStatus),
            quoteMsgId: (object.value(forKey: "quoteMsgId") as? NSNumber)?.int64Value,
            quoteMsgContent: object.value(forKey: "quoteMsgContent") as? String,
            quoteMsgSenderName: object.value(forKey: "quoteMsgSenderName") as? String,
            retracted: retracted,
            groupTime: object.value(forKey: "groupTime") as? String,
            msgTimeStr: object.value(forKey: "msgTimeStr") as? String,
            avatar: nil
        )
    }

    private static func persistedStatus(_ status: ChatMessage.SendStatus) -> Int32 {
        switch status {
        case .uploadingMedia: return 0
        case .sending: return 1
        case .success: return 2
        case .failed: return 3
        case .retracted: return 4
        }
    }

    private static func messageStatus(_ status: Int) -> ChatMessage.SendStatus {
        switch status {
        case 0: return .uploadingMedia
        case 1: return .sending
        case 3: return .failed
        case 4: return .retracted
        default: return .success
        }
    }
}

private struct StoredChatMessage {
    let messageId: Int64
    let clientMsgId: String?
    let senderId: Int32
    let receiverId: Int32
    let content: String
    let msgType: String
    let status: Int32
    let quoteMsgId: Int64?
    let quoteMsgContent: String?
    let quoteMsgSenderName: String?
    let gmtCreated: Int64
    let groupTime: String?
    let msgTimeStr: String?
    let retracted: Bool
    let deleted: Bool
}
