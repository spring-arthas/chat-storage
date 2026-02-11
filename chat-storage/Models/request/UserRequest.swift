//
//  UserRequest.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

/// 用户请求实体（用于登录和注册）
struct UserRequest: Codable {
    /// 用户名
    let userName: String
    
    /// 密码（明文）
    let password: String
    
    /// 邮箱（注册时必填，登录时可选）
    let mail: String?
    
    /// 头像数据 (Base64 编码的图片数据)
    let avatarData: String?
    
    /// 头像文件名 (可选)
    let avatarName: String?
    
    // MARK: - Initializers
    
    /// 创建登录请求
    /// - Parameters:
    ///   - userName: 用户名
    ///   - password: 密码
    init(userName: String, password: String) {
        self.userName = userName
        self.password = password
        self.mail = nil
        self.avatarData = nil
        self.avatarName = nil
    }
    
    /// 创建注册请求
    /// - Parameters:
    ///   - userName: 用户名
    ///   - password: 密码
    ///   - mail: 邮箱
    ///   - avatarData: 头像数据 (Base64)
    ///   - avatarName: 头像文件名
    init(userName: String, password: String, mail: String, avatarData: String? = nil, avatarName: String? = nil) {
        self.userName = userName
        self.password = password
        self.mail = mail
        self.avatarData = avatarData
        self.avatarName = avatarName
    }
}
