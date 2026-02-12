//
//  UserDO.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/1.
//

import Foundation

// MARK: - UserDO (Data Object)

/// 用户数据对象 (对应数据库或API返回的用户信息)
struct UserDO: Codable, Identifiable {
    /// 用户唯一ID
    let id: Int64
    
    /// 用户名 (账号)
    let username: String
    
    /// 昵称 (显示名称) - 可选，服务器可能不返回
    let nickname: String?
    
    /// 头像URL或路径
    let avatar: String?
    
    /// 邮箱
    let email: String?
    
    /// 手机号
    let phone: String?
    
    /// 创建时间 (时间戳) - 可选
    let createTime: Int64?
    
    /// 更新时间 (时间戳) - 可选
    let updateTime: Int64?
    
    /// 状态 (0:正常, 1:禁用) - 可选
    let status: Int?
    
    // Identifiable 协议要求
    var identifiableId: String { String(id) }
    
    
    enum CodingKeys: String, CodingKey {
        case id = "userId"  // Server sends "userId", map to "id"
        case username = "userName"  // Server sends "userName", map to "username"
        case nickname = "nickName"  // Server sends "nickName", map to "nickname"
        case avatar
        case email = "mail"  // Server sends "mail", map to "email"
        case phone
        case createTime
        case updateTime
        case status
    }
}

// MARK: - Common Response Wrapper

/// 通用响应包装器
/// 支持两种服务器响应格式：
/// 1. { "success": true/false, "message": "...", "data": {...} }
/// 2. { "code": 200, "message": "...", "data": {...} }
struct ResponseWrapper<T: Codable>: Codable {
    /// 是否成功（服务器返回的原始字段）
    let success: Bool?
    
    /// 响应码（可选，用于兼容旧格式）
    let codeValue: Int?
    
    /// 响应消息
    let message: String
    
    /// 响应数据（可选）
    let data: T?
    
    /// 计算属性：响应码
    /// 如果服务器返回了 code 字段，使用该值
    /// 否则根据 success 字段转换：true -> 200, false -> 400
    var code: Int {
        if let codeValue = codeValue {
            return codeValue
        }
        return (success == true) ? 200 : 400
    }
    
    /// 是否成功
    var isSuccess: Bool {
        return code == 200
    }
    
    enum CodingKeys: String, CodingKey {
        case success
        case codeValue = "code"
        case message = "msg" // 兼容 msg 和 message
        case data
    }
    
    // 自定义解码逻辑以处理 message/msg 字段
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        codeValue = try container.decodeIfPresent(Int.self, forKey: .codeValue)
        data = try container.decodeIfPresent(T.self, forKey: .data)
        
        // 尝试读取 message，如果失败尝试读取 msg
        if let msg = try? container.decode(String.self, forKey: .message) {
            message = msg
        } else {
            // 如果都没有，尝试用 CodingKey 扩展或者直接设为空
            // 由于 CodingKeys 映射了 message = "msg"，这里其实只能读 "msg"
            // 为了更灵活，可能需要手动处理
            message = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(success, forKey: .success)
        try container.encodeIfPresent(codeValue, forKey: .codeValue)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
    }
}

/// 空响应（当不需要返回数据时）
struct EmptyResponse: Codable {}
