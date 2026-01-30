//
//  UserDO.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

/// 用户数据对象（服务端返回）
struct UserDO: Codable {
    /// 用户 ID
    let userId: Int?
    
    /// 用户名
    let userName: String
    
    /// 认证令牌（登录成功后返回）
    let token: String?
    
    /// 密码（通常不返回或返回加密后的）
    let password: String?
    
    /// 邮箱
    let mail: String?
    
    /// 最后登录时间（ISO 8601 格式）
    let lastLoginDate: String?
    
    /// 注册时间（ISO 8601 格式）
    let registerDate: String?
    
    // MARK: - Computed Properties
    
    /// 最后登录时间对象
    var lastLoginDateTime: Date? {
        guard let dateString = lastLoginDate else { return nil }
        return ISO8601DateFormatter().date(from: dateString)
    }
    
    /// 注册时间对象
    var registerDateTime: Date? {
        guard let dateString = registerDate else { return nil }
        return ISO8601DateFormatter().date(from: dateString)
    }
}

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
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case success
        case codeValue = "code"
        case message
        case data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 尝试解码 success 字段
        success = try? container.decode(Bool.self, forKey: .success)
        
        // 尝试解码 code 字段
        codeValue = try? container.decode(Int.self, forKey: .codeValue)
        
        // message 是必需的
        message = try container.decode(String.self, forKey: .message)
        
        // data 是可选的
        data = try? container.decode(T.self, forKey: .data)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        if let success = success {
            try container.encode(success, forKey: .success)
        }
        
        if let codeValue = codeValue {
            try container.encode(codeValue, forKey: .codeValue)
        }
        
        try container.encode(message, forKey: .message)
        
        if let data = data {
            try container.encode(data, forKey: .data)
        }
    }
}

/// 空响应（当不需要返回数据时）
struct EmptyResponse: Codable {}
