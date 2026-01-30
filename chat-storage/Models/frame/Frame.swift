//
//  Frame.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/30.
//

import Foundation

/// 自定义协议帧结构
///
/// 帧格式：
/// ```
/// +--------+--------+--------+--------+--------+
/// | Magic  | Type   | Flags  | Length | Data   |
/// | 2字节  | 1字节  | 1字节  | 4字节  | N字节  |
/// +--------+--------+--------+--------+--------+
/// ```
struct Frame {
    // MARK: - Constants
    
    /// 魔数：0xFACE
    static let MAGIC: [UInt8] = [0xFA, 0xCE]
    
    /// 帧头长度：8字节
    static let HEADER_LENGTH = 8
    
    // MARK: - Properties
    
    /// 帧类型
    let type: FrameTypeEnum
    
    /// 标志位（默认0）
    let flags: UInt8
    
    /// 数据长度
    let length: UInt32
    
    /// 帧体数据（JSON 格式）
    let data: Data
    
    // MARK: - Initializers
    
    /// 创建帧
    /// - Parameters:
    ///   - type: 帧类型
    ///   - data: 数据
    ///   - flags: 标志位
    init(type: FrameTypeEnum, data: Data, flags: UInt8 = 0) {
        self.type = type
        self.data = data
        self.length = UInt32(data.count)
        self.flags = flags
    }
    
    // MARK: - Methods
    
    /// 将帧转换为字节数据
    /// - Returns: 完整的帧字节数据
    func toBytes() -> Data {
        var bytes = Data()
        
        // 1. 魔数 (2字节)
        bytes.append(contentsOf: Frame.MAGIC)
        
        // 2. 类型 (1字节)
        bytes.append(type.rawValue)
        
        // 3. 标志位 (1字节)
        bytes.append(flags)
        
        // 4. 长度 (4字节，大端序)
        var lengthBigEndian = length.bigEndian
        bytes.append(Data(bytes: &lengthBigEndian, count: 4))
        
        // 5. 数据 (N字节)
        bytes.append(data)
        
        return bytes
    }
    
    /// 打印帧的十六进制表示（用于调试）
    func hexDescription() -> String {
        let bytes = toBytes()
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// 帧的描述信息
    var description: String {
        return """
        Frame {
          Type: \(type.description) (0x\(String(format: "%02X", type.rawValue)))
          Flags: 0x\(String(format: "%02X", flags))
          Length: \(length) bytes
          Data: \(data.count) bytes
        }
        """
    }
}

// MARK: - Frame Errors

enum FrameError: LocalizedError {
    case invalidMagic
    case invalidType(UInt8)
    case invalidLength
    case insufficientData
    case encodingFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "帧格式错误：魔数不匹配"
        case .invalidType(let type):
            return "帧格式错误：未知的帧类型 0x\(String(format: "%02X", type))"
        case .invalidLength:
            return "帧格式错误：长度字段无效"
        case .insufficientData:
            return "帧格式错误：数据不完整"
        case .encodingFailed:
            return "JSON 编码失败"
        case .decodingFailed:
            return "JSON 解码失败"
        }
    }
}
