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
        
        do {
            // 尝试解析为 FileDto 数组
            if let dataArray = data as? [[String: Any]] {
                let fileDtos = try decoder.decode([FileDto].self, from: jsonData)
                print("✅ 成功解析为 FileDto 数组，共 \(fileDtos.count) 项")
                return fileDtos.map { $0.toDirectoryItem() }
            }
            // 尝试解析为单个 FileDto
            else if let dataDict = data as? [String: Any] {
                 let fileDto = try decoder.decode(FileDto.self, from: jsonData)
                 print("✅ 成功解析为单个 FileDto: \(fileDto.fileName)")
                 return [fileDto.toDirectoryItem()]
            }
        } catch {
            print("❌ FileDto 解析失败: \(error)")
        }
        
        print("⚠️ 无法将 data 解析为 FileDto 或 [FileDto] (Data Type: \(type(of: data)))")
        print("🔍 JSON Data String: \(String(data: jsonData, encoding: .utf8) ?? "nil")")
        return []
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
    
    // MARK: - Private Properties
    
    private let socketManager: SocketManager
    private let chunkSize: Int = 8 * 1024 // 8KB 分块
    
    // MARK: - Initializer
    
    init(socketManager: SocketManager) {
        self.socketManager = socketManager
    }
    
    // MARK: - Upload Methods
    
    /// 上传文件 (支持断点续传)
    /// - Parameters:
    ///   - fileUrl: 本地文件路径
    ///   - targetDirId: 目标目录 ID
    ///   - userId: 用户 ID
    ///   - progressHandler: 进度回调 (0.0 - 1.0)
    func uploadFile(
        fileUrl: URL,
        targetDirId: Int64,
        userId: Int32,
        userName: String,
        taskId: String,
        startOffset: Int64 = 0,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        print("🚀 开始上传文件: \(fileUrl.lastPathComponent) (TaskID: \(taskId))")
        
        // 1. 准备文件信息
        // 开启安全访问 (针对 Bookmark 恢复的 URL)
        let isSecurityScoped = fileUrl.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { fileUrl.stopAccessingSecurityScopedResource() } }
        
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            throw FileTransferError.fileNotFound
        }
        
        let fileSize = try fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize.map { Int64($0) } ?? 0
        let fileName = fileUrl.lastPathComponent
        let fileType = fileUrl.pathExtension
        
        // --- Persistence Integration Start ---
        // 初始化/更新本地数据库任务
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
            uploadedBytes: 0,
            md5: nil // MD5 计算后再更新
        )
        // --- Persistence Integration End ---
        
        // 2. 计算 MD5
        print("⏳ 正在计算 MD5...")
        let md5 = try calculateMD5(for: fileUrl)
        print("✅ MD5 计算完成: \(md5)")
        
        // --- Persistence Update MD5 ---
        PersistenceManager.shared.saveTask(taskId: taskId, md5: md5)
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
            taskId: taskId
        )
        
        // 4. 发送断点检查帧 (0x05)
        print("🔍 发送断点检查请求...")
        
        // 构建字典类型的请求体，确保 userId 是数字，且可以在此处去掉 taskId 如果服务端不需要
        // 发送上传请求元数据（包含startOffset用于断点续传）
        let uploadRequest: [String: Any] = [
            "fileSize": fileSize,
            "dirId": targetDirId,
            "fileName": fileName,
            "userId": userId,
            "userName": userName,
            "taskId": taskId,
            "md5": md5,
            "startOffset": startOffset
        ]
        
        // --- DEBUG LOG START ---
        if let jsonData = try? JSONSerialization.data(withJSONObject: uploadRequest), let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 [DEBUG] Meta Request JSON (Dict): \(jsonString)")
            
            // 使用字典构建 Frame
            let checkFrame = Frame(type: .resumeCheck, data: jsonData, flags: 0x00)
            let checkResponseFrame = try await socketManager.sendFrameAndWait(checkFrame, expecting: .resumeAck, timeout: 31536000.0)
            let resumeInfo = try FrameParser.decodePayload(checkResponseFrame, as: ResumeAckResponse.self)
            
            var offset: Int64 = 0
            // 本地变量用于跟踪最终使用的 TaskID (初始化为传入的 ID)
            var finalTaskId: String = taskId
            if resumeInfo.status == "resume" {
                // === 断点续传 ===
                let serverTaskId = resumeInfo.taskId ?? ""
                // 如果服务端返回了不为空的 ID 且与我们的不同，优先使用服务端的
                if !serverTaskId.isEmpty && serverTaskId != taskId {
                    print("⚠️ 服务端返回了不同的 TaskId: \(serverTaskId) vs \(taskId)。将优先使用服务端的。")
                    finalTaskId = serverTaskId
                }
                offset = resumeInfo.uploadedSize ?? 0
                print("🔄 发现断点记录，TaskId: \(finalTaskId), 已上传: \(offset) 字节，继续上传...")
                
            } else if resumeInfo.status == "new" {
                // === 全新上传 ===
                print("🆕 无断点记录，开始全新上传...")
                // 发送元数据帧 (0x01)，发送元数据全新上传帧
                let metaFrame = try FrameBuilder.build(type: .metaFrame, payload: metaRequest)
                let metaResponseFrame = try await socketManager.sendFrameAndWait(metaFrame, expecting: .ackFrame, timeout: 31536000.0)
                let ack = try FrameParser.decodePayload(metaResponseFrame, as: StandardAckResponse.self)
                guard ack.status == "ready" else {
                    throw FileTransferError.serverError(ack.message ?? "服务端未就绪")
                }
                if let newId = ack.taskId, !newId.isEmpty {
                    finalTaskId = newId
                }
                print("✅ 元数据握手成功，获取 TaskId: \(finalTaskId)")
                
            } else {
                throw FileTransferError.serverError(resumeInfo.message ?? "未知状态")
            }
            
            
            // --- Persistence Update Status ---
            // 关键修复: 使用原始 taskId 更新数据库，确保记录匹配
            PersistenceManager.shared.updateStatus(taskId: taskId, status: "Uploading")
            // --- Persistence Update End ---
            
            // 5. 发送文件数据 (0x02)
            if offset < fileSize {
                // 发送文件数据（从startOffset开始）
                try await sendFileData(
                    fileUrl: fileUrl,
                    offset: startOffset,
                    taskId: finalTaskId, // 使用 finalTaskId
                    fileSize: fileSize,
                    progressHandler: progressHandler
                )
            } else {
                print("✅ 文件已完整，跳过数据发送")
                progressHandler?(1.0, "0 KB/s")
            }
            
            // 6. 发送结束帧 (0x03)
            print("🏁 发送结束帧...")
            let endRequest = EndUploadRequest(taskId: finalTaskId) // 使用 finalTaskId
            let endFrame = try FrameBuilder.build(type: .endFrame, payload: endRequest)
            let endResponseFrame = try await socketManager.sendFrameAndWait(endFrame, expecting: .ackFrame, timeout: 31536000.0)
            let finalAck = try FrameParser.decodePayload(endResponseFrame, as: StandardAckResponse.self)
            if finalAck.status == "success" {
                print("🎉 文件上传成功!")
            } else {
                throw FileTransferError.serverError(finalAck.message ?? "上传最终确认失败")
            }
            
            // --- Persistence Complete ---
            // 任务完成，可以选择删除或标记为完成。 根据需求保留记录。
            PersistenceManager.shared.updateStatus(taskId: taskId, status: "Completed")
            // PersistenceManager.shared.deleteTask(taskId: taskId) // 暂时保留
            // --- Persistence End ---
            
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
        progressHandler: ((Double, String) -> Void)?
    ) async throws {
        let fileHandle = try FileHandle(forReadingFrom: fileUrl)
        defer { try? fileHandle.close() }
        
        // 定位到断点位置
        if offset > 0 {
            try fileHandle.seek(toOffset: UInt64(offset))
        }
        
        var currentOffset = offset
        var lastLogTime = Date()
        var lastOffsetForSpeed = offset // 用于计算速率的上一周期 offset
        
        // 循环读取并发送
        // 注意：这里是一个简单的循环，实际生产中可能需要流控，
        // 但根据 Java 代码逻辑，它是直接循环发送的，依赖 TCP 自身的流控。
        while true {
            // 检查任务是否被取消
            try Task.checkCancellation()
            
            // 检查 Socket 是否连接
            guard socketManager.connectionState == .connected else {
                throw FileTransferError.connectionLost
            }
            
            // --- 流控逻辑开始 ---
            // 检查发送缓冲区是否有空间，避免阻塞式写入导致的主线程卡死
            if let outputStream = socketManager.outputStream {
                if !outputStream.hasSpaceAvailable {
                    // 如果缓冲区已满，挂起等待直到可写 (基于事件驱动，不再使用 sleep)
                    // 同时释放 MainActor，让 UI 和其他事件（如心跳、ACK）能被处理
                    // await socketManager.waitForWritable()
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    
                    // 唤醒后再次检查，如果还是满的（极少情况），下次循环会再次等待
                    continue
                }
            }
            // --- 流控逻辑结束 ---
            
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty { break } // 文件读取完毕
            
            // 发送数据帧 (不等待响应)
            // 注意：Data Frame 的 payload 直接是 raw bytes，不是 JSON
            let dataFrame = Frame(type: .dataFrame, data: data)
            try socketManager.sendFrame(dataFrame)
            
            // 每次发送后主动交出控制权，确保 RunLoop 能处理 socket 输入事件（如 ACK）和 UI 更新
            // 虽然 waitForWritable 已经提供了挂起机会，但在全速发送时仍需保证 responsiveness
            await Task.yield()
            
            currentOffset += Int64(data.count)
            
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
                PersistenceManager.shared.updateProgress(
                    taskId: taskId,
                    progress: progress,
                    uploadedBytes: currentOffset
                )
                // --- Persistence End ---
                
                lastLogTime = now
                lastOffsetForSpeed = currentOffset
            }
        }
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
    
    /// 计算文件 MD5 (优化：仅使用文件名计算，避免读取大文件)
    private func calculateMD5(for url: URL) throws -> String {
        // 使用文件名作为 MD5 计算源
        let fileName = url.lastPathComponent
        guard let data = fileName.data(using: .utf8) else {
            throw FileTransferError.fileNotFound // 如果文件名无法转码，抛出错误
        }
        
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }
        
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Video Streaming
    
    /// 开始流式下载 (用于视频播放)
    /// - Parameters:
    ///   - fileId: 文件ID
    ///   - delegate: 代理
    public func startVideoStreaming(fileId: Int64, delegate: VideoStreamLoaderDelegate) async throws {
        print("🎥 [Stream] 请求视频流: \(fileId)")
        
        let fileIdInt = Int64(fileId)
        let taskId = UUID().uuidString
        
        // 1. 发送下载请求 (MetaFrame)
        // 注意：视频流通常需要全量请求或者Range请求，这里简单起见请求从0开始
        let request: [String: Any] = [
            "fileId": fileIdInt,
            "taskId": taskId,
            "startOffset": 0
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
}

struct EndUploadRequest: Codable {
    let taskId: String
}

struct ResumeAckResponse: Codable {
    let status: String       // "resume", "new"
    let taskId: String?
    let uploadedSize: Int64?
    let message: String?
}

struct StandardAckResponse: Codable {
    let status: String       // "ready", "success"
    let taskId: String?
    let message: String?
}

// MARK: - Errors

enum FileTransferError: LocalizedError {
    case fileNotFound
    case connectionLost
    case serverError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "文件不存在"
        case .connectionLost: return "网络连接已断开"
        case .serverError(let msg): return "服务端错误: \(msg)"
        case .invalidResponse: return "无效的响应数据"
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
