//
//  TransferModels.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/7.
//  Consolidated transfer types and manager
//

import Foundation
import Combine



// MARK: - Friend & User Models

/// 用户信息响应 (Search Result)
public struct UserDto: Codable, Identifiable {
    public let id: Int64
    public let userName: String
    public let nickName: String?
    public let avatar: String?
    public let status: Int? // 0=正常, 1=禁用
    
    public var identifiableId: String { String(id) }
    
    enum CodingKeys: String, CodingKey {
        case id = "userId" // 兼容后端的 userId
        case userName
        case nickName
        case avatar
        case status
    }
    
    // 增加一个备用的 CodingKeys 用于 fallback
    enum FallbackCodingKeys: String, CodingKey {
        case id
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 尝试从 userId 读取
        if let userId = try? container.decodeIfPresent(Int64.self, forKey: .id) {
            self.id = userId
        } else {
            // fallback: 尝试直接从 id 读取
            let fallbackContainer = try decoder.container(keyedBy: FallbackCodingKeys.self)
            if let rawId = try? fallbackContainer.decodeIfPresent(Int64.self, forKey: .id) {
                self.id = rawId
            } else {
                self.id = 0
            }
        }
        
        self.userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? ""
        self.nickName = try container.decodeIfPresent(String.self, forKey: .nickName)
        self.avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        self.status = try container.decodeIfPresent(Int.self, forKey: .status)
    }
}

/// 好友信息响应 (Data Transfer Object)
public struct FriendDto: Codable, Identifiable, Equatable {
    /// 关联ID
    public let id: Int64
    /// 用户ID
    public let userId: Int64
    /// 好友ID
    public let friendId: Int64
    /// 备注
    public let alias: String?
    /// 用户名
    public let userName: String
    /// 昵称
    public let nickName: String
    /// 头像 (Base64编码字符串)
    public let avatar: String?
    /// 未读消息数
    public let unreadCount: Int32?
    /// 最新未读消息内容
    public let latestUnreadMsg: String?
    
    // Identifiable (使用好友ID作为唯一标识)
    public var identifiableId: String { String(friendId) }
}

/// 好友申请信息 (Request DTO)
public struct FriendRequestDto: Codable, Identifiable {
    public let id: Int64
    public let senderId: Int64
    public let receiverId: Int64
    public let requestMsg: String
    public let status: Int // 0=待处理, 1=已同意, 2=已拒绝
    public let createTime: Int64
    
    // 附加发送者信息
    public let senderUserName: String
    public let senderNickName: String
    public let senderAvatar: String?
    
    public var identifiableId: String { String(id) }
}


// MARK: - Chat Models

/// 发送聊天请求 (0x50)
public struct ChatSendRequestDto: Codable {
    public let receiverId: Int32
    public let content: String
    public let msgType: String // TEXT, IMAGE, FILE
}

/// 接收聊天消息推送 (0x51)
public struct ChatPushDto: Codable, Identifiable {
    public let messageId: Int32
    public let senderId: Int32
    public let content: String
    public let msgType: String
    public let avatar: String?
    public let gmtCreated: Int64
    
    public var id: Int32 { messageId }
}

/// 接收聊天消息回执 (0x52)
public struct ChatReceiptDto: Codable {
    public let messageId: Int32
    public let status: String // "success" or "false"
}

/// 历史聊天记录请求 (0x53)
public struct ChatHistoryRequestDto: Codable {
    public let friendId: Int32
    public let offset: Int32
    public let limit: Int32
    
    public init(friendId: Int32, offset: Int32 = 0, limit: Int32 = 20) {
        self.friendId = friendId
        self.offset = offset
        self.limit = limit
    }
}

/// 历史聊天记录响应单条 (0x53)
public struct ChatHistoryItemDto: Codable {
    public var id: Int64 = 0
    public var senderId: Int32 = 0
    public var receiverId: Int32 = 0
    public var content: String = ""
    public var msgType: String = ""
    public var status: Int32 = 0
    public var avatar: String?
    public var groupTime: String = ""
    public var msgTimeStr: String = ""
    
    // 自定义解码器增加容错性，防止某个字段类型不匹配导致整个 0x54 接包失败
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 尝试解析 ID
        if let intId = try? container.decodeIfPresent(Int64.self, forKey: .id) {
            self.id = intId
        } else if let strId = try? container.decodeIfPresent(String.self, forKey: .id), let intId = Int64(strId) {
            self.id = intId
        }
        
        self.senderId = (try? container.decodeIfPresent(Int32.self, forKey: .senderId)) ?? 0
        self.receiverId = (try? container.decodeIfPresent(Int32.self, forKey: .receiverId)) ?? 0
        self.content = (try? container.decodeIfPresent(String.self, forKey: .content)) ?? ""
        
        // msgType 兼容 String 和 Int32
        if let intMsgType = try? container.decodeIfPresent(Int32.self, forKey: .msgType) {
            self.msgType = String(intMsgType)
        } else if let strMsgType = try? container.decodeIfPresent(String.self, forKey: .msgType) {
            self.msgType = strMsgType
        }
        
        // status 兼容 Int 和 String
        if let intStatus = try? container.decodeIfPresent(Int32.self, forKey: .status) {
            self.status = intStatus
        } else if let strStatus = try? container.decodeIfPresent(String.self, forKey: .status), let intStatus = Int32(strStatus) {
            self.status = intStatus
        }
        
        self.avatar = try? container.decodeIfPresent(String.self, forKey: .avatar)
        self.groupTime = (try? container.decodeIfPresent(String.self, forKey: .groupTime)) ?? ""
        self.msgTimeStr = (try? container.decodeIfPresent(String.self, forKey: .msgTimeStr)) ?? ""
    }
}

/// 历史聊天记录响应体 (0x54) 优化后的 Data 包装层
public struct ChatHistoryResponseDataDto: Codable {
    public let list: [ChatHistoryItemDto]
    public let avatars: [String: String]?
    
    public init(list: [ChatHistoryItemDto] = [], avatars: [String: String]? = nil) {
        self.list = list
        self.avatars = avatars
    }
}

/// 清除未读红点请求 (0x55)
public struct ChatClearUnreadRequestDto: Codable {
    public let friendId: Int32
    
    public init(friendId: Int32) {
        self.friendId = friendId
    }
}
