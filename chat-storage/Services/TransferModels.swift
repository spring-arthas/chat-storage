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
    public let nickName: String
    public let avatar: String?
    public let status: Int // 0=正常, 1=禁用
    
    public var identifiableId: String { String(id) }
}

/// 好友信息响应 (Data Transfer Object)
public struct FriendDto: Codable, Identifiable {
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
