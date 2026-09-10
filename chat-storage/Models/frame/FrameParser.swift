//
//  FrameParser.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

/// 帧解析器
class FrameParser {
    
    /// 从字节数据解析帧
    /// - Parameter data: 字节数据
    /// - Returns: 解析出的帧
    /// - Throws: FrameError
    static func parse(from data: Data) throws -> Frame {
        // 1. 检查最小长度（至少要有帧头）
        guard data.count >= Frame.HEADER_LENGTH else {
            throw FrameError.insufficientData
        }

        let header = try parseHeader(from: data)
        
        // 6. 验证数据长度
        let expectedTotalLength = Frame.HEADER_LENGTH + header.length
        guard data.count >= expectedTotalLength else {
            print("❌ 数据长度不足: 期望 \(expectedTotalLength), 实际 \(data.count)")
            throw FrameError.insufficientData
        }
        
        // 7. 提取帧体数据
        let frameData = data[Frame.HEADER_LENGTH..<expectedTotalLength]
        
        // 8. 构建帧对象
        let frame = Frame(type: header.type, data: Data(frameData), flags: header.flags)
        
        /*print("✅ 帧解析成功: \(type.description), 数据长度:\(length)")*/
        return frame
    }
    
    /// 从帧中解码 JSON 数据为指定类型
    /// - Parameters:
    ///   - frame: 帧对象
    ///   - type: 目标类型
    /// - Returns: 解码后的对象
    /// - Throws: FrameError.decodingFailed
    static func decodePayload<T: Decodable>(
        _ frame: Frame,
        as type: T.Type
    ) throws -> T {
        let decoder = JSONDecoder()
        
        do {
            let object = try decoder.decode(type, from: frame.data)
            return object
        } catch {
            print("❌ JSON 解码失败: \(error)")
            print("数据内容: \(String(data: frame.data, encoding: .utf8) ?? "无法解析")")
            throw FrameError.decodingFailed
        }
    }
    
    /// 从帧中解码为字典
    /// - Parameter frame: 帧对象
    /// - Returns: 字典
    /// - Throws: FrameError.decodingFailed
    static func decodeAsDictionary(_ frame: Frame) throws -> [String: Any] {
        do {
            let dictionary = try JSONSerialization.jsonObject(with: frame.data, options: []) as? [String: Any]
            return dictionary ?? [:]
        } catch {
            print("❌ 解码为字典失败: \(error)")
            throw FrameError.decodingFailed
        }
    }
    
    /// 尝试从数据流中提取一个完整的帧
    /// - Parameter buffer: 数据缓冲区
    /// - Returns: (提取的帧, 剩余数据)，如果数据不完整返回 nil
    static func extractFrame(from buffer: Data) throws -> (frame: Frame, remaining: Data)? {
        // 至少需要帧头
        guard buffer.count >= Frame.HEADER_LENGTH else {
            return nil
        }

        // [修改] 先验证完整帧头，超长、错魔数和未知类型不能伪装成“正文还没收完”。
        let header = try parseHeader(from: buffer)
        let totalLength = Frame.HEADER_LENGTH + header.length
        
        // 检查是否有完整的帧
        guard buffer.count >= totalLength else {
            return nil
        }
        
        // 提取完整帧数据
        let frameData = buffer[0..<totalLength]
        let remaining = buffer[totalLength...]
        
        // [修改] 解析错误交给连接层处理，禁止吞错后永久卡在同一批坏数据上。
        let frame = try parse(from: Data(frameData))
        return (frame, Data(remaining))
    }

    private static func parseHeader(
        from data: Data
    ) throws -> (type: FrameTypeEnum, flags: UInt8, length: Int) {
        let magic = [data[0], data[1]]
        guard magic == Frame.MAGIC else {
            throw FrameError.invalidMagic
        }

        let typeRawValue = data[2]
        guard let type = FrameTypeEnum(rawValue: typeRawValue) else {
            throw FrameError.invalidType(typeRawValue)
        }

        let lengthBytes = data[4..<8]
        let payloadLength = lengthBytes.withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self).bigEndian
        }
        guard payloadLength <= UInt32(Frame.maxPayloadLength) else {
            throw FrameError.invalidLength
        }

        return (type, data[3], Int(payloadLength))
    }
}
