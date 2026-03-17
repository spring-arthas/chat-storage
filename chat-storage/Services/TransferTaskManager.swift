//
//  TransferTaskManager.swift
//  chat-storage
//
//  Created by TraeAI on 2026/2/1.
//

import Foundation
import Combine

/// 传输任务管理器
/// 负责管理文件上传/下载任务的并发执行、排队和状态更新
class TransferTaskManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = TransferTaskManager()
    
    // MARK: - Published Properties
    
    /// 任务状态更新通知 (用于 UI 监听)
    /// Key: TransferItem.id, Value: (Status, Progress, Speed)
    @Published var taskUpdates: [String: (String, Double, String)] = [:]
    
    // MARK: - Private Properties
    
    /// 最大并发数
    private let maxConcurrentTasks = 5
    
    /// 正在执行的任务
    private var activeTasks: [String: Task<Void, Never>] = [:]
    
    /// 等待队列
    private var pendingQueue: [StorageTransferTask] = []
    
    /// 任务映射表 (存储任务详情)
    private var tasks: [String: StorageTransferTask] = [:]
    
    /// 锁 (保护 activeTasks 和 pendingQueue)
    private let lock = NSLock()
    
    private init() {
        // 从数据库恢复未完成的任务
        restoreTasksFromDatabase()
    }
    
    /// 从数据库恢复任务
    private func restoreTasksFromDatabase() {
        let entities = PersistenceManager.shared.fetchPendingTasks()
        print("📥 从数据库恢复 \(entities.count) 个任务")
        
        for entity in entities {
            guard let taskIdString = entity.taskId,
                  let taskId = UUID(uuidString: taskIdString),
                  let fileName = entity.fileName else {
                continue
            }
            
            // 解析 bookmark 获取 URL
            var fileUrl: URL?
            if let bookmarkData = entity.fileUrl {
                fileUrl = PersistenceManager.shared.resolveBookmark(data: bookmarkData)
            }
            
            guard let url = fileUrl else {
                print("⚠️ 无法解析任务 \(fileName) 的文件路径，跳过")
                continue
            }
            
            // 判断任务类型和恢复 remoteFileId
            var taskType: TransferTaskType = .upload
            var remoteFileId: Int64 = 0
            
            // 检查 MD5 字段是否包含下载任务的特殊标记
            if let md5 = entity.md5, md5.starts(with: "DOWNLOAD_FILE_ID_") {
                taskType = .download
                // 从 "DOWNLOAD_FILE_ID_12345" 中提取 ID
                if let idStr = md5.components(separatedBy: "_").last,
                   let id = Int64(idStr) {
                    remoteFileId = id
                }
            } else {
                // 如果没有标记，默认为上传 (为了兼容根目录上传 targetDirId=0 的情况)
                taskType = .upload
            }
            
            let task = StorageTransferTask(
                id: taskId,
                taskType: taskType,
                name: fileName,
                fileUrl: url,
                targetDirId: entity.targetDirId,
                userId: Int64(entity.userId),
                userName: entity.userName ?? "default",
                fileSize: entity.fileSize,
                directoryName: "",  // 数据库中没有存储，使用默认值
                remoteFileId: remoteFileId,
                progress: entity.progress,
                status: entity.status ?? "已暂停"
            )
            
            tasks[taskIdString] = task
            print("✅ 恢复任务: \(fileName), 进度: \(Int(task.progress * 100))%")
        }
        
        print("✅ 成功恢复 \(tasks.count) 个任务")
    }
    
    // MARK: - Public Methods
    
    /// 提交任务
    /// - Parameter task: 传输任务
    func submit(task: StorageTransferTask) {
        lock.lock()
        // Ensure ID is String
        let id = task.id.uuidString
        tasks[id] = task
        pendingQueue.append(task)
        lock.unlock()
        
        print("✅ [提交任务] ID: \(id), Name: \(task.name)")
        print("📋 [提交任务] 当前 pendingQueue 大小: \(pendingQueue.count), activeTasks 大小: \(activeTasks.count)")
        
        let dumpStatus = activeTasks.keys.joined(separator: ", ")
        print("📋 [DEBUG] 当前 execution keys: \(dumpStatus)")
        
        scheduleNext()
    }
    
    /// 暂停任务
    /// - Parameter id: 任务ID
    func pause(id: UUID) {
        let idStr = id.uuidString
        lock.lock()
        
        // 1. 如果在执行中，取消 Task
        if let runningTask = activeTasks[idStr] {
            runningTask.cancel()
            activeTasks.removeValue(forKey: idStr)
            updateTaskStatus(id: idStr, status: "暂停")
        }
        
        // 2. 如果在等待队列中，移除
        if let index = pendingQueue.firstIndex(where: { $0.id.uuidString == idStr }) {
            pendingQueue.remove(at: index)
            updateTaskStatus(id: idStr, status: "暂停")
        }
        
        lock.unlock() // 必须先释放锁，再调度，因为 scheduleNext 也会加锁
        
        // 调度下一个
        scheduleNext()
    }
    
    /// 恢复任务 (重新提交)
    /// - Parameter id: 任务ID
    func resume(id: UUID) {
        let idStr = id.uuidString
        lock.lock()
        guard let task = tasks[idStr] else {
            print("❌ [恢复任务失败] 找不到任务实例: \(idStr)")
            lock.unlock()
            return
        }
        
        // 如果已经在执行或等待中，忽略
        if activeTasks[idStr] != nil || pendingQueue.contains(where: { $0.id.uuidString == idStr }) {
            print("⚠️ [恢复任务忽略] 任务已在执行或等待队列中: \(task.name)")
            lock.unlock()
            return
        }
        
        print("🔄 [恢复任务] 重新加入队列: \(task.name)")
        
        pendingQueue.append(task)
        
        // 根据任务类型更新状态
        let status = task.taskType == .upload ? "等待上传" : "等待下载"
        updateTaskStatus(id: idStr, status: status)
        
        lock.unlock() // 必须先释放锁，再调度
        
        scheduleNext()
    }
    
    /// 取消任务 (彻底移除)
    /// - Parameter id: 任务ID
    func cancel(id: UUID) {
        let idStr = id.uuidString
        pause(id: id)
        
        lock.lock()
        tasks.removeValue(forKey: idStr)
        taskUpdates.removeValue(forKey: idStr)
        lock.unlock()
        
        // 同时从数据库删除
        PersistenceManager.shared.deleteTask(taskId: idStr)
    }
    
    /// 清除所有已完成的任务 (内存 + 数据库)
    func clearCompletedTasks() {
        lock.lock()
        
        // 1. 找出所有已完成的任务ID (status == "已完成" 或 internal check)
        // 注意：这里我们主要依靠 taskUpdates 中的状态，或者 tasks 中的状态
        // 由于 tasks 中的 status 可能不是最新的（status更新主要在 taskUpdates），我们需要结合判断
        
        var idsToRemove: [String] = []
        
        for (id, task) in tasks {
            // Check taskUpdates first for latest status
            if let update = taskUpdates[id], (update.0 == "已完成" || update.0 == "Completed") {
                idsToRemove.append(id)
            } else if task.status == "已完成" || task.status == "Completed" {
                idsToRemove.append(id)
            }
        }
        
        // 2. 从内存移除
        for id in idsToRemove {
            tasks.removeValue(forKey: id)
            taskUpdates.removeValue(forKey: id)
            // 已完成的任务应该不在 activeTasks 或 pendingQueue 中，但为了保险起见检查一下
            activeTasks.removeValue(forKey: id)
            if let index = pendingQueue.firstIndex(where: { $0.id.uuidString == id }) {
                pendingQueue.remove(at: index)
            }
        }
        
        lock.unlock()
        
        print("🧹 [TransferTaskManager] 内存中已清除 \(idsToRemove.count) 个已完成任务")
        
        // 3. 从数据库移除
        PersistenceManager.shared.deleteCompletedTasks()
    }

    /// 恢复任务 (仅用于从持久化恢复，不立即执行)
    func restore(task: StorageTransferTask, status: String, progress: Double) {
        lock.lock()
        let idStr = task.id.uuidString
        tasks[idStr] = task
        // 初始化状态
        taskUpdates[idStr] = (status, progress, "")
        lock.unlock()
    }
    
    /// 获取所有任务详情 (用于 UI 恢复)
    func getAllTasks() -> [StorageTransferTask] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tasks.values)
    }
    
    // MARK: - Private Methods
    
    /// 调度下一个任务
    private func scheduleNext() {
        lock.lock()
        defer { lock.unlock() }
        
        print("📅 [scheduleNext] 被调用 - 当前 activeTasks: \(activeTasks.count)/\(maxConcurrentTasks), pendingQueue: \(pendingQueue.count)")
        
        // 如果已达到最大并发，不调度新任务
        guard activeTasks.count < maxConcurrentTasks else {
            print("⚠️ [scheduleNext] 已达到最大并发限制")
            return 
        }
        
        // 获取下一个等待任务
        guard let task = pendingQueue.first else { 
            print("ℹ️ [scheduleNext] pendingQueue 为空，无任务可调度")
            return 
        }
        
        pendingQueue.removeFirst()
        let idStr = task.id.uuidString
        
        print("✅ [scheduleNext] 开始执行任务: \(task.name) (ID: \(idStr))")
        startTask(task)
    }
    
    /// 启动单个任务
    private func startTask(_ task: StorageTransferTask) {
        print("🚀 启动任务: \(task.name)")
        let idStr = task.id.uuidString
        updateTaskStatus(id: idStr, status: task.taskType == .upload ? "上传中" : "下载中")
        
        let executionTask = Task {
            // 创建独立的 SocketManager 实例用于文件传输
            let socketManager = SocketManager()
            var isSocketConnected = false
            
            // defer 确保在任何退出路径都断开连接
            defer {
                if isSocketConnected {
                    Task {
                        await MainActor.run {
                            socketManager.disconnect()
                        }
                    }
                    print("🔌 传输连接已断开")
                }
            }
            
            do {
                
                // 获取当前主连接的 Host
                let (currentHost, _) = SocketManager.shared.getCurrentServer()
                
                // 根据任务类型选择端口
                let transferPort: UInt32 = task.taskType == .upload ? 10087 : 10088
                print("📡 连接到传输端口: \(transferPort) (\(task.taskType == .upload ? "上传" : "下载"))")
                
                // 异步连接到传输端口（不阻塞主线程）
                await MainActor.run {
                    socketManager.switchConnection(host: currentHost, port: transferPort)
                }
                
                // 等待连接建立（带超时）
                var attempts = 0
                while socketManager.connectionState != .connected {
                    if attempts > 50 { 
                        print("❌ 连接超时: \(transferPort), 状态: \(socketManager.connectionState)")
                        throw FileTransferError.connectionLost 
                    }
                    if case .error(let str) = socketManager.connectionState {
                        print("❌ 连接错误: \(str) on port \(transferPort)")
                        throw FileTransferError.connectionLost
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    attempts += 1
                }
                
                isSocketConnected = true
                print("✅ 传输连接已建立: \(transferPort)")
                
                // 执行传输逻辑
                if task.taskType == .upload {
                    let service = FileTransferService(socketManager: socketManager)
                    
                    // 从数据库读取已上传字节数（用于断点续传）
                    let startOffset = getUploadedBytes(taskId: idStr)
                    print("🔄 从数据库读取上传断点: \(startOffset) bytes")
                    
                    try await service.uploadFile(
                        fileUrl: task.fileUrl,
                        targetDirId: task.targetDirId,
                        userId: Int32(task.userId),
                        userName: task.userName,
                        taskId: task.id.uuidString,
                        startOffset: startOffset,
                        progressHandler: { progress, speed in
                            self.updateTaskProgress(id: idStr, progress: progress, speed: speed)
                        }
                    )
                } else {
                    // 下载功能
                    let downloadService = FileDownloadService(socketManager: socketManager)
                    
                    // 从数据库读取已下载字节数（用于断点续传）
                    let startOffset = getDownloadedBytes(taskId: idStr)
                    print("🔄 从数据库读取下载断点: \(startOffset) bytes")
                    
                    try await downloadService.downloadFile(
                        task: task,
                        startOffset: startOffset,
                        progressHandler: { progress, speed in
                            self.updateTaskProgress(id: idStr, progress: progress, speed: speed)
                        }
                    )
                }
                
                // 任务完成
                self.updateTaskStatus(id: idStr, status: "已完成", progress: 1.0)
                
                } catch {
                // 区分取消和真正的失败
                if error is CancellationError {
                    print("⏸️ 任务已暂停 [\(task.name)]")
                    self.updateTaskStatus(id: idStr, status: "已暂停")
                } else {
                    print("❌ 任务失败 [\(task.name)]: \(error)")
                    self.updateTaskStatus(id: idStr, status: "失败")
                }
            }
            
            // 任务结束清理
            self.lock.lock()
            self.activeTasks.removeValue(forKey: idStr)
            self.lock.unlock()
            
            // 调度下一个
            self.scheduleNext()
        }
        
        activeTasks[idStr] = executionTask
    }
    
    // MARK: - Database Helpers
    
    /// 从数据库获取已上传/下载字节数
    private func getUploadedBytes(taskId: String) -> Int64 {
        guard let entity = PersistenceManager.shared.fetchEntity(taskId: taskId) else {
            return 0
        }
        return entity.uploadedBytes
    }
    
    /// 从数据库获取已下载字节数
    private func getDownloadedBytes(taskId: String) -> Int64 {
        // 使用同一个 uploadedBytes 字段存储已下载字节数
        return getUploadedBytes(taskId: taskId)
    }
    
    // MARK: - Status Updates
    
    private func updateTaskStatus(id: String, status: String, progress: Double? = nil) {
        DispatchQueue.main.async {
            var current = self.taskUpdates[id] ?? ("", 0.0, "")
            current.0 = status
            if let p = progress {
                current.1 = p
            }
            self.taskUpdates[id] = current
        }
    }
    
    private func updateTaskProgress(id: String, progress: Double, speed: String) {
        DispatchQueue.main.async {
            var current = self.taskUpdates[id] ?? ("", 0.0, "")
            current.1 = progress
            current.2 = speed
            // 这里可以简单计算速度，或者由 Service 计算传递过来
            self.taskUpdates[id] = current
        }
    }
}


