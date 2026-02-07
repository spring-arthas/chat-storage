//
//  TransferModels.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/7.
//  Consolidated transfer types and manager
//

import Foundation
import Combine

// MARK: - Transfer Models

/// 传输任务类型
public enum TransferTaskType: String, Codable {
    case upload
    case download
}

/// 传输任务模型
public struct StorageTransferTask: Identifiable, Codable {
    public let id: UUID
    public let taskType: TransferTaskType
    public let name: String
    public let fileUrl: URL   // 上传是源文件路径，下载是目标文件路径
    
    // 上传特有
    public let targetDirId: Int64
    
    // 通用/下载特有
    public let userId: Int64
    public let userName: String
    public let fileSize: Int64
    public let directoryName: String
    
    // 状态
    public var progress: Double = 0.0
    public var status: String = "等待中"
    
    // 下载特有：源文件ID (上传时通常 fileUrl 就是源，但下载需要服务器上的 fileId)
    public let remoteFileId: Int64
    
    // 初始化
    public init(id: UUID = UUID(),
         taskType: TransferTaskType,
         name: String,
         fileUrl: URL,
         targetDirId: Int64 = 0,
         userId: Int64,
         userName: String,
         fileSize: Int64,
         directoryName: String = "",
         remoteFileId: Int64 = 0,
         progress: Double = 0.0,
         status: String = "等待中") {
        
        self.id = id
        self.taskType = taskType
        self.name = name
        self.fileUrl = fileUrl
        self.targetDirId = targetDirId
        self.userId = userId
        self.userName = userName
        self.fileSize = fileSize
        self.directoryName = directoryName
        self.remoteFileId = remoteFileId
        self.progress = progress
        self.status = status
    }
}

// MARK: - Transfer Task Manager

/// 传输任务管理器
/// 负责管理文件上传/下载任务的并发执行、排队和状态更新
@MainActor
public class TransferTaskManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = TransferTaskManager()
    
    // MARK: - Published Properties
    
    /// 任务状态更新通知 (用于 UI 监听)
    /// Key: Task.id, Value: (Status, Progress, Speed)
    @Published var taskUpdates: [UUID: (String, Double, String)] = [:]
    
    // MARK: - Private Properties
    
    /// 最大并发数 (根据CPU核心数动态调整，最少4个)
    private let maxConcurrentTasks = 5 // max(4, ProcessInfo.processInfo.processorCount)
    
    /// 正在执行的任务
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    
    /// 等待队列
    private var pendingQueue: [StorageTransferTask] = []
    
    /// 任务映射表 (存储任务详情)
    private var tasks: [UUID: StorageTransferTask] = [:]
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 提交任务
    /// - Parameter task: 传输任务
    public func submit(task: StorageTransferTask) {
        // 如果任务已存在，直接恢复
        if tasks[task.id] != nil {
            resume(id: task.id)
            return
        }
        
        tasks[task.id] = task
        pendingQueue.append(task)
        
        // --- Persistence Integration ---
        // 初始化/保存任务到数据库 (如果尚未保存)
        saveTaskToPersistence(task, status: "Waiting")
        // -----------------------------
        
        scheduleNext()
    }
    
    /// 暂停任务
    /// - Parameter id: 任务ID
    public func pause(id: UUID) {
        // 1. 如果在执行中，取消 Task
        if let runningTask = activeTasks[id] {
            runningTask.cancel()
            activeTasks.removeValue(forKey: id)
            updateTaskStatus(id: id, status: "已暂停")
            // --- Persistence Pause ---
            PersistenceManager.shared.updateStatus(taskId: id.uuidString, status: "Paused")
        }
        
        // 2. 如果在等待队列中，移除
        if let index = pendingQueue.firstIndex(where: { $0.id == id }) {
            pendingQueue.remove(at: index)
            updateTaskStatus(id: id, status: "已暂停")
            // --- Persistence Pause ---
            PersistenceManager.shared.updateStatus(taskId: id.uuidString, status: "Paused")
        }
        
        // 调度下一个
        scheduleNext()
    }
    
    /// 恢复任务 (重新提交)
    /// - Parameter id: 任务ID
    public func resume(id: UUID) {
        guard let task = tasks[id] else { return }
        
        // 如果已经在执行或等待中，忽略
        if activeTasks[id] != nil || pendingQueue.contains(where: { $0.id == id }) {
            return
        }
        
        pendingQueue.append(task)
        updateTaskStatus(id: id, status: "等待中")
        
        scheduleNext()
    }
    
    /// 取消任务 (彻底移除)
    /// - Parameter id: 任务ID
    public func cancel(id: UUID) {
        pause(id: id)
        
        tasks.removeValue(forKey: id)
        taskUpdates.removeValue(forKey: id)
        // Persistence: 可以选择删除或标记为 Cancelled
    }
    
    /// 恢复(还原)任务 - 用于从持久化存储加载
    public func restore(task: StorageTransferTask, status: String, progress: Double) {
        // 存入任务表
        tasks[task.id] = task
        
        // 恢复状态 display logic
        let displayStatus = (status == "Uploading" || status == "Downloading" || status == "Waiting") ? "已暂停" : status
        
        updateTaskStatus(id: task.id, status: displayStatus, progress: progress)
    }
    
    /// 获取所有任务 (用于 UI 同步)
    public func getAllTasks() -> [StorageTransferTask] {
        return Array(self.tasks.values)
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
    private func startTask(_ task: StorageTransferTask) {
        print("🚀 [Manager] 启动任务: \(task.name) (\(task.taskType.rawValue))")
        let statusText = task.taskType == .upload ? "上传中" : "下载中"
        updateTaskStatus(id: task.id, status: statusText)
        
        let executionTask = Task {
            // 创建新的 SocketManager 实例
            let socketManager = SocketManager()
            
            do {
                // 获取当前主连接的 Host
                let (currentHost, currentPort) = SocketManager.shared.getCurrentServer()
                
                // 选择端口
                let targetPort = task.taskType == .upload ? 10087 : 10088
                
                print("🔌 [Manager] 连接服务器: \(currentHost):\(targetPort)")
                
                // 切换(其实是新建连接)到数据端口
                socketManager.switchConnection(host: currentHost, port: UInt32(targetPort))
                
                // 等待连接建立 (简单轮询)
                var attempts = 0
                while socketManager.connectionState != .connected {
                    if attempts > 300 { // 30秒超时
                        throw DirectoryError.serverError(code: -1, message:"Connection failed") 
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    attempts += 1
                }
                
                // 根据类型执行
                switch task.taskType {
                case .upload:
                    let service = FileTransferService(socketManager: socketManager)
                    try await service.uploadFile(
                        fileUrl: task.fileUrl,
                        targetDirId: task.targetDirId,
                        userId: Int32(task.userId),
                        userName: task.userName,
                        taskId: task.id.uuidString,
                        progressHandler: { progress, speed in
                            Task { @MainActor in
                                self.updateTaskProgress(id: task.id, progress: progress, speed: speed)
                            }
                        }
                    )
                    
                case .download:
                    let service = FileDownloadService(socketManager: socketManager)
                    try await service.downloadFile(
                        task: task,
                        startOffset: 0, // 断点续传逻辑需完善：检查本地文件大小
                        progressHandler: { progress, speed in
                             Task { @MainActor in
                                self.updateTaskProgress(id: task.id, progress: progress, speed: speed)
                            }
                        }
                    )
                }
                
                // 任务完成
                await MainActor.run {
                    self.updateTaskStatus(id: task.id, status: "已完成", progress: 1.0)
                }
                socketManager.disconnect()
                
            } catch is CancellationError {
                print("⏸️ [Manager] 任务已暂停 [\(task.name)]")
                await MainActor.run {
                    self.updateTaskStatus(id: task.id, status: "已暂停")
                }
                socketManager.disconnect()
                
            } catch {
                print("❌ [Manager] 任务失败: \(error.localizedDescription)")
                await MainActor.run {
                    self.updateTaskStatus(id: task.id, status: "失败")
                }
                socketManager.disconnect()
            }
            
            // 任务结束清理
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
    
    private func updateTaskProgress(id: UUID, progress: Double, speed: String = "") {
        var current = self.taskUpdates[id] ?? ("", 0.0, "")
        current.1 = progress
        if !speed.isEmpty {
            current.2 = speed
        }
        self.taskUpdates[id] = current
    }
    
    // MARK: - Helpers
    
    private func saveTaskToPersistence(_ task: StorageTransferTask, status: String) {
        var md5Value: String? = nil
        if task.taskType == .download {
            md5Value = "DOWNLOAD_FILE_ID_\(task.remoteFileId)"
        }
        
        PersistenceManager.shared.saveTask(
            taskId: task.id.uuidString,
            fileUrl: task.fileUrl,
            fileName: task.name,
            fileSize: task.fileSize,
            targetDirId: task.targetDirId,
            userId: Int32(task.userId),
            userName: task.userName,
            status: status,
            progress: task.progress,
            md5: md5Value
        )
    }
}
