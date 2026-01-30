//
//  FrameBuilder.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

/// 帧构建器
class FrameBuilder {
    
    /// 构建帧（使用 Codable 对象）
    /// - Parameters:
    ///   - type: 帧类型
    ///   - payload: 可编码的负载对象
    ///   - flags: 标志位
    /// - Returns: 构建好的帧
    /// - Throws: FrameError.encodingFailed
    static func build<T: Encodable>(
        type: FrameTypeEnum,
        payload: T,
        flags: UInt8 = 0
    ) throws -> Frame {
        // 将 payload 编码为 JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted  // 便于调试
        
        do {
            let jsonData = try encoder.encode(payload)
            return Frame(type: type, data: jsonData, flags: flags)
        } catch {
            print("❌ JSON 编码失败: \(error)")
            throw FrameError.encodingFailed
        }
    }
    
    /// 构建帧（使用原始 JSON 数据）
    /// - Parameters:
    ///   - type: 帧类型
    ///   - jsonData: JSON 数据
    ///   - flags: 标志位
    /// - Returns: 构建好的帧
    static func build(
        type: FrameTypeEnum,
        jsonData: Data,
        flags: UInt8 = 0
    ) -> Frame {
        return Frame(type: type, data: jsonData, flags: flags)
    }
    
    /// 构建帧（使用字典）
    /// - Parameters:
    ///   - type: 帧类型
    ///   - dictionary: 字典数据
    ///   - flags: 标志位
    /// - Returns: 构建好的帧
    /// - Throws: FrameError.encodingFailed
    static func build(
        type: FrameTypeEnum,
        dictionary: [String: Any],
        flags: UInt8 = 0
    ) throws -> Frame {
        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: dictionary,
                options: .prettyPrinted
            )
            return Frame(type: type, data: jsonData, flags: flags)
        } catch {
            print("❌ 字典转 JSON 失败: \(error)")
            throw FrameError.encodingFailed
        }
    }
    
    /// 构建空帧（无数据）
    /// - Parameters:
    ///   - type: 帧类型
    ///   - flags: 标志位
    /// - Returns: 构建好的帧
    static func buildEmpty(
        type: FrameTypeEnum,
        flags: UInt8 = 0
    ) -> Frame {
        return Frame(type: type, data: Data(), flags: flags)
    }
}

// MARK: - 便捷方法（用于常用帧类型）

extension FrameBuilder {
    
    /// 构建用户登录请求帧
    static func buildLoginRequest(userName: String, password: String) throws -> Frame {
        let request = ["userName": userName, "password": password]
        return try build(type: .userLoginReq, dictionary: request)
    }
    
    /// 构建用户注册请求帧
    static func buildRegisterRequest(userName: String, password: String, mail: String) throws -> Frame {
        let request = ["userName": userName, "password": password, "mail": mail]
        return try build(type: .userRegisterReq, dictionary: request)
    }
}
