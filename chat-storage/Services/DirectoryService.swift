//
//  DirectoryService.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/31.
//

import Foundation
import Combine
import CommonCrypto

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
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail):
            return "响应数据无效: \(detail)"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
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
        userId: Int64,
        taskId: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        print("🚀 开始上传文件: \(fileUrl.lastPathComponent) (TaskID: \(taskId))")
        
        // 1. 准备文件信息
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            throw FileTransferError.fileNotFound
        }
        
        let fileSize = try fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize.map { Int64($0) } ?? 0
        let fileName = fileUrl.lastPathComponent
        let fileType = fileUrl.pathExtension
        
        // 2. 计算 MD5
        print("⏳ 正在计算 MD5...")
        let md5 = try calculateMD5(for: fileUrl)
        print("✅ MD5 计算完成: \(md5)")
        
        // 3. 构建元数据请求体
        // 3. 构建元数据请求体
        let metaRequest = FileMetaRequest(
            md5: md5,
            fileName: fileName,
            fileSize: fileSize,
            fileType: fileType,
            dirId: targetDirId,
            userId: userId,
            taskId: taskId
        )
        
        // 4. 发送断点检查帧 (0x05)
        print("🔍 发送断点检查请求...")
        let checkFrame = try FrameBuilder.build(type: .resumeCheck, payload: metaRequest)
        let checkResponseFrame = try await socketManager.sendFrameAndWait(checkFrame, expecting: .resumeAck)
        
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
            
            // 发送元数据帧 (0x01)
            let metaFrame = try FrameBuilder.build(type: .metaFrame, payload: metaRequest)
            let metaResponseFrame = try await socketManager.sendFrameAndWait(metaFrame, expecting: .ackFrame)
            
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
        
        // 5. 发送文件数据 (0x02)
        if offset < fileSize {
            try await sendFileData(
                fileUrl: fileUrl,
                offset: offset,
                taskId: finalTaskId, // 使用 finalTaskId
                fileSize: fileSize,
                progressHandler: progressHandler
            )
        } else {
            print("✅ 文件已完整，跳过数据发送")
            progressHandler?(1.0)
        }
        
        // 6. 发送结束帧 (0x03)
        print("🏁 发送结束帧...")
        let endRequest = EndUploadRequest(taskId: finalTaskId) // 使用 finalTaskId
        let endFrame = try FrameBuilder.build(type: .endFrame, payload: endRequest)
        let endResponseFrame = try await socketManager.sendFrameAndWait(endFrame, expecting: .ackFrame, timeout: 60.0)
        
        let finalAck = try FrameParser.decodePayload(endResponseFrame, as: StandardAckResponse.self)
        
        if finalAck.status == "success" {
            print("🎉 文件上传成功!")
        } else {
            throw FileTransferError.serverError(finalAck.message ?? "上传最终确认失败")
        }
    }
    
    /// 发送文件数据分块
    private func sendFileData(
        fileUrl: URL,
        offset: Int64,
        taskId: String,
        fileSize: Int64,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        let fileHandle = try FileHandle(forReadingFrom: fileUrl)
        defer { try? fileHandle.close() }
        
        // 定位到断点位置
        if offset > 0 {
            try fileHandle.seek(toOffset: UInt64(offset))
        }
        
        var currentOffset = offset
        var lastLogTime = Date()
        
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
                    await socketManager.waitForWritable()
                    
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
            
            // 更新进度 (每 500ms 回调一次，避免 UI 刷新过频)
            let now = Date()
            if now.timeIntervalSince(lastLogTime) > 0.5 || currentOffset == fileSize {
                let progress = Double(currentOffset) / Double(fileSize)
                progressHandler?(progress)
                lastLogTime = now
                // print("📤 上传进度: \(String(format: "%.1f", progress * 100))%")
            }
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
}

// MARK: - Data Models (Request/Response)

struct FileMetaRequest: Codable {
    let md5: String
    let fileName: String
    let fileSize: Int64
    let fileType: String
    let dirId: Int64
    let userId: Int64
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

// MARK: - TransferTaskManager (Merged)
// Merged to resolve scope visibility issues.

/// 传输任务管理器
/// 负责管理文件上传/下载任务的并发执行、排队和状态更新
@MainActor
class TransferTaskManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = TransferTaskManager()
    
    // MARK: - Published Properties
    
    /// 任务状态更新通知 (用于 UI 监听)
    /// Key: TransferItem.id, Value: (Status, Progress, Speed)
    @Published var taskUpdates: [UUID: (String, Double, String)] = [:]
    
    // MARK: - Private Properties
    
    /// 最大并发数 (根据CPU核心数动态调整，最少4个)
    private let maxConcurrentTasks = max(4, ProcessInfo.processInfo.processorCount)
    
    /// 正在执行的任务
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    
    /// 等待队列
    private var pendingQueue: [TransferTask] = []
    
    /// 任务映射表 (存储任务详情)
    private var tasks: [UUID: TransferTask] = [:]
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 提交任务
    /// - Parameter task: 传输任务
    func submit(task: TransferTask) {
        // 如果任务已存在，直接恢复
        if tasks[task.id] != nil {
            resume(id: task.id)
            return
        }
        
        tasks[task.id] = task
        pendingQueue.append(task)
        
        scheduleNext()
    }
    
    /// 暂停任务
    /// - Parameter id: 任务ID
    func pause(id: UUID) {
        // 1. 如果在执行中，取消 Task
        if let runningTask = activeTasks[id] {
            runningTask.cancel()
            activeTasks.removeValue(forKey: id)
            updateTaskStatus(id: id, status: "暂停")
        }
        
        // 2. 如果在等待队列中，移除
        if let index = pendingQueue.firstIndex(where: { $0.id == id }) {
            pendingQueue.remove(at: index)
            updateTaskStatus(id: id, status: "暂停")
        }
        
        // 调度下一个
        scheduleNext()
    }
    
    /// 恢复任务 (重新提交)
    /// - Parameter id: 任务ID
    func resume(id: UUID) {
        guard let task = tasks[id] else {
            return
        }
        
        // 如果已经在执行或等待中，忽略
        if activeTasks[id] != nil || pendingQueue.contains(where: { $0.id == id }) {
            return
        }
        
        pendingQueue.append(task)
        updateTaskStatus(id: id, status: "等待上传")
        
        scheduleNext()
    }
    
    /// 取消任务 (彻底移除)
    /// - Parameter id: 任务ID
    func cancel(id: UUID) {
        pause(id: id)
        
        tasks.removeValue(forKey: id)
        taskUpdates.removeValue(forKey: id)
    }
    
    // MARK: - Private Methods
    
    /// 调度下一个任务
    private func scheduleNext() {
        // 检查并发限制
        guard activeTasks.count < maxConcurrentTasks else { return }
        
        // 检查是否有等待任务
        guard !pendingQueue.isEmpty else { return }
        
        // 取出第一个任务
        let task = pendingQueue.removeFirst()
        
        // 启动任务
        startTask(task)
    }
    
    /// 启动单个任务
    private func startTask(_ task: TransferTask) {
        print("🚀 启动任务: \(task.name)")
        updateTaskStatus(id: task.id, status: "上传中")
        
        let executionTask = Task {
            do {
                // 创建新的 SocketManager 实例
                // 注意：SocketManager 应该是线程安全的，或者我们需要确保它可以在后台线程使用
                let socketManager = SocketManager()
                
                // 获取当前主连接的 Host (从 SocketManager.shared 获取，假设它是线程安全的或我们只读)
                let (currentHost, _) = SocketManager.shared.getCurrentServer()
                
                // 切换到数据端口
                socketManager.switchConnection(host: currentHost, port: 10087)
                
                // 等待连接建立
                var attempts = 0
                while socketManager.connectionState != .connected {
                    if attempts > 300 { throw TransferError.connectionFailed } // 30秒超时 (300 * 0.1s)
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    attempts += 1
                }
                
                // 执行上传逻辑
                let service = FileTransferService(socketManager: socketManager)
                
                try await service.uploadFile(
                    fileUrl: task.fileUrl,
                    targetDirId: task.targetDirId,
                    userId: task.userId,
                    taskId: task.id.uuidString,
                    progressHandler: { progress in
                        // 回到主线程更新进度
                        Task { @MainActor in
                            self.updateTaskProgress(id: task.id, progress: progress)
                        }
                    }
                )
                
                // 任务完成 (回到主线程)
                await MainActor.run {
                    self.updateTaskStatus(id: task.id, status: "已完成", progress: 1.0)
                }
                socketManager.disconnect()
                
            } catch {
                print("❌ 任务失败 [\(task.name)]: \(error)")
                await MainActor.run {
                    self.updateTaskStatus(id: task.id, status: "失败")
                }
            }
            
            // 任务结束清理 (回到主线程)
            await MainActor.run {
                self.activeTasks.removeValue(forKey: task.id)
                self.scheduleNext()
            }
        }
        
        activeTasks[task.id] = executionTask
    }
    
    // MARK: - Status Updates
    
    private func updateTaskStatus(id: UUID, status: String, progress: Double? = nil) {
        var current = self.taskUpdates[id] ?? ("", 0.0, "")
        current.0 = status
        if let p = progress {
            current.1 = p
        }
        self.taskUpdates[id] = current
    }
    
    private func updateTaskProgress(id: UUID, progress: Double) {
        var current = self.taskUpdates[id] ?? ("", 0.0, "")
        current.1 = progress
        // 这里可以简单计算速度，或者由 Service 计算传递过来
        self.taskUpdates[id] = current
    }
}

/// 传输任务模型 (内部使用)
struct TransferTask {
    let id: UUID
    let name: String
    let fileUrl: URL
    let targetDirId: Int64
    let userId: Int64
}

enum TransferError: Error {
    case connectionFailed
}
