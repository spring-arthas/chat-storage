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

    struct UploadIdentity: Equatable {
        let userId: Int32
        let userName: String
    }

    static func shouldPostFileListRefresh(for taskType: TransferTaskType) -> Bool {
        taskType == .upload
    }
    
    // MARK: - Singleton
    
    static let shared = TransferTaskManager()
    
    // MARK: - Published Properties
    
    /// 任务状态更新通知 (用于 UI 监听)
    /// Key: TransferItem.id, Value: (Status, Progress, Speed)
    @Published var taskUpdates: [String: (String, Double, String)] = [:]
    
    // MARK: - Private Properties
    
    /// 最大并发数
    private let maxConcurrentTasks = 5
    
    /// 任务状态 (async-safe)
    private struct TaskState {
        var activeTasks: [String: Task<Void, Never>] = [:]
        var pendingQueue: [StorageTransferTask] = []
        var tasks: [String: StorageTransferTask] = [:]
    }
    
    private let state = ManagedCriticalState(TaskState())
    
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
            
            state.withCriticalRegion { $0.tasks[taskIdString] = task }
            print("✅ 恢复任务: \(fileName), 进度: \(Int(task.progress * 100))%")
        }

        let restoredCount = state.withCriticalRegion { $0.tasks.count }
        print("✅ 成功恢复 \(restoredCount) 个任务")
    }
    
    // MARK: - Public Methods
    
    /// 提交任务
    /// - Parameter task: 传输任务
    func submit(task: StorageTransferTask) {
        // Ensure ID is String
        let id = task.id.uuidString
        let counts = state.withCriticalRegion { state -> (pendingCount: Int, activeCount: Int) in
            state.tasks[id] = task
            state.pendingQueue.append(task)
            return (state.pendingQueue.count, state.activeTasks.count)
        }

        print("✅ [提交任务] ID: \(id), Name: \(task.name)")
        print("📋 [提交任务] 当前 pendingQueue 大小: \(counts.pendingCount), activeTasks 大小: \(counts.activeCount)")

        let dumpStatus = state.withCriticalRegion { $0.activeTasks.keys.joined(separator: ", ") }
        print("📋 [DEBUG] 当前 execution keys: \(dumpStatus)")

        scheduleNext()
    }
    
    /// 暂停任务
    /// - Parameter id: 任务ID
    func pause(id: UUID) {
        let idStr = id.uuidString
        var runningTask: Task<Void, Never>?
        var removedPending = false
        
        state.withCriticalRegion { state in
            if let task = state.activeTasks.removeValue(forKey: idStr) {
                runningTask = task
            }
            if let index = state.pendingQueue.firstIndex(where: { $0.id.uuidString == idStr }) {
                state.pendingQueue.remove(at: index)
                removedPending = true
            }
        }
        
        if let runningTask {
            runningTask.cancel()
            updateTaskStatus(id: idStr, status: "暂停")
        }
        
        if removedPending {
            updateTaskStatus(id: idStr, status: "暂停")
        }
        
        // 调度下一个
        scheduleNext()
    }
    
    /// 恢复任务 (重新提交)
    /// - Parameter id: 任务ID
    func resume(id: UUID) {
        let idStr = id.uuidString
        var task: StorageTransferTask?
        var alreadyQueued = false
        
        state.withCriticalRegion { state in
            task = state.tasks[idStr]
            if state.activeTasks[idStr] != nil || state.pendingQueue.contains(where: { $0.id.uuidString == idStr }) {
                alreadyQueued = true
                return
            }
            if let task {
                state.pendingQueue.append(task)
            }
        }
        
        guard let task else {
            print("❌ [恢复任务失败] 找不到任务实例: \(idStr)")
            return
        }
        
        if alreadyQueued {
            print("⚠️ [恢复任务忽略] 任务已在执行或等待队列中: \(task.name)")
            return
        }
        
        print("🔄 [恢复任务] 重新加入队列: \(task.name)")
        
        // 根据任务类型更新状态
        let status = task.taskType == .upload ? "等待上传" : "等待下载"
        updateTaskStatus(id: idStr, status: status)
        
        scheduleNext()
    }
    
    /// 取消任务 (彻底移除)
    /// - Parameter id: 任务ID
    func cancel(id: UUID) {
        let idStr = id.uuidString
        pause(id: id)
        
        state.withCriticalRegion { state in
            state.tasks.removeValue(forKey: idStr)
            state.activeTasks.removeValue(forKey: idStr)
            if let index = state.pendingQueue.firstIndex(where: { $0.id.uuidString == idStr }) {
                state.pendingQueue.remove(at: index)
            }
        }
        taskUpdates.removeValue(forKey: idStr)
        
        // 同时从数据库删除
        PersistenceManager.shared.deleteTask(taskId: idStr)
    }
    
    /// 清除所有已完成的任务 (内存 + 数据库)
    func clearCompletedTasks() {
        let idsToRemove = state.withCriticalRegion { state -> [String] in
            var ids: [String] = []
            for (id, task) in state.tasks {
                if let update = taskUpdates[id], (update.0 == "已完成" || update.0 == "Completed") {
                    ids.append(id)
                } else if task.status == "已完成" || task.status == "Completed" {
                    ids.append(id)
                }
            }
            return ids
        }
        
        state.withCriticalRegion { state in
            for id in idsToRemove {
                state.tasks.removeValue(forKey: id)
                state.activeTasks.removeValue(forKey: id)
                if let index = state.pendingQueue.firstIndex(where: { $0.id.uuidString == id }) {
                    state.pendingQueue.remove(at: index)
                }
            }
        }
        
        for id in idsToRemove {
            taskUpdates.removeValue(forKey: id)
        }
        
        print("🧹 [TransferTaskManager] 内存中已清除 \(idsToRemove.count) 个已完成任务")
        
        // 3. 从数据库移除
        PersistenceManager.shared.deleteCompletedTasks()
    }

    /// 恢复任务 (仅用于从持久化恢复，不立即执行)
    func restore(task: StorageTransferTask, status: String, progress: Double) {
        let idStr = task.id.uuidString
        state.withCriticalRegion { $0.tasks[idStr] = task }
        // 初始化状态
        taskUpdates[idStr] = (status, progress, "")
    }
    
    /// 获取所有任务详情 (用于 UI 恢复)
    func getAllTasks() -> [StorageTransferTask] {
        state.withCriticalRegion { Array($0.tasks.values) }
    }
    
    // MARK: - Private Methods

    static func resolveUploadIdentity(currentUser: UserDO?) throws -> UploadIdentity {
        guard let currentUser else {
            throw FileTransferError.serverError("登录状态已失效，请重新登录")
        }
        guard let userId = Int32(exactly: currentUser.id) else {
            throw FileTransferError.serverError("当前用户ID超出文件传输协议范围")
        }
        return UploadIdentity(userId: userId, userName: currentUser.username)
    }
    
    /// 调度下一个任务
    private func scheduleNext() {
        let decision = state.withCriticalRegion { state -> (activeCount: Int, pendingCount: Int, task: StorageTransferTask?) in
            let activeCount = state.activeTasks.count
            let pendingCount = state.pendingQueue.count
            
            guard activeCount < maxConcurrentTasks else {
                return (activeCount, pendingCount, nil)
            }
            
            guard let task = state.pendingQueue.first else {
                return (activeCount, pendingCount, nil)
            }
            
            state.pendingQueue.removeFirst()
            return (activeCount, pendingCount, task)
        }
        
        print("📅 [scheduleNext] 被调用 - 当前 activeTasks: \(decision.activeCount)/\(maxConcurrentTasks), pendingQueue: \(decision.pendingCount)")
        
        guard let task = decision.task else {
            if decision.activeCount >= maxConcurrentTasks {
                print("⚠️ [scheduleNext] 已达到最大并发限制")
            } else {
                print("ℹ️ [scheduleNext] pendingQueue 为空，无任务可调度")
            }
            return
        }
        
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
                var completedUploadFileId: Int64?
                
                // 获取当前主连接的 Host
                let (currentHost, _) = SocketManager.shared.getCurrentServer()
                
                // 根据任务类型选择端口
                let transferPort: UInt32 = task.taskType == .upload ? 10087 : 10088
                print("📡 连接到传输端口: \(transferPort) (\(task.taskType == .upload ? "上传" : "下载"))")
                
                // 执行传输逻辑
                if task.taskType == .upload {
                    // 上传连接的首次建立和传输中重连统一由恢复状态机负责。
                    isSocketConnected = true
                    let uploadIdentity = try Self.resolveUploadIdentity(
                        currentUser: AuthenticationService.shared.currentUser
                    )
                    let uploadedFileId = try await self.uploadWithRecovery(
                        task: task,
                        taskId: idStr,
                        identity: uploadIdentity,
                        socketManager: socketManager,
                        host: currentHost,
                        port: transferPort
                    )
                    completedUploadFileId = uploadedFileId
                    // [修改] 上传完成后将 taskId-key 缩略图迁移到 fileId-key，供文件列表直接命中。
                    // 缩略图已在 submit 时生成（不依赖 fileId），此处仅做磁盘文件重命名。
                    if let newFileId = uploadedFileId, newFileId > 0 {
                        let taskId = idStr
                        Task {
                            await FileThumbnailService.shared.remapToFileId(taskId: taskId, fileId: newFileId)
                        }
                    } else {
                        let taskId = idStr
                        Task {
                            await FileThumbnailService.shared.markUploadSucceeded(taskId: taskId, fileId: nil)
                        }
                        print("[Thumbnail] 服务端未返回 fileId，跳过 remap（缩略图保留在 taskId-key）")
                    }
                } else {
                    try await Self.connectTransferSocket(
                        socketManager,
                        host: currentHost,
                        port: transferPort
                    )
                    isSocketConnected = true
                    print("✅ 传输连接已建立: \(transferPort)")

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
                if Self.shouldPostFileListRefresh(for: task.taskType) {
                    let notificationFileId = completedUploadFileId
                    let notificationTargetDirId = task.targetDirId
                    await MainActor.run {
                        var userInfo: [String: Any] = [
                            "taskId": idStr,
                            "targetDirId": notificationTargetDirId
                        ]
                        if let fileId = notificationFileId {
                            userInfo["fileId"] = fileId
                        }
                        NotificationCenter.default.post(
                            name: .uploadTaskDidComplete,
                            object: nil,
                            userInfo: userInfo
                        )
                    }
                }
                
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
            self.state.withCriticalRegion { $0.activeTasks.removeValue(forKey: idStr) }
            
            // 调度下一个
            self.scheduleNext()
        }
        
        state.withCriticalRegion { $0.activeTasks[idStr] = executionTask }
    }

    private func uploadWithRecovery(
        task: StorageTransferTask,
        taskId: String,
        identity: UploadIdentity,
        socketManager: SocketManager,
        host: String,
        port: UInt32
    ) async throws -> Int64? {
        let maxRecoveryAttempts = 3
        var recoveryAttempt = 0

        while true {
            do {
                if socketManager.connectionState != .connected {
                    try await Self.connectTransferSocket(socketManager, host: host, port: port)
                    print("✅ 上传连接已建立: \(port)")
                }
                let service = FileTransferService(socketManager: socketManager)
                let startOffset = getUploadedBytes(taskId: taskId)
                print("🔄 从数据库读取上传断点: \(startOffset) bytes")

                return try await service.uploadFile(
                    fileUrl: task.fileUrl,
                    targetDirId: task.targetDirId,
                    userId: identity.userId,
                    userName: identity.userName,
                    taskId: taskId,
                    startOffset: startOffset,
                    progressHandler: { progress, speed in
                        self.updateTaskProgress(id: taskId, progress: progress, speed: speed)
                    },
                    statusHandler: { status in
                        self.updateTaskStatus(id: taskId, status: status)
                    }
                )
            } catch {
                guard Self.isRecoverableUploadError(error),
                      recoveryAttempt < maxRecoveryAttempts else {
                    throw error
                }

                recoveryAttempt += 1
                updateTaskStatus(id: taskId, status: "网络恢复中")
                print("🔄 上传连接异常，准备断点重连: attempt=\(recoveryAttempt)/\(maxRecoveryAttempts), error=\(error)")

                await MainActor.run {
                    socketManager.disconnect(notifyUI: false)
                }
                let delayMilliseconds = 500 * (1 << (recoveryAttempt - 1))
                try await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            }
        }
    }

    private static func connectTransferSocket(
        _ socketManager: SocketManager,
        host: String,
        port: UInt32
    ) async throws {
        await MainActor.run {
            socketManager.disconnect(notifyUI: false)
            socketManager.connect(host: host, port: port)
        }

        var attempts = 0
        while socketManager.connectionState != .connected {
            try Task.checkCancellation()
            if attempts > 50 {
                print("❌ 连接超时: \(port), 状态: \(socketManager.connectionState)")
                throw FileTransferError.connectionLost
            }
            if case .error(let message) = socketManager.connectionState {
                print("❌ 连接错误: \(message) on port \(port)")
                throw FileTransferError.connectionLost
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
    }

    static func isRecoverableUploadError(_ error: Error) -> Bool {
        if let transferError = error as? FileTransferError {
            if case .connectionLost = transferError {
                return true
            }
            if case .invalidFinalFileId = transferError {
                return true
            }
            return false
        }
        guard let socketError = error as? SocketError else {
            return false
        }
        switch socketError {
        case .connectionFailed, .notConnected, .sendFailed, .timeout, .connectionClosed:
            return true
        case .invalidResponse, .unknown:
            return false
        }
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
