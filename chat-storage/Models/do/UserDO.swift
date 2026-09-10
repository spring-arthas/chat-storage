//
//  UserDO.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/1.
//

import Foundation

// MARK: - UserDO (Data Object)

/// 用户数据对象 (对应数据库或API返回的用户信息)
struct UserDO: Codable, Identifiable, Equatable {
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

    /// 登录后由服务端签发，用于文件上传、下载和图片流请求认证。
    let transferToken: String?

    /// 登录后由服务端签发，用于应用重启、回到前台和传输令牌刷新时恢复会话。
    let sessionToken: String?

    init(
        id: Int64,
        username: String,
        nickname: String?,
        avatar: String?,
        email: String?,
        phone: String?,
        createTime: Int64?,
        updateTime: Int64?,
        status: Int?,
        transferToken: String?,
        sessionToken: String? = nil
    ) {
        self.id = id
        self.username = username
        self.nickname = nickname
        self.avatar = avatar
        self.email = email
        self.phone = phone
        self.createTime = createTime
        self.updateTime = updateTime
        self.status = status
        self.transferToken = transferToken
        self.sessionToken = sessionToken
    }
    
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
        case transferToken
        case sessionToken
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

    /// 认证类失败的稳定错误码，例如 SESSION_EXPIRED。
    let errorCode: String?
    
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
        case message
        case msg
        case data
        case errorCode
    }
    
    // 自定义解码逻辑以处理 message/msg 字段
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        codeValue = try container.decodeIfPresent(Int.self, forKey: .codeValue)
        data = try container.decodeIfPresent(T.self, forKey: .data)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        
        // 尝试读取 message，如果失败尝试读取 msg
        message = (try? container.decode(String.self, forKey: .message))
            ?? (try? container.decode(String.self, forKey: .msg))
            ?? ""
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(success, forKey: .success)
        try container.encodeIfPresent(codeValue, forKey: .codeValue)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(errorCode, forKey: .errorCode)
    }
}

/// 空响应（当不需要返回数据时）
struct EmptyResponse: Codable {}
