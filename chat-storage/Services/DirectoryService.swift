//
//  DirectoryService.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/31.
//

import Foundation

/// 目录服务 - 处理目录加载和解析
@MainActor
class DirectoryService: ObservableObject {
    
    private let socketManager: SocketManager
    
    /// 初始化
    init(socketManager: SocketManager) {
        self.socketManager = socketManager
    }
    
    /// 加载目录树
    /// - Returns: 目录项数组
    /// - Throws: 网络或解析错误
    func loadDirectoryTree() async throws -> [DirectoryItem] {
        print("📂 开始加载目录树...")
        
        // 创建目录列表请求帧 (0x15, 空body)
        let frame = Frame(
            type: .dirListReq,
            flags: 0x00,
            data: Data()
        )
        
        // 发送帧并等待响应
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .dirResponse,
            timeout: 15.0
        )
        
        print("📥 收到目录响应，开始解析...")
        
        // 解析响应
        let directoryItems = try parseDirectoryResponse(responseFrame)
        
        print("✅ 目录树加载完成，共 \(directoryItems.count) 个顶级项")
        
        return directoryItems
    }
    
    /// 解析目录响应帧
    /// - Parameter frame: 响应帧
    /// - Returns: 目录项数组
    /// - Throws: 解析错误
    private func parseDirectoryResponse(_ frame: Frame) throws -> [DirectoryItem] {
        // 解析为字典
        guard let dict = try? FrameParser.decodeAsDictionary(frame) else {
            throw DirectoryError.invalidResponse("无法解析响应为字典")
        }
        
        // 检查响应码
        if let code = dict["code"] as? Int, code != 200 {
            let message = dict["message"] as? String ?? "未知错误"
            throw DirectoryError.serverError(code: code, message: message)
        }
        
        // 获取 data 字段
        guard let data = dict["data"] else {
            throw DirectoryError.invalidResponse("响应中缺少 data 字段")
        }
        
        // 将 data 转换为 JSON 数据
        let jsonData: Data
        if let dataDict = data as? [String: Any] {
            jsonData = try JSONSerialization.data(withJSONObject: dataDict)
        } else if let dataArray = data as? [[String: Any]] {
            jsonData = try JSONSerialization.data(withJSONObject: dataArray)
        } else {
            throw DirectoryError.invalidResponse("data 字段格式不正确")
        }
        
        // 解析为 FileDto
        let decoder = JSONDecoder()
        
        // 尝试解析为单个 FileDto
        if let fileDto = try? decoder.decode(FileDto.self, from: jsonData) {
            return [fileDto.toDirectoryItem()]
        }
        
        // 尝试解析为 FileDto 数组
        if let fileDtos = try? decoder.decode([FileDto].self, from: jsonData) {
            return fileDtos.map { $0.toDirectoryItem() }
        }
        
        throw DirectoryError.invalidResponse("无法解析 data 为 FileDto")
    }
}

/// 目录错误
enum DirectoryError: LocalizedError {
    case invalidResponse(String)
    case serverError(code: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail):
            return "响应数据无效: \(detail)"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        }
    }
}
