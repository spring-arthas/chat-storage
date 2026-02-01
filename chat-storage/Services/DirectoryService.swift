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
            data: Data(),
            flags: 0x00
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
    
    /// 创建目录
    /// - Parameters:
    ///   - pId: 父目录ID
    ///   - name: 目录名称
    /// - Throws: 网络或服务端错误
    func createDirectory(pId: Int64, name: String) async throws {
        print("📂 请求创建目录: pId=\(pId), name=\(name)")
        
        // 使用 Codable 结构体构建请求，确保类型安全
        struct CreateDirRequest: Codable {
            let pId: Int64
            let dirName: String
        }
        
        let request = CreateDirRequest(pId: pId, dirName: name)
        let jsonData = try JSONEncoder().encode(request)
        
        // 打印发送的 JSON
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 发送目录创建请求: \(jsonString)")
        }
        
        // 创建目录新建请求帧 (0x10)
        let frame = Frame(
            type: .dirCreateReq,
            data: jsonData,
            flags: 0x00
        )
        
        // 发送帧并等待响应 (0x14)
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .dirResponse,
            timeout: 10.0
        )
        
        // 解析响应 (仅检查是否成功)
        _ = try parseDirectoryResponse(responseFrame)
        // 注意：这里我们忽略了解析后的 DirectoryItem，因为我们会手动刷新整个列表
        
        print("✅ 目录创建成功")
    }

    /// 重命名目录 (0x12)
    /// - Parameters:
    ///   - id: 目录ID
    ///   - name: 新名称
    /// - Throws: 网络或服务端错误
    func renameDirectory(id: Int64, name: String) async throws {
        print("📂 请求重命名目录: id=\(id), name=\(name)")
        
        struct RenameDirRequest: Codable {
            let id: Int64
            let dirName: String
        }
        
        let request = RenameDirRequest(id: id, dirName: name)
        let jsonData = try JSONEncoder().encode(request)
        
        let frame = Frame(
            type: .dirUpdateReq,
            data: jsonData,
            flags: 0x00
        )
        
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .dirResponse,
            timeout: 10.0
        )
        _ = try parseDirectoryResponse(responseFrame)
        print("✅ 目录重命名成功")
    }
    
    /// 删除目录 (0x11)
    /// - Parameter id: 目录ID
    /// - Throws: 网络或服务端错误
    func deleteDirectory(id: Int64) async throws {
        print("📂 请求删除目录: id=\(id)")
        
        struct DeleteDirRequest: Codable {
            let id: Int64
        }
        
        let request = DeleteDirRequest(id: id)
        let jsonData = try JSONEncoder().encode(request)
        
        let frame = Frame(
            type: .dirDeleteReq,
            data: jsonData,
            flags: 0x00
        )
        
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .dirResponse,
            timeout: 10.0
        )
        _ = try parseDirectoryResponse(responseFrame)
        print("✅ 目录删除成功")
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
        
        // 1. 优先检查 success 字段 (布尔值)
        if let success = dict["success"] as? Bool {
            if !success {
                let message = dict["message"] as? String ?? "未知错误"
                // 也可以获取 errorCode: dict["errorCode"] as? String
                throw DirectoryError.serverError(code: 500, message: message)
            }
        } else {
            // 兼容旧逻辑：如果没有 success 字段，检查 code
            if let code = dict["code"] as? Int, code != 200 {
                let message = dict["message"] as? String ?? "未知错误"
                throw DirectoryError.serverError(code: code, message: message)
            }
        }
        
        // 2. 获取 data 字段 (可能为 nil)
        guard let data = dict["data"] else {
            // 如果成功但没有 data，视为空列表或无返回值操作成功，返回空数组
            print("⚠️ 响应中没有 data 字段，视为操作成功但无返回数据")
            return []
        }
        
        // 如果 data 本身就是 null (NSNull)
        if data is NSNull {
            print("⚠️ 响应中 data 字段为 null，视为操作成功但无返回数据")
            return []
        }
        
        // 3. 将 data 转换为 JSON 数据
        let jsonData: Data
        if let dataDict = data as? [String: Any] {
            jsonData = try JSONSerialization.data(withJSONObject: dataDict, options: .prettyPrinted)
        } else if let dataArray = data as? [[String: Any]] {
            jsonData = try JSONSerialization.data(withJSONObject: dataArray)
        } else {
            // data 既不是字典也不是数组，可能是字符串或其他，暂时视为无效格式或不需要解析
           print("⚠️ data 字段格式不是字典或数组: \(type(of: data))")
           return []
        }
        
        // 4. 解析为 FileDto
        let decoder = JSONDecoder()
        
        // 尝试解析为单个 FileDto
        if let fileDto = try? decoder.decode(FileDto.self, from: jsonData) {
            print("✅ 成功解析为单个 FileDto: \(fileDto.fileName)")
            return [fileDto.toDirectoryItem()]
        }
        
        // 尝试解析为 FileDto 数组
        if let fileDtos = try? decoder.decode([FileDto].self, from: jsonData) {
            print("✅ 成功解析为 FileDto 数组，共 \(fileDtos.count) 项")
            return fileDtos.map { $0.toDirectoryItem() }
        }
        
        // 解析失败但不抛出错误，防止打断流程 (除非确实需要严格校验)
        print("⚠️ 无法将 data 解析为 FileDto 或 [FileDto]，返回空数组")
        return []
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
