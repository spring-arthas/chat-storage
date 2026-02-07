//
//  FileDownloadService.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/7.
//

import Foundation

/// 文件下载服务
/// 负责处理基于流式协议的文件下载
public class FileDownloadService {
    
    private let socketManager: SocketManager
    
    // 缓存区大小
    private let bufferSize = 4096 // 4KB
    
    public init(socketManager: SocketManager) {
        self.socketManager = socketManager
    }
    
    /// 下载文件
    /// - Parameters:
    ///   - fileId: 远程文件ID
    ///   - taskId: 任务唯一标识
    ///   - startOffset: 起始偏移量 (用于断点续传)
    ///   - saveTo: 本地保存路径
    ///   - progressHandler: 进度回调 (progress: 0.0-1.0, speed: string)
    /// 下载文件
    /// - Parameters:
    ///   - task: 传输任务对象
    ///   - startOffset: 起始偏移量 (用于断点续传)
    ///   - progressHandler: 进度回调 (progress: 0.0-1.0, speed: string)
    public func downloadFile(
        task: StorageTransferTask,
        startOffset: Int64,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        let fileId = task.remoteFileId
        let taskId = task.id.uuidString
        let localUrl = task.fileUrl
        
        print("⬇️ [下载] 开始下载文件 ID: \(fileId), TaskID: \(taskId), Offset: \(startOffset)")
        
        // 1. 准备本地文件写入
        let fileManager = FileManager.default
        let fileDir = localUrl.deletingLastPathComponent()
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: fileDir.path) {
            try fileManager.createDirectory(at: fileDir, withIntermediateDirectories: true)
        }
        
        // 如果是断点续传 (startOffset > 0)，文件应该已经存在
        // 如果是新下载，创建新文件
        if startOffset == 0 {
            fileManager.createFile(atPath: localUrl.path, contents: nil, attributes: nil)
        }
        
        let fileHandle = try FileHandle(forWritingTo: localUrl)
        defer {
            try? fileHandle.close()
        }
        
        if startOffset > 0 {
            try fileHandle.seek(toOffset: UInt64(startOffset))
        }
        
        // 1.1 保存任务状态到数据库 (用于恢复)
        // Trick: 使用 MD5 字段存储 "DOWNLOAD_FILE_ID_{id}" 以便恢复时识别为下载任务
        let persistenceId = "DOWNLOAD_FILE_ID_\(fileId)"
        PersistenceManager.shared.saveTask(
            taskId: taskId,
            fileUrl: localUrl,
            fileName: task.name,
            fileSize: task.fileSize,
            targetDirId: task.targetDirId, // 0 or whatever
            userId: Int32(task.userId),
            userName: task.userName,
            status: "下载中",
            progress: task.progress,
            uploadedBytes: startOffset,
            md5: persistenceId
        )
        
        // 2. 发送下载请求 (MetaFrame 0x01)
        let request: [String: Any] = [
            "fileId": fileId,
            "taskId": taskId,
            "startOffset": startOffset
        ]
        
        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            throw DirectoryError.invalidData
        }
        
        let requestFrame = Frame(type: .metaFrame, data: requestData, flags: 0x00)
        try socketManager.sendFrame(requestFrame)
        print("📤 [下载] 发送下载请求成功")
        
        // 3. 注册流式处理器并等待数据
        return try await withCheckedThrowingContinuation { continuation in
            var receivedSize: Int64 = startOffset
            var totalSize: Int64 = 0
            var lastUpdateTime = Date()
            var lastBytesReceived: Int64 = startOffset
            
            // 监听: 元数据(0x01), 数据帧(0x02), 结束帧(0x03), 响应帧(0x43/0x14 报错用) + 0x04 (确认帧)
            let types: Set<FrameTypeEnum> = [.metaFrame, .dataFrame, .endFrame, .fileResponse, .ackFrame]
            
            socketManager.registerStreamHandler(for: types) { frame in
                
                switch frame.type {
                case .ackFrame, .metaFrame:
                    // 服务端确认/元数据
                    // ACK帧可能携带文件信息
                    if let jsonString = String(data: frame.data, encoding: .utf8),
                       let data = jsonString.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        // 1. 检查错误
                        if let status = dict["status"] as? String, (status == "error" || status == "fail") {
                            let msg = dict["message"] as? String ?? "未知错误"
                            let error = DirectoryError.serverError(code: -1, message: msg)
                            continuation.resume(throwing: error)
                            return false
                        }
                        
                        // 2. 检查文件信息
                        if let size = dict["fileSize"] as? Int64 {
                            totalSize = size
                            print("✅ [下载] 收到文件信息，大小: \(totalSize)")
                            
                            // ⚠️ 关键步骤: 发送“准备就绪”确认帧给服务端 (0x04)
                            let readyAck: [String: Any] = [
                                "taskId": taskId,
                                "status": "ready"
                            ]
                            if let readyData = try? JSONSerialization.data(withJSONObject: readyAck) {
                                let readyFrame = Frame(type: .ackFrame, data: readyData, flags: 0x00)
                                _ = self.socketManager.send(data: readyFrame.toBytes())
                                print("📤 [下载] 发送 Ready 确认帧")
                            }
                            
                            // 立即更新一次进度
                            progressHandler(Double(receivedSize) / Double(totalSize), "准备中...")
                        }
                    }
                    return true
                    
                case .dataFrame:
                    do {
                        // 写入文件
                        try fileHandle.write(contentsOf: frame.data)
                        
                        receivedSize += Int64(frame.data.count)
                        
                        // 计算速度和进度 (限制更新频率)
                        let now = Date()
                        if now.timeIntervalSince(lastUpdateTime) >= 0.5 {
                            let timeDelta = now.timeIntervalSince(lastUpdateTime)
                            let bytesDelta = receivedSize - lastBytesReceived
                            let speed = Double(bytesDelta) / timeDelta
                            
                            var speedStr = ""
                            if speed < 1024 {
                                speedStr = String(format: "%.0f B/s", speed)
                            } else if speed < 1024 * 1024 {
                                speedStr = String(format: "%.1f KB/s", speed / 1024)
                            } else {
                                speedStr = String(format: "%.1f MB/s", speed / 1024 / 1024)
                            }
                            
                            let progress = totalSize > 0 ? Double(receivedSize) / Double(totalSize) : 0.0
                            progressHandler(progress, speedStr)
                            
                            // 更新数据库
                            PersistenceManager.shared.updateProgress(
                                taskId: taskId,
                                progress: progress,
                                uploadedBytes: receivedSize,
                                status: "下载中"
                            )
                            
                            lastUpdateTime = now
                            lastBytesReceived = receivedSize
                        }
                    } catch {
                        print("❌ [下载] 写入失败: \(error)")
                        PersistenceManager.shared.updateStatus(taskId: taskId, status: "失败")
                        continuation.resume(throwing: error)
                        return false
                    }
                    return true
                    
                case .endFrame:
                    print("✅ [下载] 下载完成")
                    // 确保进度 100%
                    progressHandler(1.0, "完成")
                    PersistenceManager.shared.updateStatus(taskId: taskId, status: "已完成")
                    // Optional: Delete from DB if you don't want to keep history, but usually we keep 'Completed'
                    
                    continuation.resume()
                    return false
                    
                case .fileResponse:
                    // 错误处理
                    if let dict = try? FrameParser.decodeAsDictionary(frame),
                       let code = dict["code"] as? Int, code != 200 {
                        let msg = dict["message"] as? String ?? "下载失败"
                        let error = DirectoryError.serverError(code: code, message: msg)
                        PersistenceManager.shared.updateStatus(taskId: taskId, status: "失败")
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
