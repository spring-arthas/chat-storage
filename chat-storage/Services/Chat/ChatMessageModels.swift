//
//  ChatMessageModels.swift
//  chat-storage
//

import Foundation

enum ChatMessageTimeGrouping {
    static func groupTime(for date: Date, now: Date = Date()) -> String? {
        guard date != .distantPast else { return nil }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")

        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            formatter.dateFormat = "HH:mm"
            return "昨天 " + formatter.string(from: date)
        }

        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func messageTime(for date: Date) -> String? {
        guard date != .distantPast else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    var id: String {
        if let mid = messageId {
            return "msg-\(mid)"
        }
        return localId.uuidString
    }

    let localId = UUID()
    var messageId: Int64?
    var clientMsgId: String? = nil
    private(set) var content: String
    let isMe: Bool
    let timestamp: Date
    private(set) var type: String
    var sendStatus: SendStatus
    var errorMessage: String? = nil
    var quoteMsgId: Int64? = nil
    var quoteMsgContent: String? = nil
    var quoteMsgSenderName: String? = nil
    var retracted: Bool = false

    var groupTime: String?
    var msgTimeStr: String?
    var avatar: String?
    private(set) var preparedPayload: ChatMessagePayload

    init(
        messageId: Int64?,
        clientMsgId: String? = nil,
        content: String,
        isMe: Bool,
        timestamp: Date,
        type: String,
        sendStatus: SendStatus,
        errorMessage: String? = nil,
        quoteMsgId: Int64? = nil,
        quoteMsgContent: String? = nil,
        quoteMsgSenderName: String? = nil,
        retracted: Bool = false,
        groupTime: String? = nil,
        msgTimeStr: String? = nil,
        avatar: String? = nil,
        preparedPayload: ChatMessagePayload? = nil
    ) {
        self.messageId = messageId
        self.clientMsgId = clientMsgId
        self.content = content
        self.isMe = isMe
        self.timestamp = timestamp
        self.type = type
        self.sendStatus = sendStatus
        self.errorMessage = errorMessage
        self.quoteMsgId = quoteMsgId
        self.quoteMsgContent = quoteMsgContent
        self.quoteMsgSenderName = quoteMsgSenderName
        self.retracted = retracted
        self.groupTime = groupTime?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? groupTime
            : ChatMessageTimeGrouping.groupTime(for: timestamp)
        self.msgTimeStr = msgTimeStr?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? msgTimeStr
            : ChatMessageTimeGrouping.messageTime(for: timestamp)
        self.avatar = avatar
        self.preparedPayload = preparedPayload
            ?? ChatMessagePayload.parse(content: content, msgType: type)
    }

    mutating func updateContent(
        _ content: String,
        type: String,
        preparedPayload: ChatMessagePayload
    ) {
        self.content = content
        self.type = type
        self.preparedPayload = preparedPayload
    }

    enum SendStatus: Equatable, Sendable {
        case uploadingMedia
        case sending
        case success
        case failed
        case retracted
    }
}

struct ChatHistoryCursorState: Equatable {
    var oldestMessageId: Int64?
    var latestMessageId: Int64?
    var hasOlder: Bool
    var hasNewer: Bool = false
    var isHydrated: Bool
    var windowRevision: UInt64 = 0

    static let empty = ChatHistoryCursorState(
        oldestMessageId: nil,
        latestMessageId: nil,
        hasOlder: true,
        hasNewer: false,
        isHydrated: false,
        windowRevision: 0
    )
}

enum ChatHistoryMergeDirection: Equatable, Sendable {
    case latest
    case older
    case newer
}

struct ChatHistoryWindowResult: Equatable, Sendable {
    let messages: [ChatMessage]
    let droppedOlder: Bool
    let droppedNewer: Bool
}

struct ChatHistoryWindowPolicy {
    static func merge(
        existing: [ChatMessage],
        incoming: [ChatMessage],
        direction: ChatHistoryMergeDirection,
        limit: Int
    ) -> ChatHistoryWindowResult {
        let merged = ChatHistoryMergePolicy.merge(existing: existing, incoming: incoming)
        let boundedLimit = max(0, limit)

        guard merged.count > boundedLimit else {
            return ChatHistoryWindowResult(
                messages: merged,
                droppedOlder: false,
                droppedNewer: false
            )
        }

        switch direction {
        case .latest, .newer:
            return ChatHistoryWindowResult(
                messages: Array(merged.suffix(boundedLimit)),
                droppedOlder: true,
                droppedNewer: false
            )
        case .older:
            return ChatHistoryWindowResult(
                messages: Array(merged.prefix(boundedLimit)),
                droppedOlder: false,
                droppedNewer: true
            )
        }
    }
}

struct ChatReceiptMatcher {
    static func apply(receipt: ChatReceiptDto, to messages: [ChatMessage]) -> [ChatMessage] {
        guard let index = matchingIndex(for: receipt, in: messages) else {
            return messages
        }

        var updated = messages
        var message = updated[index]
        let normalizedStatus = receipt.status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isSuccess = ["SUCCESS", "SUCCEED", "OK", "TRUE", "200"].contains(normalizedStatus)

        message.sendStatus = isSuccess ? .success : .failed
        message.errorMessage = receipt.message
        if isSuccess, receipt.messageId > 0 {
            message.messageId = receipt.messageId
        }
        updated[index] = message
        return updated
    }

    static func matchingIndex(for receipt: ChatReceiptDto, in messages: [ChatMessage]) -> Int? {
        if let clientMsgId = receipt.clientMsgId, !clientMsgId.isEmpty,
           let index = messages.firstIndex(where: { $0.clientMsgId == clientMsgId }) {
            return index
        }

        if receipt.messageId > 0,
           let index = messages.firstIndex(where: { $0.messageId == receipt.messageId }) {
            return index
        }

        return messages.firstIndex { message in
            message.messageId == nil && (message.sendStatus == .sending || message.sendStatus == .uploadingMedia)
        }
    }
}

struct ChatHistoryMergePolicy {
    static func merge(existing: [ChatMessage], incoming: [ChatMessage]) -> [ChatMessage] {
        var serverMessages: [Int64: ChatMessage] = [:]
        var pendingMessages: [ChatMessage] = []

        for message in existing {
            if let messageId = message.messageId {
                serverMessages[messageId] = message
            } else {
                pendingMessages.append(message)
            }
        }

        for message in incoming {
            if let clientMsgId = message.clientMsgId, !clientMsgId.isEmpty {
                pendingMessages.removeAll { $0.clientMsgId == clientMsgId }
                let duplicateIds = serverMessages.compactMap { messageId, serverMessage in
                    serverMessage.clientMsgId == clientMsgId && messageId != message.messageId
                        ? messageId
                        : nil
                }
                for messageId in duplicateIds {
                    serverMessages.removeValue(forKey: messageId)
                }
            }

            if let messageId = message.messageId {
                serverMessages[messageId] = message
            } else if let clientMsgId = message.clientMsgId, !clientMsgId.isEmpty,
                      let index = pendingMessages.firstIndex(where: { $0.clientMsgId == clientMsgId }) {
                pendingMessages[index] = message
            } else {
                pendingMessages.append(message)
            }
        }

        let confirmed = serverMessages.values.sorted {
            ($0.messageId ?? Int64.min) < ($1.messageId ?? Int64.min)
        }
        let pending = pendingMessages.sorted { $0.timestamp < $1.timestamp }
        return confirmed + pending
    }
}

extension ChatMessage {
    var displayText: String {
        preparedPayload.displayText
    }
}
