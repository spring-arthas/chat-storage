//
//  DirectoryService.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/31.
//

import Foundation
import Combine
import CommonCrypto
import AppKit

/// 目录服务 - 处理目录加载和解析
@MainActor
class DirectoryService: ObservableObject {
    func test() { print("Test") }
    func test2(id: Int64) {}
    func test3(delegate: VideoStreamLoaderDelegate) {}
    
    private let socketManager: SocketManager
    
    /// 初始化
    init(socketManager: SocketManager) {
        self.socketManager = socketManager
    }
    
    var transferManager: TransferTaskManager {
        TransferTaskManager.shared
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
        let directoryItems = try Self.parseDirectoryResponse(responseFrame)
        
        print("✅ 目录树加载完成，共 \(directoryItems.count) 个顶级项")
        
        return directoryItems
    }

    /// 按目录 ID 懒加载下一层目录节点。
    func loadDirectoryChildren(dirId: Int64) async throws -> [DirectoryItem] {
        print("📂 请求加载子目录: dirId=\(dirId)")

        let request: [String: Any] = ["dirId": dirId]
        let frame = try FrameBuilder.build(type: .dirListReq, dictionary: request)

        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .dirResponse,
            timeout: 15.0
        )

        let items = try Self.parseDirectoryResponse(responseFrame)
        let children = (items.first?.childFileList ?? items).filter { !$0.isFile }
        print("✅ 子目录加载完成: dirId=\(dirId), directoryCount=\(children.count)")
        return children
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
        _ = try Self.parseDirectoryResponse(responseFrame)
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
        _ = try Self.parseDirectoryResponse(responseFrame)
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
        _ = try Self.parseDirectoryResponse(responseFrame)
        print("✅ 目录删除成功")
    }
    
    /// 分页获取文件列表 (0x40)
    /// - Parameters:
    ///   - dirId: 目录ID
    ///   - fileName: 文件名关键字
    ///   - pageNum: 页码
    ///   - pageSize: 每页大小
    /// - Returns: 分页结果
    func fetchFileList(
        dirId: Int64,
        fileName: String = "",
        pageNum: Int = 1,
        pageSize: Int = 10
    ) async throws -> PageResult<FileDto> {
        print("📂 请求加载文件列表: dirId=\(dirId), fileName=\(fileName), page=\(pageNum)")
        
        let request = FileListRequest(
            dirId: dirId,
            fileName: fileName,
            pageNum: pageNum,
            pageSize: pageSize
        )
        let jsonData = try JSONEncoder().encode(request)
        
        let frame = Frame(
            type: .fileListReq,
            data: jsonData,
            flags: 0x00
        )
        
        // 发送并等待响应（仅等待文件响应，避免与其他并发请求（如目录树）冲突）
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .fileResponse,
            timeout: 15.0
        )
        
        // 解析响应
        guard let dict = try? FrameParser.decodeAsDictionary(responseFrame) else {
            throw DirectoryError.invalidResponse("无法解析响应为字典 [FrameType: \(responseFrame.type.description)]")
        }
        
        // 检查业务状态码
        if let code = dict["code"] as? Int, code != 200 {
            let message = dict["message"] as? String ?? "未知错误"
            throw DirectoryError.serverError(code: code, message: message)
        }
        
        guard let data = dict["data"] else {
             // 如果 data 为空，返回空的分页结果
             return PageResult(
                currentPage: pageNum,
                pageSize: pageSize,
                totalCount: 0,
                totalPage: 0,
                recordList: []
             )
        }
        
        // 解析 PageResult
        let jsonDataResponse: Data
        if let dataDict = data as? [String: Any] {
            print("📦 收到分页数据 (Keys): \(dataDict.keys)")
            if let list = dataDict["recordList"] as? [Any] {
                 print("   recordList count: \(list.count)")
            } else {
                 print("   recordList is MISSING or invalid type: \(type(of: dataDict["recordList"] ?? "nil"))")
            }
            jsonDataResponse = try JSONSerialization.data(withJSONObject: dataDict)
        } else {
             return PageResult(
                currentPage: pageNum,
                pageSize: pageSize,
                totalCount: 0,
                totalPage: 0,
                recordList: []
             )
        }
        
        do {
            let pageResult = try JSONDecoder().decode(PageResult<FileDto>.self, from: jsonDataResponse)
            print("✅ 文件列表加载成功，当前页 \(pageResult.currentPage)/\(pageResult.totalPage)，共 \(pageResult.totalCount) 条")
            
            return pageResult
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ JSON 解码缺少键: \(key.stringValue), 路径: \(context.codingPath.map { $0.stringValue })")
            throw DirectoryError.invalidResponse("缺少字段: \(key.stringValue)")
        } catch let DecodingError.valueNotFound(type, context) {
             print("❌ JSON 解码缺少值: \(type), 路径: \(context.codingPath.map { $0.stringValue })")
             throw DirectoryError.invalidResponse("缺少值: \(type)")
        } catch {
             print("❌ JSON 解码其它错误: \(error)")
             throw error
        }
    }

    // MARK: - File Detail (Merged)

    /// 获取文件详情 (0x42)
    /// - Parameter fileId: 文件ID
    /// - Returns: 文件详情对象
    /// - Throws: 网络或服务端错误
    func fetchFileDetail(fileId: Int64) async throws -> FileDto {
        print("🔍 请求文件详情: fileId=\(fileId)")
        
        // 构造请求字典
        let requestDict: [String: Any] = ["fileId": fileId]
        let jsonData = try JSONSerialization.data(withJSONObject: requestDict)
        
        // 构造请求帧 (0x42)
        let frame = Frame(
            type: .fileDetailReq,
            data: jsonData,
            flags: 0x00
        )
        
        // 发送并等待响应 (0x43)
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .fileResponse,
            timeout: 10.0
        )
        
        // 解析响应
        guard let dict = try? FrameParser.decodeAsDictionary(responseFrame) else {
            throw DirectoryError.invalidResponse("无法解析响应为字典")
        }
        
        if let code = dict["code"] as? Int, code != 200 {
            let message = dict["message"] as? String ?? "未知错误"
            throw DirectoryError.serverError(code: code, message: message)
        }
        
        guard let data = dict["data"] else {
             throw DirectoryError.invalidResponse("响应数据为空")
        }
        
        return try parseFileDto(data)
    }

    /// 辅助解析 FileDto
    private func parseFileDto(_ data: Any) throws -> FileDto {
        let jsonData: Data
        if let dataDict = data as? [String: Any] {
            jsonData = try JSONSerialization.data(withJSONObject: dataDict)
        } else {
             throw DirectoryError.invalidResponse("数据格式错误")
        }
        
        return try JSONDecoder().decode(FileDto.self, from: jsonData)
    }
    /// 删除文件 (0x41)
    /// - Parameter fileId: 文件ID
    /// - Throws: 网络或服务端错误
    func deleteFile(fileId: Int64) async throws {
        print("🗑️ 请求删除文件: fileId=\(fileId)")
        
        struct DeleteFileRequest: Codable {
            let fileId: Int64
        }
        
        let request = DeleteFileRequest(fileId: fileId)
        let jsonData = try JSONEncoder().encode(request)
        
        let frame = Frame(
            type: .fileDeleteReq,
            data: jsonData,
            flags: 0x00
        )
        
        // 发送帧并等待响应 (0x43 fileResponse)
        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .fileResponse,
            timeout: 10.0
        )
        
        // 解析通用响应
        guard let dict = try? FrameParser.decodeAsDictionary(responseFrame) else {
            throw DirectoryError.invalidResponse("无法解析删除响应")
        }
        
        if let code = dict["code"] as? Int, code != 200 {
            let message = dict["message"] as? String ?? "未知错误"
            throw DirectoryError.serverError(code: code, message: message)
        }
        
        print("✅ 文件删除成功")
        Task { await FileThumbnailService.shared.deleteFromCache(fileId: fileId) }
    }

    /// 重命名文件 (0x44)
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - newFileName: 新文件名（含扩展名）
    /// - Throws: 网络或服务端错误
    func renameFile(fileId: Int64, newFileName: String) async throws {
        print("✏️ 请求重命名文件: fileId=\(fileId), newFileName=\(newFileName)")

        struct RenameFileRequest: Codable {
            let fileId: Int64
            let newFileName: String
        }

        let request = RenameFileRequest(fileId: fileId, newFileName: newFileName)
        let jsonData = try JSONEncoder().encode(request)

        let frame = Frame(
            type: .fileRenameReq,
            data: jsonData,
            flags: 0x00
        )

        let responseFrame = try await socketManager.sendFrameAndWait(
            frame,
            expecting: .fileResponse,
            timeout: 10.0
        )

        guard let dict = try? FrameParser.decodeAsDictionary(responseFrame) else {
            throw DirectoryError.invalidResponse("无法解析重命名响应")
        }

        // 兼容 success(bool) 和 code(int) 两种响应格式
        if let success = dict["success"] as? Bool {
            if !success {
                let message = dict["message"] as? String ?? "未知错误"
                throw DirectoryError.serverError(code: 500, message: message)
            }
        } else if let code = dict["code"] as? Int, code != 200 {
            let message = dict["message"] as? String ?? "未知错误"
            throw DirectoryError.serverError(code: code, message: message)
        }

        print("✅ 文件重命名成功")
    }

    /// 解析目录响应帧
    /// - Parameter frame: 响应帧
    /// - Returns: 目录项数组
    /// - Throws: 解析错误
    nonisolated static func debugParseDirectoryResponse(_ frame: Frame) throws -> [DirectoryItem] {
        try parseDirectoryResponse(frame)
    }

    private nonisolated static func parseDirectoryResponse(_ frame: Frame) throws -> [DirectoryItem] {
        // 解析为字典
        guard let dict = try? FrameParser.decodeAsDictionary(frame) else {
            throw DirectoryError.invalidResponse("无法解析响应为字典")
        }
        
        // 1. 只有服务端明确声明成功时才继续解析，避免认证错误被误判为空目录。
        var hasExplicitSuccess = false
        if let success = dict["success"] as? Bool {
            if !success {
                let message = dict["message"] as? String ?? "未知错误"
                let errorCode = dict["errorCode"] as? String
                let code = errorCode == "NOT_LOGGED_IN" ? 401 : 500
                throw DirectoryError.serverError(code: code, message: message)
            }
            hasExplicitSuccess = true
        } else if let code = dict["code"] as? Int {
            if code != 200 {
                let message = dict["message"] as? String ?? "未知错误"
                throw DirectoryError.serverError(code: code, message: message)
            }
            hasExplicitSuccess = true
        } else if let status = dict["status"] as? String,
                  status.caseInsensitiveCompare("success") == .orderedSame {
            hasExplicitSuccess = true
        }

        guard hasExplicitSuccess else {
            let errorCode = dict["errorCode"] as? String
            let message = dict["message"] as? String ?? "服务端未返回明确的成功状态"
            let code = errorCode == "NOT_LOGGED_IN" ? 401 : 500
            throw DirectoryError.serverError(code: code, message: message)
        }
        
        // 2. 获取 data 字段 (可能为 nil)
        guard let data = dict["data"] else {
            // 创建、重命名和删除成功时允许服务端不返回 data。
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
            throw DirectoryError.invalidResponse("data 字段格式无效: \(type(of: data))")
        }
        
        // 4. 解析为 FileDto
        let decoder = JSONDecoder()
        
        do {
            // 尝试解析为 FileDto 数组
            if data is [[String: Any]] {
                let fileDtos = try decoder.decode([FileDto].self, from: jsonData)
                print("✅ 成功解析为 FileDto 数组，共 \(fileDtos.count) 项")
                return fileDtos.map { $0.toDirectoryItem() }
            }
            // 尝试解析为单个 FileDto
            else if data is [String: Any] {
                 let fileDto = try decoder.decode(FileDto.self, from: jsonData)
                 print("✅ 成功解析为单个 FileDto: \(fileDto.fileName)")
                 return [fileDto.toDirectoryItem()]
            }
        } catch {
            print("❌ FileDto 解析失败: \(error)")
            throw DirectoryError.invalidResponse("无法将 data 解析为目录数据: \(error.localizedDescription)")
        }

        throw DirectoryError.invalidResponse("data 字段不是目录对象或数组")
    }
    
    /// 恢复挂起的任务 (应用启动调用)
    func resumePendingTasks() {
        let entities = PersistenceManager.shared.fetchPendingTasks()
        print("🔄 正在恢复未完成的任务... (Total entities: \(entities.count))")
        var count = 0
        
        for entity in entities {
            // 🔹 跳过已完成的任务 (已完成的任务不应该恢复到传输列表)
            if let status = entity.status, status == "已完成" {
                print("⏭️ 跳过已完成任务: \(entity.fileName ?? "Unknown")")
                continue
            }
            
            // Debug info
            let debugName = entity.fileName ?? "Unknown"
            let debugId = entity.taskId ?? "No ID"
            
            guard let taskIdStr = entity.taskId,
                  let uuid = UUID(uuidString: taskIdStr) else {
                print("⚠️ 跳过恢复 [\(debugName)]: 无效的 UUID string: \(debugId)")
                continue
            }
            
            guard let bookmark = entity.fileUrl else {
                print("⚠️ 跳过恢复 [\(debugName)]: 缺少文件 Bookmark (Security Scope Data)")
                continue
            }
            
            guard let fileName = entity.fileName else {
                print("⚠️ 跳过恢复 [\(debugId)]: 缺少文件名")
                continue
            }
            
            // 解析 Bookmark
            guard let url = PersistenceManager.shared.resolveBookmark(data: bookmark) else {
                print("❌ 无法解析文件 Bookmark [\(fileName)]:这可能是因为文件被移动或权限已失效")
                continue
            }
            
            // 重新计算进度，确保数据一致性
            var progress = entity.progress
            if entity.fileSize > 0 {
                let calculatedParams = Double(entity.uploadedBytes) / Double(entity.fileSize)
                // 如果数据库存的 progress 为 0 但有上传字节，或者偏差较大，优先使用计算值
                if progress == 0 || abs(progress - calculatedParams) > 0.01 {
                    progress = calculatedParams
                }
            }
            
            print("🔄 恢复任务 [\(fileName)]: Progress DB=\(entity.progress), Bytes=\(entity.uploadedBytes)/\(entity.fileSize) -> Final=\(progress)")
            
            
            // Determine Task Type based on MD5 prefix (Trick used in FileDownloadService)
            var taskType: TransferTaskType = .upload
            var remoteFileId: Int64 = 0
            
            if let md5 = entity.md5, md5.hasPrefix("DOWNLOAD_FILE_ID_") {
                taskType = .download
                let prefix = "DOWNLOAD_FILE_ID_"
                if let idSnippet = md5.split(separator: "_").last, let id = Int64(idSnippet) {
                   remoteFileId = id
                }
                
                // 🔹 下载任务特殊处理: 验证本地文件并重新计算实际进度
                let actualProgress = calculateActualProgress(fileUrl: url, totalSize: entity.fileSize)
                if actualProgress != progress {
                    print("📥 [恢复] 下载任务进度校正: DB=\(progress) -> 实际=\(actualProgress)")
                    progress = actualProgress
                }
            }

            let task = StorageTransferTask(
                id: uuid,
                taskType: taskType,
                name: fileName,
                fileUrl: url,
                targetDirId: entity.targetDirId,
                userId: Int64(entity.userId),
                userName: entity.userName ?? "",
                fileSize: entity.fileSize,
                directoryName: "/", // 暂时无法获取目录名，或者需要存库
                remoteFileId: remoteFileId,
                progress: progress
            )
            
            // 调用 Manager 恢复


            // 使用 MainActor 确保 UI 更新
            Task { @MainActor in
                let originalStatus = entity.status ?? "Paused"
                print("📋 [恢复] 任务: \(fileName), 原始状态: \(originalStatus), 进度: \(String(format: "%.1f%%", progress * 100))")
                
                TransferTaskManager.shared.restore(
                    task: task,
                    status: originalStatus,
                    progress: progress
                )
            }
            count += 1
        }
        print("✅ 已恢复 \(count) 个挂起任务")
    }
    
    /// 计算下载任务的实际进度 (基于本地文件大小)
    /// - Parameters:
    ///   - fileUrl: 本地文件路径
    ///   - totalSize: 文件总大小
    /// - Returns: 实际进度 (0.0 - 1.0)
    private func calculateActualProgress(fileUrl: URL, totalSize: Int64) -> Double {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileUrl.path) else {
            return 0.0
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileUrl.path)
            let currentSize = attributes[.size] as? Int64 ?? 0
            return totalSize > 0 ? Double(currentSize) / Double(totalSize) : 0.0
        } catch {
            print("❌ [恢复] 读取本地文件大小失败: \(error)")
            return 0.0
        }
    }
}

// MARK: - Local Data Models

struct FileListRequest: Codable {
    let dirId: Int64
    let fileName: String
    let pageNum: Int
    let pageSize: Int
}

struct PageResult<T: Codable>: Codable {
    let currentPage: Int
    let pageSize: Int
    let totalCount: Int64
    let totalPage: Int64
    let recordList: [T]
    
    enum CodingKeys: String, CodingKey {
        case currentPage, pageNum
        case pageSize
        case totalCount, total
        case totalPage, pages, totalPages
        case recordList, list, records, data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.currentPage = try container.decodeIfPresent(Int.self, forKey: .currentPage)
                        ?? container.decodeIfPresent(Int.self, forKey: .pageNum)
                        ?? 1
        
        self.pageSize = try container.decodeIfPresent(Int.self, forKey: .pageSize) ?? 10
        
        self.totalCount = try container.decodeIfPresent(Int64.self, forKey: .totalCount)
                       ?? container.decodeIfPresent(Int64.self, forKey: .total)
                       ?? 0
        
        self.totalPage = try container.decodeIfPresent(Int64.self, forKey: .totalPage)
                      ?? container.decodeIfPresent(Int64.self, forKey: .pages)
                      ?? container.decodeIfPresent(Int64.self, forKey: .totalPages)
                      ?? 0
        
        self.recordList = try container.decodeIfPresent([T].self, forKey: .recordList)
                       ?? container.decodeIfPresent([T].self, forKey: .list)
                       ?? container.decodeIfPresent([T].self, forKey: .records)
                       ?? container.decodeIfPresent([T].self, forKey: .data)
                       ?? []
    }
    
    init(currentPage: Int, pageSize: Int, totalCount: Int64, totalPage: Int64, recordList: [T]) {
        self.currentPage = currentPage
        self.pageSize = pageSize
        self.totalCount = totalCount
        self.totalPage = totalPage
        self.recordList = recordList
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currentPage, forKey: .currentPage)
        try container.encode(pageSize, forKey: .pageSize)
        try container.encode(totalCount, forKey: .totalCount)
        try container.encode(totalPage, forKey: .totalPage)
        try container.encode(recordList, forKey: .recordList)
    }
}

/// 目录错误
enum DirectoryError: LocalizedError {
    case invalidResponse(String)
    case serverError(code: Int, message: String)
    case invalidData // New case
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail):
            return "响应数据无效: \(detail)"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        case .invalidData:
            return "无效的数据"
        }
    }
}


// MARK: - FileTransferService (Merged)
// Moved here because the original file was not included in the Xcode project target.

/// 文件传输服务 (上传/下载)
class FileTransferService: ObservableObject {
    private struct FileHashCacheEntry: Codable {
        let md5: String
        let fileSize: Int64
        let modifiedAt: TimeInterval
    }
    
    // MARK: - Private Properties
    
    private let socketManager: SocketManager
    private static let md5ChunkSize = 4 * 1024 * 1024 // 4MB
    private static let hashCacheLock = NSLock()
    private static var hashCacheLoaded = false
    private static var hashCache: [String: FileHashCacheEntry] = [:]
    private static var hashComputationTasks: [String: Task<String, Error>] = [:]
    
    // MARK: - Initializer
    
    init(socketManager: SocketManager) {
        self.socketManager = socketManager
    }

    static func debugShouldRequestUploadAck(
        nextOffset: Int64,
        fileSize: Int64,
        lastAckOffset: Int64,
        ackWindowBytes: Int = 4 * 1024 * 1024
    ) -> Bool {
        shouldRequestUploadAck(
            nextOffset: nextOffset,
            fileSize: fileSize,
            lastAckOffset: lastAckOffset,
            ackWindowBytes: ackWindowBytes
        )
    }

    static func debugBuildUploadDataPayload(offset: Int64, data: Data) -> Data {
        buildUploadDataPayload(offset: offset, data: data)
    }

    static func debugUploadFinalizeTimeout(fileSize: Int64) -> TimeInterval {
        uploadFinalizeTimeout(fileSize: fileSize)
    }

    static func debugValidateUploadAckOffset(uploadedSize: Int64, expectedOffset: Int64) throws {
        try validateUploadAckOffset(uploadedSize: uploadedSize, expectedOffset: expectedOffset)
    }

    static func debugValidateFinalUploadAck(_ ack: StandardAckResponse, expectedTaskId: String) throws -> Int64 {
        try validateFinalUploadAck(ack, expectedTaskId: expectedTaskId)
    }

    private static func uploadFinalizeTimeout(fileSize: Int64) -> TimeInterval {
        let estimatedHashSeconds = Double(max(0, fileSize)) / Double(20 * 1024 * 1024)
        return min(600, max(60, estimatedHashSeconds + 30))
    }

    private static func validateUploadAckOffset(uploadedSize: Int64, expectedOffset: Int64) throws {
        guard uploadedSize >= 0 else {
            throw FileTransferError.serverError("服务端返回负数上传进度: uploaded=\(uploadedSize)")
        }
        guard uploadedSize <= expectedOffset else {
            throw FileTransferError.serverError(
                "服务端上传进度超前: expected=\(expectedOffset), uploaded=\(uploadedSize)"
            )
        }
    }

    private static func validateFinalUploadAck(_ ack: StandardAckResponse, expectedTaskId: String) throws -> Int64 {
        guard ack.status == "success" else {
            throw FileTransferError.serverError(ack.message ?? "上传最终确认失败")
        }
        guard ack.taskId == expectedTaskId else {
            throw FileTransferError.serverError("服务端上传任务ID不匹配")
        }
        guard let fileId = ack.fileId, fileId > 0 else {
            throw FileTransferError.invalidFinalFileId
        }
        return fileId
    }

    private static func shouldRequestUploadAck(
        nextOffset: Int64,
        fileSize: Int64,
        lastAckOffset: Int64,
        ackWindowBytes: Int
    ) -> Bool {
        if nextOffset >= fileSize {
            return true
        }
        return nextOffset - lastAckOffset >= Int64(ackWindowBytes)
    }

    private static func buildUploadDataPayload(offset: Int64, data: Data) -> Data {
        var payload = Data()
        var offsetBigEndian = UInt64(offset).bigEndian
        payload.append(Data(bytes: &offsetBigEndian, count: MemoryLayout<UInt64>.size))
        payload.append(data)
        return payload
    }
    
    // MARK: - Upload Methods
    
    /// 上传文件 (支持断点续传)
    /// - Parameters:
    ///   - fileUrl: 本地文件路径
    ///   - targetDirId: 目标目录 ID
    ///   - userId: 用户 ID
    ///   - progressHandler: 进度回调 (0.0 - 1.0)
    @discardableResult
    func uploadFile(
        fileUrl: URL,
        targetDirId: Int64,
        userId: Int32,
        userName: String,
        taskId: String,
        uploadPurpose: String = "CLOUD_FILE",
        connectionReuse: Bool = false,
        batchId: String? = nil,
        startOffset: Int64 = 0,
        persistTransferTask: Bool = true,
        progressHandler: ((Double, String) -> Void)? = nil,
        statusHandler: ((String) -> Void)? = nil
    ) async throws -> Int64? {
        print("🚀 开始上传文件: \(fileUrl.lastPathComponent) (TaskID: \(taskId))")
        
        // 1. 准备文件信息
        // 开启安全访问 (针对 Bookmark 恢复的 URL)
        let isSecurityScoped = fileUrl.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { fileUrl.stopAccessingSecurityScopedResource() } }

        // [缩略图] 在上传 scope 有效期内独立启动缩略图生成。
        // Task.detached 立即执行自己的 startAccessingSecurityScopedResource，
        // 确保自身 scope 在上传 scope 生命期内已建立，之后两者互不阻塞、各自管理生命周期。
        let _thumbnailTaskId = taskId
        let _thumbnailFileUrl = fileUrl
        Task.detached(priority: .background) {
            let isScoped = _thumbnailFileUrl.startAccessingSecurityScopedResource()
            defer { if isScoped { _thumbnailFileUrl.stopAccessingSecurityScopedResource() } }
            await FileThumbnailService.shared.buildFromLocal(
                taskId: _thumbnailTaskId,
                fileUrl: _thumbnailFileUrl,
                fileName: _thumbnailFileUrl.lastPathComponent
            )
        }

        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            throw FileTransferError.fileNotFound
        }
        
        let fileSize = try fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize.map { Int64($0) } ?? 0
        let fileName = fileUrl.lastPathComponent
        let fileType = fileUrl.pathExtension
        guard let transferToken = AuthenticationService.shared.currentUser?.transferToken,
              !transferToken.isEmpty else {
            throw FileTransferError.serverError("文件传输凭证无效，请重新登录")
        }
        
        // --- Persistence Integration Start ---
        // 初始化/更新本地数据库任务
        if persistTransferTask {
            PersistenceManager.shared.saveTask(
                taskId: taskId,
                fileUrl: fileUrl,
                fileName: fileName,
                fileSize: fileSize,
                targetDirId: targetDirId,
                userId: userId,
                userName: userName,
                status: "Waiting",
                progress: 0.0,
                uploadedBytes: startOffset, // [修改] 保留已上传字节数，断点续传时不归零
                md5: nil // MD5 计算后再更新
            )
        }
        // --- Persistence Integration End ---
        
        // 2. 计算 MD5
        if persistTransferTask {
            PersistenceManager.shared.updateStatus(taskId: taskId, status: "Hashing")
        }
        print("⏳ 正在计算 MD5...")
        let md5 = try await resolveOrComputeMD5(for: fileUrl, fileSize: fileSize)
        print("✅ MD5 计算完成: \(md5)")
        
        // --- Persistence Update MD5 ---
        if persistTransferTask {
            PersistenceManager.shared.saveTask(taskId: taskId, md5: md5)
        }
        // --- Persistence Update End ---
        
        // 3. 构建元数据请求体
        // 3. 构建元数据请求体
        let metaRequest = FileMetaRequest(
            md5: md5,
            fileName: fileName,
            fileSize: fileSize,
            fileType: fileType,
            dirId: targetDirId,
            userId: userId,
            userName: userName,
            taskId: taskId,
            transferToken: transferToken,
            uploadPurpose: uploadPurpose,
            connectionReuse: connectionReuse,
            batchId: batchId
        )
        
        // 4. 发送断点检查帧 (0x05)
        print("🔍 发送断点检查请求...")
        if uploadPurpose == "CHAT_ATTACHMENT" {
            statusHandler?("断点检查")
        }
        
        // 构建字典类型的请求体，确保 userId 是数字，且可以在此处去掉 taskId 如果服务端不需要
        // 发送上传请求元数据（包含startOffset用于断点续传）
        var uploadRequest: [String: Any] = [
            "fileSize": fileSize,
            "dirId": targetDirId,
            "fileName": fileName,
            "userId": userId,
            "userName": userName,
            "taskId": taskId,
            "md5": md5,
            "startOffset": startOffset,
            "transferToken": transferToken,
            "uploadPurpose": uploadPurpose,
            "connectionReuse": connectionReuse
        ]
        if let batchId, !batchId.isEmpty {
            uploadRequest["batchId"] = batchId
        }
        
        // --- DEBUG LOG START ---
        if let jsonData = try? JSONSerialization.data(withJSONObject: uploadRequest), let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 [DEBUG] Meta Request JSON (Dict): \(jsonString)")
            
            // 使用字典构建 Frame
            let checkFrame = Frame(type: .resumeCheck, data: jsonData, flags: 0x00)

            var offset: Int64 = 0
            // 标记是否需要走全新上传路径
            var needFreshUpload = false

            let checkResponseFrame = try await socketManager.sendFrameAndWait(
                checkFrame,
                expecting: .resumeAck,
                timeout: 30.0,
                matching: { Self.frame($0, matchesTaskId: taskId) }
            )
            let resumeInfo = try FrameParser.decodePayload(checkResponseFrame, as: ResumeAckResponse.self)

            if resumeInfo.status == "resume" {
                // === 断点续传 ===
                guard resumeInfo.taskId == taskId else {
                    throw FileTransferError.serverError("服务端返回的上传任务ID不匹配")
                }
                offset = resumeInfo.uploadedSize ?? 0
                guard offset >= 0, offset <= fileSize else {
                    throw FileTransferError.serverError("服务端返回的上传断点非法: \(offset)")
                }
                print("🔄 发现断点记录，TaskId: \(taskId), 已上传: \(offset) 字节，继续上传...")

            } else if resumeInfo.status == "new" {
                needFreshUpload = true
            } else if resumeInfo.status == "complete" {
                guard let fileId = resumeInfo.fileId, fileId > 0 else {
                    throw FileTransferError.invalidFinalFileId
                }
                if persistTransferTask {
                    PersistenceManager.shared.updateStatus(taskId: taskId, status: "Completed")
                }
                progressHandler?(1.0, "完成")
                return fileId
            } else {
                throw FileTransferError.serverError(resumeInfo.message ?? "未知状态")
            }

            if needFreshUpload {
                // === 全新上传 ===
                print("🆕 无断点记录，开始全新上传...")
                if uploadPurpose == "CHAT_ATTACHMENT" {
                    statusHandler?("元数据握手")
                }
                let metaFrame = try FrameBuilder.build(type: .metaFrame, payload: metaRequest)
                let metaResponseFrame = try await socketManager.sendFrameAndWait(
                    metaFrame,
                    expecting: .ackFrame,
                    timeout: 30.0,
                    matching: { Self.frame($0, matchesTaskId: taskId) }
                )
                let ack = try FrameParser.decodePayload(metaResponseFrame, as: StandardAckResponse.self)
                guard ack.status == "ready" else {
                    throw FileTransferError.serverError(ack.message ?? "服务端未就绪")
                }
                guard ack.taskId == taskId else {
                    throw FileTransferError.serverError("服务端上传任务ID不匹配")
                }
                offset = ack.uploadedSize ?? 0
                guard offset >= 0, offset <= fileSize else {
                    throw FileTransferError.serverError("服务端返回的初始上传位置非法")
                }
                print("✅ 元数据握手成功，TaskId: \(taskId), offset: \(offset)")
            }
            
            
            // --- Persistence Update Status ---
            // 关键修复: 使用原始 taskId 更新数据库，确保记录匹配
            if persistTransferTask {
                PersistenceManager.shared.updateStatus(taskId: taskId, status: "Uploading")
            }
            statusHandler?(uploadPurpose == "CHAT_ATTACHMENT" ? "数据发送" : "上传中")
            // --- Persistence Update End ---
            
            // 5. 发送文件数据 (0x02)
            if offset < fileSize {
                // 发送文件数据（从startOffset开始）
                let finalOffset = try await sendFileData(
                    fileUrl: fileUrl,
                    offset: offset,
                    taskId: taskId, // [修改] 用本地 taskId 确保进度存入正确 DB 记录
                    fileSize: fileSize,
                    initialChunkSize: resumeInfo.initialChunkSize,
                    initialAckWindowBytes: resumeInfo.initialAckWindow,
                    persistTransferTask: persistTransferTask,
                    reportsDetailedStages: uploadPurpose == "CHAT_ATTACHMENT",
                    progressHandler: progressHandler,
                    statusHandler: statusHandler
                )
                guard finalOffset == fileSize else {
                    throw FileTransferError.localReadIncomplete(expected: fileSize, actual: finalOffset)
                }
            } else {
                print("✅ 文件已完整，跳过数据发送")
                progressHandler?(1.0, "0 KB/s")
            }
            
            // 6. 发送结束帧 (0x03)
            print("🏁 发送结束帧...")
            statusHandler?(uploadPurpose == "CHAT_ATTACHMENT" ? "完整性校验与最终确认" : "校验中")
            let endRequest = EndUploadRequest(taskId: taskId)
            let endFrame = try FrameBuilder.build(type: .endFrame, payload: endRequest)
            let endResponseFrame = try await socketManager.sendFrameAndWait(
                endFrame,
                expecting: .ackFrame,
                timeout: Self.uploadFinalizeTimeout(fileSize: fileSize),
                matching: { Self.frame($0, matchesTaskId: taskId) }
            )
            let finalAck = try FrameParser.decodePayload(endResponseFrame, as: StandardAckResponse.self)
            let finalFileId = try Self.validateFinalUploadAck(finalAck, expectedTaskId: taskId)
            print("🎉 文件上传成功!")

            // --- Persistence Complete ---
            // 任务完成，可以选择删除或标记为完成。 根据需求保留记录。
            if persistTransferTask {
                PersistenceManager.shared.updateStatus(taskId: taskId, status: "Completed")
            }
            // PersistenceManager.shared.deleteTask(taskId: taskId) // 暂时保留
            // --- Persistence End ---

            return finalFileId

        } else {
             throw FileTransferError.invalidResponse // Replace with appropriate error if serialization fails
        }
    }
    
    /// 发送文件数据分块
    private func sendFileData(
        fileUrl: URL,
        offset: Int64,
        taskId: String,
        fileSize: Int64,
        initialChunkSize: Int?,
        initialAckWindowBytes: Int?,
        persistTransferTask: Bool,
        reportsDetailedStages: Bool,
        progressHandler: ((Double, String) -> Void)?,
        statusHandler: ((String) -> Void)?
    ) async throws -> Int64 {
        let fileHandle = try FileHandle(forReadingFrom: fileUrl)
        defer { try? fileHandle.close() }
        
        // 定位到断点位置
        if offset > 0 {
            try fileHandle.seek(toOffset: UInt64(offset))
        }
        
        var currentOffset = offset
        var lastAckOffset = offset
        var lastLogTime = Date()
        var lastOffsetForSpeed = offset // 用于计算速率的上一周期 offset
        var rewindAttempts = 0
        let maxRewindAttempts = 12
        var adaptiveController = AdaptiveUploadController(
            initialChunkSize: initialChunkSize,
            initialAckWindowBytes: initialAckWindowBytes
        )
        var adaptiveDecision = adaptiveController.currentDecision
        var ackWindowStartedAt = Date()
        var socketWriteWaitDuration: TimeInterval = 0
        
        // 循环读取并发送
        // 注意：这里是一个简单的循环，实际生产中可能需要流控，
        // 但根据 Java 代码逻辑，它是直接循环发送的，依赖 TCP 自身的流控。
        while currentOffset < fileSize {
            // 检查任务是否被取消
            try Task.checkCancellation()
            
            // 检查 Socket 是否连接
            guard socketManager.connectionState == .connected else {
                throw FileTransferError.connectionLost
            }
            
            let remainingBytes = fileSize - currentOffset
            let readLength = min(adaptiveDecision.chunkSize, Int(remainingBytes))
            let data = fileHandle.readData(ofLength: readLength)
            if data.isEmpty { break } // 文件读取完毕
            let nextOffset = currentOffset + Int64(data.count)
            let dataFrameNeedsAck = Self.shouldRequestUploadAck(
                nextOffset: nextOffset,
                fileSize: fileSize,
                lastAckOffset: lastAckOffset,
                ackWindowBytes: adaptiveDecision.ackWindowBytes
            )
            
            // 发送数据帧 (不等待响应)
            // 注意：Data Frame 的 payload 直接是 raw bytes，不是 JSON
            let payload = Self.buildUploadDataPayload(offset: currentOffset, data: data)
            var flags = Frame.FLAG_HAS_OFFSET
            if dataFrameNeedsAck {
                flags |= Frame.FLAG_NEED_ACK
            }
            let dataFrame = Frame(
                type: .dataFrame,
                data: payload,
                flags: flags
            )
            if dataFrameNeedsAck {
                if reportsDetailedStages {
                    statusHandler?("进度确认")
                }
                let ackResult = try await waitForUploadProgressAck(
                    dataFrame: dataFrame,
                    taskId: taskId,
                    expectedOffset: nextOffset,
                    timeout: adaptiveDecision.ackTimeout
                )
                let confirmedOffset = ackResult.ack.uploadedSize ?? 0
                let windowDuration = max(Date().timeIntervalSince(ackWindowStartedAt), 0.001)
                let confirmedWindowBytes = max(0, confirmedOffset - lastAckOffset)
                let serverState = Self.adaptiveServerState(ackResult.ack.serverState)
                adaptiveDecision = adaptiveController.record(
                    AdaptiveUploadController.Observation(
                        ackRTT: ackResult.rtt,
                        windowBytes: Int(min(Int64(Int.max), confirmedWindowBytes)),
                        windowDuration: windowDuration,
                        serverState: serverState,
                        recommendedChunkSize: ackResult.ack.recommendedChunkSize,
                        recommendedAckWindowBytes: ackResult.ack.recommendedAckWindow,
                        retryAfterMs: ackResult.ack.retryAfterMs,
                        isOffsetBehind: confirmedOffset < nextOffset,
                        socketWriteWaitRatio: min(1, max(0, socketWriteWaitDuration / windowDuration)),
                        didTimeout: false,
                        didDisconnect: false
                    )
                )
                if serverState == .error {
                    throw FileTransferError.serverError(ackResult.ack.message ?? "服务端停止接收上传数据")
                }
                if confirmedOffset < nextOffset {
                    rewindAttempts += 1
                    guard rewindAttempts <= maxRewindAttempts else {
                        throw FileTransferError.serverError("服务端上传进度多次落后，已停止重传: offset=\(confirmedOffset)")
                    }
                    print("↩️ 服务端上传进度落后，回退重传: expected=\(nextOffset), confirmed=\(confirmedOffset)")
                    try fileHandle.seek(toOffset: UInt64(confirmedOffset))
                    currentOffset = confirmedOffset
                    lastAckOffset = confirmedOffset
                    lastOffsetForSpeed = confirmedOffset
                    ackWindowStartedAt = Date()
                    socketWriteWaitDuration = 0
                    await Task.yield()
                    continue
                }
                rewindAttempts = 0
                lastAckOffset = confirmedOffset
                if reportsDetailedStages {
                    statusHandler?("数据发送")
                }
                if adaptiveDecision.shouldPause {
                    statusHandler?("等待服务端")
                    let retryAfterMs = min(60_000, max(1, adaptiveDecision.retryAfterMs ?? 250))
                    try await Task.sleep(nanoseconds: UInt64(retryAfterMs) * 1_000_000)
                    statusHandler?("上传中")
                }
                ackWindowStartedAt = Date()
                socketWriteWaitDuration = 0
            } else {
                let writeStartedAt = Date()
                try await socketManager.sendFrameAsync(dataFrame)
                socketWriteWaitDuration += Date().timeIntervalSince(writeStartedAt)
            }
            
            // 每次发送后主动交出控制权，确保 RunLoop 能处理 socket 输入事件（如 ACK）和 UI 更新
            // 虽然 waitForWritable 已经提供了挂起机会，但在全速发送时仍需保证 responsiveness
            await Task.yield()
            
            currentOffset = nextOffset
            
            // 更新进度 (每 0.5 秒回调一次，避免 UI 刷新过频)
            let now = Date()
            let timeDelta = now.timeIntervalSince(lastLogTime)
            
            if timeDelta >= 0.5 || currentOffset == fileSize {
                // 计算本周期内的增量
                let bytesSinceLastLog = currentOffset - lastOffsetForSpeed
                
                // 计算速率 (Bytes/s)
                let speedBytesPerSec = Double(bytesSinceLastLog) / timeDelta
                let speedStr = formatSpeed(speedBytesPerSec)
                
                let progress = Double(currentOffset) / Double(fileSize)
                progressHandler?(progress, speedStr)
                
                // --- Persistence Update Progress ---
                if persistTransferTask {
                    PersistenceManager.shared.updateProgress(
                        taskId: taskId,
                        progress: progress,
                        uploadedBytes: currentOffset
                    )
                }
                // --- Persistence End ---
                
                lastLogTime = now
                lastOffsetForSpeed = currentOffset
            }
        }

        guard currentOffset == fileSize else {
            throw FileTransferError.localReadIncomplete(expected: fileSize, actual: currentOffset)
        }
        return currentOffset
    }

    private struct UploadProgressAckResult {
        let ack: StandardAckResponse
        let rtt: TimeInterval
    }

    private func waitForUploadProgressAck(
        dataFrame: Frame,
        taskId: String,
        expectedOffset: Int64,
        timeout: TimeInterval
    ) async throws -> UploadProgressAckResult {
        let startedAt = Date()
        let ackFrame = try await socketManager.sendFrameAndWait(
            dataFrame,
            expecting: .ackFrame,
            timeout: timeout,
            matching: { Self.frame($0, matchesTaskId: taskId) }
        )
        let ack = try FrameParser.decodePayload(ackFrame, as: StandardAckResponse.self)
        guard ack.status == "progress" else {
            throw FileTransferError.serverError(ack.message ?? "服务端上传进度确认异常")
        }
        guard let uploadedSize = ack.uploadedSize else {
            throw FileTransferError.serverError("服务端未返回上传进度确认")
        }
        try Self.validateUploadAckOffset(uploadedSize: uploadedSize, expectedOffset: expectedOffset)
        return UploadProgressAckResult(ack: ack, rtt: Date().timeIntervalSince(startedAt))
    }

    private static func adaptiveServerState(_ rawValue: String?) -> AdaptiveUploadController.ServerState {
        switch rawValue ?? "normal" {
        case "normal":
            return .normal
        case "slow_down":
            return .slowDown
        case "pause":
            return .pause
        default:
            return .error
        }
    }

    private static func frame(_ frame: Frame, matchesTaskId taskId: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: frame.data) as? [String: Any] else {
            return false
        }
        if let responseTaskId = object["taskId"] as? String {
            return responseTaskId == taskId
        }
        return object["status"] as? String == "error"
    }

    static func debugFrame(_ frame: Frame, matchesTaskId taskId: String) -> Bool {
        Self.frame(frame, matchesTaskId: taskId)
    }
    
    // 格式化速率字符串 helper
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        }
    }
    
    // MARK: - Helper Methods
    
    private func resolveOrComputeMD5(for url: URL, fileSize: Int64) async throws -> String {
        let fileURL = url.standardizedFileURL
        let cacheKey = fileURL.path
        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0

        if let hit = Self.withHashCacheLock({
            Self.loadHashCacheIfNeededLocked()
            if let cached = Self.hashCache[cacheKey],
               cached.fileSize == fileSize,
               abs(cached.modifiedAt - modifiedAt) < 0.0001 {
                return cached.md5
            }
            return nil
        }) {
            print("♻️ 命中本地 MD5 缓存: \(fileURL.lastPathComponent)")
            return hit
        }

        if let existingTask = Self.withHashCacheLock({ Self.hashComputationTasks[cacheKey] }) {
            return try await existingTask.value
        }

        let computeTask = Task.detached(priority: .utility) {
            try Self.computeContentMD5(for: fileURL)
        }
        Self.withHashCacheLock {
            Self.hashComputationTasks[cacheKey] = computeTask
        }

        do {
            let md5 = try await computeTask.value
            Self.withHashCacheLock {
                Self.hashComputationTasks.removeValue(forKey: cacheKey)
                Self.hashCache[cacheKey] = FileHashCacheEntry(
                    md5: md5,
                    fileSize: fileSize,
                    modifiedAt: modifiedAt
                )
                Self.persistHashCacheLocked()
            }
            return md5
        } catch {
            _ = Self.withHashCacheLock {
                Self.hashComputationTasks.removeValue(forKey: cacheKey)
            }
            throw error
        }
    }

    private static func hashCacheFileURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("chat-storage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("upload_md5_cache.json")
    }

    private static func loadHashCacheIfNeededLocked() {
        guard !hashCacheLoaded else { return }
        hashCacheLoaded = true
        let url = hashCacheFileURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: FileHashCacheEntry].self, from: data) else {
            hashCache = [:]
            return
        }
        hashCache = decoded
    }

    private static func persistHashCacheLocked() {
        let url = hashCacheFileURL()
        guard let data = try? JSONEncoder().encode(hashCache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 返回本地上传 MD5 缓存文件大小。该缓存只保存可重新计算的校验值。
    static func uploadMD5CacheSize() -> Int64 {
        withHashCacheLock {
            let url = hashCacheFileURL()
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize else { return 0 }
            return Int64(fileSize)
        }
    }

    /// 清除上传 MD5 缓存，不取消正在进行的哈希计算或文件传输。
    @discardableResult
    static func clearUploadMD5Cache() -> Int64 {
        withHashCacheLock {
            loadHashCacheIfNeededLocked()
            let url = hashCacheFileURL()
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            hashCache.removeAll()
            try? FileManager.default.removeItem(at: url)
            return Int64(bytes)
        }
    }

    private static func withHashCacheLock<T>(_ body: () -> T) -> T {
        hashCacheLock.lock()
        defer { hashCacheLock.unlock() }
        return body()
    }

    /// 计算文件内容 MD5（分块流式），避免一次性读取大文件导致内存飙升。
    private static func computeContentMD5(for url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        while true {
            let chunk = try fileHandle.read(upToCount: md5ChunkSize) ?? Data()
            if chunk.isEmpty { break }
            chunk.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                CC_MD5_Update(&context, baseAddress, CC_LONG(chunk.count))
            }
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Video Streaming
    
    /// 开始流式下载 (用于视频播放)
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - delegate: 代理
    @available(*, unavailable, message: "Use VideoStreamingService for isolated video streaming sockets.")
    nonisolated public func startVideoStreaming(fileId: Int64, delegate: VideoStreamLoaderDelegate) async throws {
        print("🎥 [Stream] 请求视频流: \(fileId)")
        guard let currentUser = AuthenticationService.shared.currentUser,
              let transferToken = currentUser.transferToken else {
            throw FileTransferError.serverError("文件传输凭证无效，请重新登录")
        }
        
        let fileIdInt = Int64(fileId)
        let taskId = UUID().uuidString
        
        // 1. 发送下载请求 (MetaFrame)
        // 注意：视频流通常需要全量请求或者Range请求，这里简单起见请求从0开始
        let request: [String: Any] = [
            "fileId": fileIdInt,
            "taskId": taskId,
            "startOffset": 0,
            "userId": currentUser.id,
            "userName": currentUser.username,
            "transferToken": transferToken
        ]
        
        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            throw DirectoryError.invalidData
        }
        
        let requestFrame = Frame(type: .metaFrame, data: requestData, flags: 0x00)
        try socketManager.sendFrame(requestFrame)
        
        // 2. 监听数据端
        return try await withCheckedThrowingContinuation { continuation in
            var receivedSize: Int64 = 0
            
            // 监听类型
            let types: Set<FrameTypeEnum> = [.metaFrame, .dataFrame, .endFrame, .fileResponse, .ackFrame]
            
            socketManager.registerStreamHandler(for: types) { frame in
                switch frame.type {
                case .ackFrame, .metaFrame:
                    if let jsonString = String(data: frame.data, encoding: .utf8),
                       let data = jsonString.data(using: String.Encoding.utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        // 检查错误
                        if let status = dict["status"] as? String, (status == "error" || status == "fail") {
                             let msg = dict["message"] as? String ?? "未知错误"
                             let err = DirectoryError.serverError(code: -1, message: msg)
                             delegate.didFail(with: err)
                             continuation.resume(throwing: err)
                             return false
                        }
                        
                        // 文件信息
                        if let size = dict["fileSize"] as? Int64 {
                            delegate.didReceiveContentInfo(totalSize: size, mimeType: "video/mp4")
                            
                            // 发送 Ready
                            let readyAck: [String: Any] = ["taskId": taskId, "status": "ready"]
                            if let readyData = try? JSONSerialization.data(withJSONObject: readyAck) {
                                let readyFrame = Frame(type: .ackFrame, data: readyData, flags: 0x00)
                                try? self.socketManager.sendFrame(readyFrame)
                            }
                        }
                    }
                    return true
                    
                case .dataFrame:
                    let data = frame.data
                    let range = receivedSize..<receivedSize + Int64(data.count)
                    delegate.didReceiveVideoData(data, range: range)
                    receivedSize += Int64(data.count)
                    return true
                    
                case .endFrame:
                    print("✅ [Stream] 视频流结束")
                    delegate.didFinishLoading()
                    continuation.resume()
                    return false
                    
                case .fileResponse:
                     if let dict = try? FrameParser.decodeAsDictionary(frame),
                        let code = dict["code"] as? Int, code != 200 {
                         let msg = dict["message"] as? String ?? "Stream Fail"
                         let error = DirectoryError.serverError(code: code, message: msg)
                         delegate.didFail(with: error)
                         continuation.resume(throwing: error)
                         return false
                     }
                     return true
                     
                default:
                    return true
                }
            }
        }
    }
    /// 开始定制流式下载 (用于支持断点续传的视频播放)
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - startOffset: 二进制开始偏移位置 (针对 Http Range 请求)
    ///   - delegate: 代理
    @available(*, unavailable, message: "Use VideoStreamingService for isolated range streaming sockets.")
    nonisolated public func startCustomVideoStreaming(fileId: Int64, startOffset: Int64, delegate: VideoStreamLoaderDelegate) async throws {
        print("🎥 [Stream] 请求视频流: fileId=\(fileId) range-start=\(startOffset)")
        guard let currentUser = AuthenticationService.shared.currentUser,
              let transferToken = currentUser.transferToken else {
            throw FileTransferError.serverError("文件传输凭证无效，请重新登录")
        }
        
        let fileIdInt = Int64(fileId)
        let taskId = UUID().uuidString
        
        // 1. 发送带 offset 的下载请求 (MetaFrame)
        let request: [String: Any] = [
            "fileId": fileIdInt,
            "taskId": taskId,
            "startOffset": startOffset,
            "userId": currentUser.id,
            "userName": currentUser.username,
            "transferToken": transferToken
        ]
        
        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            throw DirectoryError.invalidData
        }
        
        let requestFrame = Frame(type: .metaFrame, data: requestData, flags: 0x00)
        try socketManager.sendFrame(requestFrame)
        
        // 2. 监听数据端
        return try await withCheckedThrowingContinuation { continuation in
            var receivedSize: Int64 = startOffset
            
            // 监听类型
            let types: Set<FrameTypeEnum> = [.metaFrame, .dataFrame, .endFrame, .fileResponse, .ackFrame]
            
            socketManager.registerStreamHandler(for: types) { frame in
                switch frame.type {
                case .ackFrame, .metaFrame:
                    if let jsonString = String(data: frame.data, encoding: .utf8),
                       let data = jsonString.data(using: String.Encoding.utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        // 检查错误
                        if let status = dict["status"] as? String, (status == "error" || status == "fail") {
                             let msg = dict["message"] as? String ?? "未知错误"
                             let err = DirectoryError.serverError(code: -1, message: msg)
                             delegate.didFail(with: err)
                             continuation.resume(throwing: err)
                             return false
                        }
                        
                        // 文件信息
                        if let size = dict["fileSize"] as? Int64 {
                            delegate.didReceiveContentInfo(totalSize: size, mimeType: "video/mp4")
                            
                            // 发送 Ready 确认帧 开始接收后续的 DataFrame
                            let readyAck: [String: Any] = ["taskId": taskId, "status": "ready"]
                            if let readyData = try? JSONSerialization.data(withJSONObject: readyAck) {
                                let readyFrame = Frame(type: .ackFrame, data: readyData, flags: 0x00)
                                try? self.socketManager.sendFrame(readyFrame)
                            }
                        }
                    }
                    return true
                    
                case .dataFrame:
                    let data = frame.data
                    let range = receivedSize..<receivedSize + Int64(data.count)
                    delegate.didReceiveVideoData(data, range: range)
                    receivedSize += Int64(data.count)
                    return true
                    
                case .endFrame:
                    print("✅ [Stream] 视频流片段发送结束")
                    delegate.didFinishLoading()
                    continuation.resume()
                    return false
                    
                case .fileResponse:
                     if let dict = try? FrameParser.decodeAsDictionary(frame),
                        let code = dict["code"] as? Int, code != 200 {
                         let msg = dict["message"] as? String ?? "Stream Fail"
                         let error = DirectoryError.serverError(code: code, message: msg)
                         delegate.didFail(with: error)
                         continuation.resume(throwing: error)
                         return false
                     }
                     return true
                     
                default:
                    return true
                }
            }
        }
    }
}

// MARK: - Data Models (Request/Response)

struct FileMetaRequest: Codable {
    let md5: String
    let fileName: String
    let fileSize: Int64
    let fileType: String
    let dirId: Int64
    let userId: Int32
    let userName: String
    let taskId: String // 新增: 客户端传递的任务ID
    let transferToken: String
    let uploadPurpose: String
    let connectionReuse: Bool
    let batchId: String?
}

struct EndUploadRequest: Codable {
    let taskId: String
}

struct ResumeAckResponse: Codable {
    let status: String       // "resume", "new"
    let taskId: String?
    let uploadedSize: Int64?
    let message: String?
    let fileId: Int64?
    let initialChunkSize: Int?
    let minChunkSize: Int?
    let maxChunkSize: Int?
    let initialAckWindow: Int?
    let maxAckWindow: Int?
}

struct StandardAckResponse: Codable {
    let status: String       // "ready", "success"
    let taskId: String?
    let message: String?
    let fileId: Int64?
    let uploadedSize: Int64?
    let serverState: String?
    let recommendedChunkSize: Int?
    let recommendedAckWindow: Int?
    let serverWriteMillis: Int64?
    let retryAfterMs: Int?
}

// MARK: - Errors

enum FileTransferError: LocalizedError {
    case fileNotFound
    case connectionLost
    case serverError(String)
    case invalidResponse
    case invalidFinalFileId
    case localReadIncomplete(expected: Int64, actual: Int64)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "文件不存在"
        case .connectionLost: return "网络连接已断开"
        case .serverError(let msg): return "服务端错误: \(msg)"
        case .invalidResponse: return "无效的响应数据"
        case .invalidFinalFileId: return "服务端未返回有效的文件ID，正在重新确认上传结果"
        case .localReadIncomplete(let expected, let actual):
            return "本地文件读取不完整: expected=\(expected), actual=\(actual)"
        }
    }
}





// MARK: - DownloadDirectoryManager (Merged)
// Moved here because the original file was not included in the Xcode project target.

class DownloadDirectoryManager: ObservableObject {
    static let shared = DownloadDirectoryManager()
    
    @Published var currentDownloadPath: String = {
        let username = NSUserName()
        return "/Users/\(username)/Downloads"
    }()
    
    private let kBookmarkKey = "UserDownloadDirBookmark"
    private var securityScopedURL: URL?
    
    private init() {
        restoreBookmark()
    }
    
    /// 获取当前的下载目录 (如果是默认则返回系统Downloads，如果是自定义则返回自定义URL)
    func getDownloadDirectory() -> URL {
        if let url = securityScopedURL {
            return url
        }
        if let url = securityScopedURL {
            return url
        }
        let username = NSUserName()
        return URL(fileURLWithPath: "/Users/\(username)/Downloads")
    }
    
    /// 选择新的下载目录
    @MainActor
    func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择下载存储目录"
        
        if panel.runModal() == .OK, let url = panel.url {
            saveBookmark(for: url)
        }
    }

    @MainActor
    func resetToDefaultDirectory() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        UserDefaults.standard.removeObject(forKey: kBookmarkKey)
        currentDownloadPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? "/Users/\(NSUserName())/Downloads"
    }
    
    /// 开始访问安全资源 (在进行文件读写前调用)
    /// 返回 true 表示成功获取权限或不需要权限(默认目录)，false 表示失败
    func startAccess() -> Bool {
        // 如果是默认路径，不需要申请权限（前提是有 entitlements）
        // 实际上，只要 no securityScopedURL，就说明是默认路径。
        // 但为了保险，我们检查是否为 nil
        guard let url = securityScopedURL else { return true } 
        return url.startAccessingSecurityScopedResource()
    }
    
    /// 停止访问安全资源
    func stopAccess() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    // MARK: - Private Methods
    
    private func saveBookmark(for url: URL) {
        do {
            // 创建安全范围书签
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // 保存到 UserDefaults
            UserDefaults.standard.set(bookmarkData, forKey: kBookmarkKey)
            
            // 更新当前 URL
            self.securityScopedURL = url
            self.currentDownloadPath = url.path
            
            print("✅ [DownloadManager] 新下载目录已保存: \(url.path)")
            
        } catch {
            print("❌ [DownloadManager] 保存书签失败: \(error)")
        }
    }
    
    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: kBookmarkKey) else {
            return
        }
        
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("⚠️ [DownloadManager] 书签已过期，重置为默认")
                UserDefaults.standard.removeObject(forKey: kBookmarkKey)
                // 重置为默认路径
                let username = NSUserName()
                self.currentDownloadPath = "/Users/\(username)/Downloads"
                return
            }
            
            self.securityScopedURL = url
            self.currentDownloadPath = url.path
            print("✅ [DownloadManager] 恢复下载目录成功: \(url.path)")
            
        } catch {
            print("❌ [DownloadManager] 解析书签失败: \(error)")
        }
    }
}
