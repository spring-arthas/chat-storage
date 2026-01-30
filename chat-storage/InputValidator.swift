//
//  InputValidator.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

/// 输入验证工具类
/// 提供用户名（手机号/邮箱）和密码的格式验证
struct InputValidator {
    
    // MARK: - 手机号验证
    
    /// 验证中国大陆手机号
    /// - Parameter phone: 待验证的手机号字符串
    /// - Returns: 是否为有效的11位手机号（1开头，第二位3-9）
    static func isValidPhone(_ phone: String) -> Bool {
        // 手机号正则：1开头，第二位3-9，总共11位数字
        let phonePattern = "^1[3-9]\\d{9}$"
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phonePattern)
        return phonePredicate.evaluate(with: phone)
    }
    
    // MARK: - 邮箱验证
    
    /// 验证邮箱格式
    /// - Parameter email: 待验证的邮箱字符串
    /// - Returns: 是否为有效的邮箱格式
    static func isValidEmail(_ email: String) -> Bool {
        // 邮箱正则：标准邮箱格式
        let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailPattern)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: - 用户名验证
    
    /// 验证用户名（手机号或邮箱）
    /// - Parameter username: 待验证的用户名
    /// - Returns: 是否为有效的手机号或邮箱
    static func isValidUsername(_ username: String) -> Bool {
        return isValidPhone(username) || isValidEmail(username)
    }
    
    // MARK: - 密码验证
    
    /// 验证密码格式
    /// - Parameter password: 待验证的密码
    /// - Returns: 是否符合密码要求（长度 >= 6）
    static func isValidPassword(_ password: String) -> Bool {
        return password.count >= 6
    }
    
    // MARK: - 错误消息生成
    
    /// 根据用户名格式返回友好的错误提示
    /// - Parameter username: 用户输入的用户名
    /// - Returns: 错误提示信息
    static func getUsernameErrorMessage(_ username: String) -> String {
        if username.isEmpty {
            return "请输入手机号或邮箱"
        }
        
        // 判断用户可能想输入的是什么
        if username.contains("@") {
            return "邮箱格式不正确"
        } else if username.allSatisfy({ $0.isNumber }) {
            if username.count != 11 {
                return "手机号应为11位数字"
            } else if !username.hasPrefix("1") {
                return "手机号应以1开头"
            } else {
                return "手机号格式不正确"
            }
        } else {
            return "请输入有效的手机号或邮箱"
        }
    }
    
    /// 获取密码错误提示
    /// - Parameter password: 用户输入的密码
    /// - Returns: 错误提示信息
    static func getPasswordErrorMessage(_ password: String) -> String {
        if password.isEmpty {
            return "请输入密码"
        } else if password.count < 6 {
            return "密码长度至少为6位"
        }
        return ""
    }
}
