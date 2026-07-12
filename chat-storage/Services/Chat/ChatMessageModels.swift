//
//  ChatMessageModels.swift
//  chat-storage
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    var id: String {
        if let mid = messageId {
            return "msg-\(mid)"
        }
        return localId.uuidString
    }

    let localId = UUID()
    var messageId: Int32?
    var clientMsgId: String? = nil
    var content: String
    let isMe: Bool
    let timestamp: Date
    var type: String
    var sendStatus: SendStatus
    var errorMessage: String? = nil
    var quoteMsgId: Int64? = nil
    var quoteMsgContent: String? = nil
    var quoteMsgSenderName: String? = nil
    var retracted: Bool = false

    var groupTime: String?
    var msgTimeStr: String?
    var avatar: String?

    enum SendStatus: Equatable {
        case uploadingMedia
        case sending
        case success
        case failed
        case retracted
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

extension ChatMessage {
    var displayText: String {
        ChatMessagePayload.parse(content: content, msgType: type).displayText
    }
}
