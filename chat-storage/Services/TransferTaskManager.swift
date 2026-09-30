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
    /// [修改] 同时发布阶段、进度、速度、已传字节和失败原因。
    @Published var taskUpdates: [String: TransferTaskUpdate] = [:]
    
    // MARK: - Private Properties
    
    /// 最大并发数
    private let maxConcurrentTasks: Int
    private let persistence: TransferTaskPersisting
    private let controlSocketManager: SocketManager
    private let authenticationService: AuthenticationService
    private let transferSocketFactory: () -> SocketManager
    
    /// 任务状态 (async-safe)
    private struct TaskState {
        var activeTasks: [String: Task<Void, Never>] = [:]
        var pendingQueue: [StorageTransferTask] = []
        var tasks: [String: StorageTransferTask] = [:]
    }
    
    private let state = ManagedCriticalState(TaskState())
    
    init(
        persistence: TransferTaskPersisting = PersistenceManager.shared,
        maxConcurrentTasks: Int = 5,
        restorePersistedTasks: Bool = true,
        controlSocketManager: SocketManager = .shared,
        authenticationService: AuthenticationService = .shared,
        transferSocketFactory: @escaping () -> SocketManager = { SocketManager() }
    ) {
        self.persistence = persistence
        self.maxConcurrentTasks = max(0, maxConcurrentTasks)
        self.controlSocketManager = controlSocketManager
        self.authenticationService = authenticationService
        self.transferSocketFactory = transferSocketFactory
        if restorePersistedTasks {
            restoreTasksFromDatabase()
        }
    }
    
    /// 从数据库恢复任务
    private func restoreTasksFromDatabase() {
        let records = persistence.loadPendingTasks()
        print("📥 从数据库恢复 \(records.count) 个任务")

        for record in records {
            let task = record.task
            let taskId = task.id.uuidString
            let stage = TransferTaskStage.resolve(task.status, taskType: task.taskType)
            state.withCriticalRegion { $0.tasks[taskId] = task }
            taskUpdates[taskId] = TransferTaskUpdate(
                stage: stage,
                progress: task.progress,
                speed: "",
                transferredBytes: record.transferredBytes,
                errorMessage: record.errorMessage
            )
            print("✅ 恢复任务: \(task.name), 进度: \(Int(task.progress * 100))%")
        }

        let restoredCount = state.withCriticalRegion { $0.tasks.count }
        print("✅ 成功恢复 \(restoredCount) 个任务")
    }
    
    // MARK: - Public Methods
    
    /// 提交任务
    /// - Parameter task: 传输任务
    func submit(task: StorageTransferTask) {
        let id = task.id.uuidString
        let queuedStage = TransferTaskStage.queued(for: task.taskType)
        var queuedTask = task
        queuedTask.status = queuedStage.rawValue

        // [修改] 必须先同步落库再进入调度队列，上传端口连接失败时任务仍然存在。
        do {
            try persistence.persistInitialTask(queuedTask, stage: queuedStage)
        } catch {
            state.withCriticalRegion { $0.tasks[id] = queuedTask }
            publishTaskUpdate(
                id: id,
                update: TransferTaskUpdate(
                    stage: .failed,
                    progress: queuedTask.progress,
                    speed: "",
                    transferredBytes: 0,
                    errorMessage: "建立本地传输任务失败：\(error.localizedDescription)"
                )
            )
            print("❌ [提交任务] 本地持久化失败: \(error.localizedDescription)")
            return
        }

        let counts = state.withCriticalRegion { state -> (pendingCount: Int, activeCount: Int) in
            state.tasks[id] = queuedTask
            state.pendingQueue.append(queuedTask)
            return (state.pendingQueue.count, state.activeTasks.count)
        }

        publishTaskUpdate(
            id: id,
            update: TransferTaskUpdate(
                stage: queuedStage,
                progress: queuedTask.progress,
                speed: "",
                transferredBytes: Int64(Double(queuedTask.fileSize) * queuedTask.progress),
                errorMessage: nil
            )
        )

        print("✅ [提交任务] ID: \(id), Name: \(queuedTask.name)")
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
            updateTaskStatus(id: idStr, stage: .paused)
        }
        
        if removedPending {
            updateTaskStatus(id: idStr, stage: .paused)
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
        updateTaskStatus(id: idStr, stage: .queued(for: task.taskType), errorMessage: nil)
        
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
        persistence.deleteTask(taskId: idStr)
    }
    
    /// 清除所有已完成的任务 (内存 + 数据库)
    func clearCompletedTasks() {
        let idsToRemove = state.withCriticalRegion { state -> [String] in
            var ids: [String] = []
            for (id, task) in state.tasks {
                if let update = taskUpdates[id], update.stage.isCompleted {
                    ids.append(id)
                } else if TransferTaskStage.resolve(task.status, taskType: task.taskType).isCompleted {
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
        persistence.deleteCompletedTasks()
    }

    /// 恢复任务 (仅用于从持久化恢复，不立即执行)
    func restore(task: StorageTransferTask, status: String, progress: Double) {
        let idStr = task.id.uuidString
        state.withCriticalRegion { $0.tasks[idStr] = task }
        // 初始化状态
        taskUpdates[idStr] = TransferTaskUpdate(
            stage: TransferTaskStage.resolve(status, taskType: task.taskType),
            progress: progress,
            speed: "",
            transferredBytes: persistence.transferredBytes(taskId: idStr),
            errorMessage: nil
        )
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
        updateTaskStatus(id: idStr, stage: .connecting, errorMessage: nil)
        
        let executionTask = Task {
            // 创建独立的 SocketManager 实例用于文件传输
            let socketManager = self.transferSocketFactory()
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
                let (currentHost, currentControlPort) = self.controlSocketManager.getCurrentServer()
                let configuration = ServerEndpointStore.resolvedConfiguration(
                    for: ServerEndpoint(host: currentHost, port: currentControlPort)
                )

                // [修改] 上传和下载端口来自持久化配置，不再固定写死 10087/10088。
                let transferPort = task.taskType == .upload
                    ? configuration.uploadPort
                    : configuration.downloadPort
                print("📡 连接到传输端口: \(transferPort) (\(task.taskType == .upload ? "上传" : "下载"))")
                
                // 执行传输逻辑
                if task.taskType == .upload {
                    // 上传连接的首次建立和传输中重连统一由恢复状态机负责。
                    isSocketConnected = true
                    let uploadIdentity = try Self.resolveUploadIdentity(
                        currentUser: self.authenticationService.currentUser
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
                    self.updateTaskStatus(id: idStr, stage: .downloading)

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
                self.updateTaskStatus(id: idStr, stage: .completed, progress: 1.0)
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
                    self.updateTaskStatus(id: idStr, stage: .paused)
                } else {
                    print("❌ 任务失败 [\(task.name)]: \(error)")
                    self.updateTaskStatus(
                        id: idStr,
                        stage: .failed,
                        errorMessage: error.localizedDescription
                    )
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
                    updateTaskStatus(id: taskId, stage: .connecting)
                    try await Self.connectTransferSocket(socketManager, host: host, port: port)
                    print("✅ 上传连接已建立: \(port)")
                }
                let service = FileTransferService(socketManager: socketManager)
                let startOffset = getUploadedBytes(taskId: taskId)
                print("🔄 从数据库读取上传断点: \(startOffset) bytes")
                if task.fileSize > 0, startOffset > 0 {
                    updateTaskProgress(
                        id: taskId,
                        progress: Double(startOffset) / Double(task.fileSize),
                        speed: "-"
                    )
                }

                return try await service.uploadFile(
                    fileUrl: task.fileUrl,
                    targetDirId: task.targetDirId,
                    userId: identity.userId,
                    userName: identity.userName,
                    taskId: taskId,
                    startOffset: startOffset,
                    directoryFullPath: task.directoryFullPath,
                    progressHandler: { progress, speed in
                        self.updateTaskProgress(id: taskId, progress: progress, speed: speed)
                    },
                    statusHandler: { status in
                        self.updateTaskStatus(
                            id: taskId,
                            stage: TransferTaskStage.resolve(status, taskType: .upload)
                        )
                    }
                )
            } catch {
                guard Self.isRecoverableUploadError(error),
                      recoveryAttempt < maxRecoveryAttempts else {
                    throw error
                }

                recoveryAttempt += 1
                updateTaskStatus(
                    id: taskId,
                    stage: .recovering,
                    errorMessage: error.localizedDescription
                )
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
        case .invalidResponse, .serverError(_), .unknown:
            return false
        }
    }
    
    // MARK: - Database Helpers
    
    /// 从数据库获取已上传/下载字节数
    private func getUploadedBytes(taskId: String) -> Int64 {
        persistence.transferredBytes(taskId: taskId)
    }
    
    /// 从数据库获取已下载字节数
    private func getDownloadedBytes(taskId: String) -> Int64 {
        // 使用同一个 uploadedBytes 字段存储已下载字节数
        return getUploadedBytes(taskId: taskId)
    }
    
    // MARK: - Status Updates
    
    private func updateTaskStatus(
        id: String,
        stage: TransferTaskStage,
        progress: Double? = nil,
        errorMessage: String? = nil
    ) {
        let snapshot = state.withCriticalRegion { state -> (progress: Double, fileSize: Int64) in
            guard var task = state.tasks[id] else {
                return (progress ?? 0, 0)
            }
            task.status = stage.rawValue
            if let progress {
                task.progress = min(1, max(0, progress))
            }
            state.tasks[id] = task
            return (task.progress, task.fileSize)
        }
        let transferredBytes = stage.isCompleted
            ? snapshot.fileSize
            : min(snapshot.fileSize, max(0, persistence.transferredBytes(taskId: id)))
        persistence.updateTask(
            taskId: id,
            stage: stage,
            progress: snapshot.progress,
            transferredBytes: transferredBytes,
            errorMessage: errorMessage
        )

        DispatchQueue.main.async {
            var current = self.taskUpdates[id] ?? TransferTaskUpdate(
                stage: stage,
                progress: snapshot.progress,
                speed: "",
                transferredBytes: transferredBytes,
                errorMessage: nil
            )
            current.stage = stage
            current.progress = snapshot.progress
            current.transferredBytes = transferredBytes
            current.errorMessage = errorMessage
            if stage == .completed || stage == .failed || stage == .paused {
                current.speed = ""
            }
            self.taskUpdates[id] = current
        }
    }
    
    private func updateTaskProgress(id: String, progress: Double, speed: String) {
        let normalizedProgress = min(1, max(0, progress))
        let snapshot = state.withCriticalRegion { state -> (stage: TransferTaskStage, fileSize: Int64) in
            guard var task = state.tasks[id] else {
                return (.uploading, 0)
            }
            task.progress = normalizedProgress
            state.tasks[id] = task
            return (
                TransferTaskStage.resolve(task.status, taskType: task.taskType),
                task.fileSize
            )
        }
        let transferredBytes = min(
            snapshot.fileSize,
            max(0, Int64(Double(snapshot.fileSize) * normalizedProgress))
        )
        persistence.updateTask(
            taskId: id,
            stage: snapshot.stage,
            progress: normalizedProgress,
            transferredBytes: transferredBytes,
            errorMessage: nil
        )

        DispatchQueue.main.async {
            var current = self.taskUpdates[id] ?? TransferTaskUpdate(
                stage: snapshot.stage,
                progress: normalizedProgress,
                speed: speed,
                transferredBytes: transferredBytes,
                errorMessage: nil
            )
            current.stage = snapshot.stage
            current.progress = normalizedProgress
            current.speed = speed
            current.transferredBytes = transferredBytes
            current.errorMessage = nil
            self.taskUpdates[id] = current
        }
    }

    private func publishTaskUpdate(id: String, update: TransferTaskUpdate) {
        if Thread.isMainThread {
            taskUpdates[id] = update
        } else {
            DispatchQueue.main.async {
                self.taskUpdates[id] = update
            }
        }
    }
}
