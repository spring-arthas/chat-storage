//
//  UserSearchModels.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/11.
//

import Foundation

/// 搜索用户请求
struct UserSearchRequest: Codable {
    /// 搜索的用户名关键词
    let userName: String
}

/// 搜索用户响应 (Data Transfer Object)
struct UserDto: Codable, Identifiable {
    /// 用户ID
    let userId: String
    /// 昵称
    let nickName: String
    /// 头像 (Base64编码字符串)
    let avatar: String?
    
    // Identifiable
    var id: String { userId }
}
