//
//  FileDownloadService.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/7.
//

import Foundation

/// 文件下载服务
/// 负责处理基于流式协议的文件下载,支持异步写入和流控
public class FileDownloadService {
    
    private let socketManager: SocketManager
    
    // 缓存区大小
    private let bufferSize = 4096 // 4KB
    
    // MARK: - 取消机制
    
    /// 取消标志
    private var isCancelled = false
    
    /// 取消锁
    private let cancelLock = NSLock()
    
    // MARK: - 异步写入队列 (流控核心)
    
    /// 异步写入操作队列 (串行执行,保证写入顺序)
    private let writeOperationQueue = OperationQueue()
    
    /// 待写入数据块队列
    private var pendingWrites: [Data] = []
    
    /// 队列锁
    private let writeLock = NSLock()
    
    /// 最大待写入数据块数量 (背压阈值)
    /// 当队列达到此值时,触发背压,暂停接收
    private let maxPendingWrites = 100
    
    /// 背压恢复阈值 (队列降到此值以下时恢复接收)
    private let resumeThreshold = 50
    
    /// 背压状态标记
    private var isBackpressureActive = false
    
    /// 背压锁
    private let backpressureLock = NSLock()
    
    public init(socketManager: SocketManager) {
        self.socketManager = socketManager
        
        // 配置写入队列为串行执行
        self.writeOperationQueue.maxConcurrentOperationCount = 1
        self.writeOperationQueue.qualityOfService = .utility
        self.writeOperationQueue.name = "com.chatstorage.filewrite"
    }
    
    // MARK: - 取消控制方法
    
    /// 取消下载
    public func cancel() {
        cancelLock.lock()
        isCancelled = true
        cancelLock.unlock()
        
        print("🛑 [下载] 收到取消请求")
    }
    
    /// 停止下载
    public func stopDownload() {
        cancel()
        socketManager.disconnect(notifyUI: false)
    }
    
    /// 检查是否已取消
    private func checkCancellation() -> Bool {
        cancelLock.lock()
        let cancelled = isCancelled
        cancelLock.unlock()
        return cancelled
    }
    
    // MARK: - 下载方法
    
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
        
        // 🔹 开启安全访问 (针对 Bookmark 恢复的 URL)
        let isSecurityScoped = localUrl.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                localUrl.stopAccessingSecurityScopedResource()
            }
        }
        
        // 🔹 重置取消标志
        cancelLock.lock()
        isCancelled = false
        cancelLock.unlock()
        
        print("⬇️ [下载] 开始下载文件 ID: \(fileId), TaskID: \(taskId), Offset: \(startOffset)")
        
        // 0.以此确保有权限写入(针对自定义目录)
        let accessGranted = DownloadDirectoryManager.shared.startAccess()
        // 无论成功与否,任务结束时都要停止访问
        defer {
            DownloadDirectoryManager.shared.stopAccess()
        }
        
        // 1. 准备本地文件写入
        let fileManager = FileManager.default
        let fileDir = localUrl.deletingLastPathComponent()
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: fileDir.path) {
            try fileManager.createDirectory(at: fileDir, withIntermediateDirectories: true)
        }
        
        // 如果是断点续传 (startOffset > 0),文件应该已经存在
        // 如果是新下载,创建新文件
        if startOffset == 0 {
            fileManager.createFile(atPath: localUrl.path, contents: nil, attributes: nil)
        }
        
        let fileHandle = try FileHandle(forWritingTo: localUrl)
        defer {
            try? fileHandle.close()
            // 清理写入队列
            self.cleanupWriteQueue()
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
            targetDirId: task.targetDirId,
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
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                var receivedSize: Int64 = startOffset
            var totalSize: Int64 = 0
            var lastUpdateTime = Date()
            var lastBytesReceived: Int64 = startOffset
            var hasResumed = false  // 防止重复 resume
            
            // 监听: 元数据(0x01), 数据帧(0x02), 结束帧(0x03), 响应帧(0x43/0x14 报错用) + 0x04 (确认帧)
            let types: Set<FrameTypeEnum> = [.metaFrame, .dataFrame, .endFrame, .fileResponse, .ackFrame]
            
            socketManager.registerStreamHandler(for: types) { frame in
                
                switch frame.type {
                case .ackFrame, .metaFrame:
                    // 服务端确认/元数据
                    // ACK帧可能携带文件信息
                    if let jsonString = String(data: frame.data, encoding: String.Encoding.utf8),
                       let data = jsonString.data(using: String.Encoding.utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        // 1. 检查错误
                        if let status = dict["status"] as? String, (status == "error" || status == "fail") {
                            let msg = dict["message"] as? String ?? "未知错误"
                            let error = DirectoryError.serverError(code: -1, message: msg)
                            if !hasResumed {
                                hasResumed = true
                                continuation.resume(throwing: error)
                            }
                            return false
                        }
                        
                        // 2. 检查文件信息
                        if let size = dict["fileSize"] as? Int64 {
                            totalSize = size
                            print("✅ [下载] 收到文件信息,大小: \(totalSize)")
                            
                            // ⚠️ 关键步骤: 发送"准备就绪"确认帧给服务端 (0x04)
                            let readyAck: [String: Any] = [
                                "taskId": taskId,
                                "status": "ready"
                            ]
                            if let readyData = try? JSONSerialization.data(withJSONObject: readyAck) {
                                let readyFrame = Frame(type: .ackFrame, data: readyData, flags: 0x00)
                                try? self.socketManager.sendFrame(readyFrame)
                                print("📤 [下载] 发送 Ready 确认帧")
                            }
                            
                            // 立即更新一次进度
                            progressHandler(Double(receivedSize) / Double(totalSize), "准备中...")
                        }
                    }
                    return true
                    
                case .dataFrame:
                    // 🔹 取消检查: 优先检查是否已取消
                    if self.checkCancellation() {
                        print("🛑 [下载] 检测到取消,停止接收")
                        PersistenceManager.shared.updateStatus(taskId: taskId, status: "已暂停")
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(throwing: CancellationError())
                        }
                        return false  // 停止 streamHandler
                    }
                    
                    // 🔹 流控检查: 检查待写入队列深度
                    self.writeLock.lock()
                    let currentPending = self.pendingWrites.count
                    self.writeLock.unlock()
                    
                    // 🔹 背压控制: 队列过深时暂停接收
                    if currentPending >= self.maxPendingWrites {
                        self.backpressureLock.lock()
                        if !self.isBackpressureActive {
                            self.isBackpressureActive = true
                            print("⚠️ [流控] 触发背压,待写入队列: \(currentPending)/\(self.maxPendingWrites)")
                        }
                        self.backpressureLock.unlock()
                        
                        // 暂停接收,等待队列消化
                        Thread.sleep(forTimeInterval: 0.05)  // 50ms
                        return true  // 继续监听,但延迟处理
                    }
                    
                    // 🔹 异步写入: 将数据块加入队列
                    let dataToWrite = frame.data
                    let dataSize = Int64(dataToWrite.count)
                    
                    self.writeLock.lock()
                    self.pendingWrites.append(dataToWrite)
                    let queueDepth = self.pendingWrites.count
                    self.writeLock.unlock()
                    
                    // 🔹 提交异步写入任务
                    self.writeOperationQueue.addOperation { [weak self] in
                        guard let self = self else { return }
                        
                        // 从队列取出数据
                        self.writeLock.lock()
                        guard !self.pendingWrites.isEmpty else {
                            self.writeLock.unlock()
                            return
                        }
                        let data = self.pendingWrites.removeFirst()
                        let remainingCount = self.pendingWrites.count
                        self.writeLock.unlock()
                        
                        // 写入文件
                        do {
                            try fileHandle.write(contentsOf: data)
                            receivedSize += Int64(data.count)
                            
                            // 🔹 背压恢复: 队列降到阈值以下时恢复接收
                            self.backpressureLock.lock()
                            if remainingCount < self.resumeThreshold && self.isBackpressureActive {
                                self.isBackpressureActive = false
                                print("✅ [流控] 解除背压,待写入队列: \(remainingCount)/\(self.maxPendingWrites)")
                            }
                            self.backpressureLock.unlock()
                            
                            // 🔹 内存监控 (每 50 个数据块检查一次)
                            if remainingCount % 50 == 0 {
                                let memoryMB = self.getCurrentMemoryUsage()
                                if memoryMB > 500 {
                                    print("⚠️ [内存] 使用过高: \(String(format: "%.1f", memoryMB)) MB")
                                }
                            }
                            
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
                            if !hasResumed {
                                hasResumed = true
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    
                    return true
                    
                case .endFrame:
                    print("✅ [下载] 下载完成")
                    
                    // 🔹 等待所有写入操作完成
                    self.writeOperationQueue.waitUntilAllOperationsAreFinished()
                    
                    // 确保进度 100%
                    progressHandler(1.0, "完成")
                    PersistenceManager.shared.updateStatus(taskId: taskId, status: "已完成")
                    
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume()
                    }
                    return false
                    
                case .fileResponse:
                    // 错误处理
                    if let dict = try? FrameParser.decodeAsDictionary(frame),
                       let code = dict["code"] as? Int, code != 200 {
                        let msg = dict["message"] as? String ?? "下载失败"
                        let error = DirectoryError.serverError(code: code, message: msg)
                        PersistenceManager.shared.updateStatus(taskId: taskId, status: "失败")
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(throwing: error)
                        }
                        return false
                    }
                    return true
                    
                default:
                    return true
                }
            }
        }
    } onCancel: {
        print("⏸️ [下载] 任务被取消 (Task Cancellation)")
        self.cancel()
    }
}
    
    // MARK: - 辅助方法
    
    /// 清理写入队列
    private func cleanupWriteQueue() {
        writeOperationQueue.cancelAllOperations()
        writeLock.lock()
        pendingWrites.removeAll()
        writeLock.unlock()
        
        backpressureLock.lock()
        isBackpressureActive = false
        backpressureLock.unlock()
        
        print("🧹 [流控] 清理写入队列")
    }
    
    /// 获取当前内存使用量 (MB)
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0.0 }
        
        return Double(info.resident_size) / 1024 / 1024
    }
}
