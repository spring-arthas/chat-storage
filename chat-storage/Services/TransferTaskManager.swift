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
    @Published var taskUpdates: [UUID: (String, Double, String)] = [:]
    
    // MARK: - Private Properties
    
    /// 最大并发数
    private let maxConcurrentTasks = 10
    
    /// 正在执行的任务
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    
    /// 等待队列
    private var pendingQueue: [TransferTask] = []
    
    /// 任务映射表 (存储任务详情)
    private var tasks: [UUID: TransferTask] = [:]
    
    /// 锁 (保护 activeTasks 和 pendingQueue)
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 提交任务
    /// - Parameter task: 传输任务
    func submit(task: TransferTask) {
        lock.lock()
        tasks[task.id] = task
        pendingQueue.append(task)
        lock.unlock()
        
        scheduleNext()
    }
    
    /// 暂停任务
    /// - Parameter id: 任务ID
    func pause(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
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
        lock.lock()
        guard let task = tasks[id] else {
            lock.unlock()
            return
        }
        
        // 如果已经在执行或等待中，忽略
        if activeTasks[id] != nil || pendingQueue.contains(where: { $0.id == id }) {
            lock.unlock()
            return
        }
        
        pendingQueue.append(task)
        updateTaskStatus(id: id, status: "等待上传")
        lock.unlock()
        
        scheduleNext()
    }
    
    /// 取消任务 (彻底移除)
    /// - Parameter id: 任务ID
    func cancel(id: UUID) {
        pause(id: id)
        
        lock.lock()
        tasks.removeValue(forKey: id)
        taskUpdates.removeValue(forKey: id)
        lock.unlock()
    }
    
    // MARK: - Private Methods
    
    /// 调度下一个任务
    private func scheduleNext() {
        lock.lock()
        defer { lock.unlock() }
        
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
                let socketManager = SocketManager()
                
                // 配置连接参数 (服务端端口 10087)
                // 注意：这里需要先修改 SocketManager 支持外部配置 Host/Port，或者在 connect 前设置
                // 暂时假设 SocketManager 有 switchConnection 方法或我们直接修改它的属性
                // 由于 SocketManager 的 host/port 是 private，我们需要用 switchConnection
                
                // 获取当前主连接的 Host
                let (currentHost, _) = SocketManager.shared.getCurrentServer()
                
                // 切换到数据端口
                socketManager.switchConnection(host: currentHost, port: 10087)
                
                // 等待连接建立 (简单轮询检查，或者 SocketManager 内部支持 async connect)
                // 由于 switchConnection 是异步的，我们这里需要稍微等待一下或检查状态
                // 更好的方式是给 SocketManager 加一个 async connect 方法
                // 这里我们暂时假设 switchConnection 会触发连接，我们轮询检查状态
                
                var attempts = 0
                while socketManager.connectionState != .connected {
                    if attempts > 50 { throw TransferError.connectionFailed } // 5秒超时
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    attempts += 1
                }
                
                // 执行上传逻辑
                let service = FileTransferService(socketManager: socketManager)
                
                try await service.uploadFile(
                    fileUrl: task.fileUrl,
                    targetDirId: task.targetDirId,
                    userId: task.userId,
                    progressHandler: { progress in
                        self.updateTaskProgress(id: task.id, progress: progress)
                    }
                )
                
                // 任务完成
                self.updateTaskStatus(id: task.id, status: "已完成", progress: 1.0)
                socketManager.disconnect()
                
            } catch {
                print("❌ 任务失败 [\(task.name)]: \(error)")
                self.updateTaskStatus(id: task.id, status: "失败")
            }
            
            // 任务结束清理
            self.lock.lock()
            self.activeTasks.removeValue(forKey: task.id)
            self.lock.unlock()
            
            // 调度下一个
            self.scheduleNext()
        }
        
        activeTasks[task.id] = executionTask
    }
    
    // MARK: - Status Updates
    
    private func updateTaskStatus(id: UUID, status: String, progress: Double? = nil) {
        DispatchQueue.main.async {
            var current = self.taskUpdates[id] ?? ("", 0.0, "")
            current.0 = status
            if let p = progress {
                current.1 = p
            }
            self.taskUpdates[id] = current
        }
    }
    
    private func updateTaskProgress(id: UUID, progress: Double) {
        DispatchQueue.main.async {
            var current = self.taskUpdates[id] ?? ("", 0.0, "")
            current.1 = progress
            // 这里可以简单计算速度，或者由 Service 计算传递过来
            self.taskUpdates[id] = current
        }
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
