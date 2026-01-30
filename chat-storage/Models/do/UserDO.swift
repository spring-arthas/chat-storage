//
//  UserDO.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

/// 用户数据对象（服务端返回）
struct UserDO: Codable {
    /// 用户名
    let userName: String
    
    /// 密码（通常不返回或返回加密后的）
    let password: String?
    
    /// 邮箱
    let mail: String
    
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
struct ResponseWrapper<T: Codable>: Codable {
    /// 响应码（200=成功，其他=失败）
    let code: Int
    
    /// 响应消息
    let message: String
    
    /// 响应数据（可选）
    let data: T?
    
    /// 是否成功
    var isSuccess: Bool {
        return code == 200
    }
}

/// 空响应（当不需要返回数据时）
struct EmptyResponse: Codable {}
