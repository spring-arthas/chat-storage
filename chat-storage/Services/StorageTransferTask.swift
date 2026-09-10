//
//  StorageTransferTask.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/7.
//

import Foundation

// MARK: - Transfer Models

/// 传输任务类型
public enum TransferTaskType: String, Codable {
    case upload
    case download
}

/// 传输中心统一阶段。
/// [修改] UI、任务调度和持久化共用同一套状态，避免连接/校验阶段被误判成“没有上传”。
enum TransferTaskStage: String, Codable, CaseIterable {
    case queuedUpload = "等待上传"
    case queuedDownload = "等待下载"
    case connecting = "连接传输服务"
    case hashing = "计算文件校验"
    case resumeChecking = "检查上传断点"
    case metadataHandshake = "建立服务端任务"
    case uploading = "上传中"
    case downloading = "下载中"
    case waitingForServer = "等待服务端"
    case verifying = "校验中"
    case recovering = "网络恢复中"
    case paused = "已暂停"
    case completed = "已完成"
    case failed = "失败"

    var isActive: Bool {
        switch self {
        case .queuedUpload, .queuedDownload, .connecting, .hashing, .resumeChecking,
             .metadataHandshake, .uploading, .downloading, .waitingForServer,
             .verifying, .recovering:
            return true
        case .paused, .completed, .failed:
            return false
        }
    }

    var canResume: Bool {
        self == .paused || self == .failed
    }

    var isCompleted: Bool {
        self == .completed
    }

    var isFailed: Bool {
        self == .failed
    }

    static func queued(for taskType: TransferTaskType) -> TransferTaskStage {
        taskType == .upload ? .queuedUpload : .queuedDownload
    }

    static func resolve(_ status: String, taskType: TransferTaskType? = nil) -> TransferTaskStage {
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = TransferTaskStage(rawValue: trimmed) {
            return exact
        }

        switch trimmed.lowercased() {
        case "waiting", "pending", "queued":
            return queued(for: taskType ?? .upload)
        case "hashing":
            return .hashing
        case "uploading":
            return .uploading
        case "downloading":
            return .downloading
        case "paused", "pause", "暂停":
            return .paused
        case "completed", "complete", "success":
            return .completed
        case "failed", "failure", "error":
            return .failed
        case "连接服务器":
            return .connecting
        case "断点检查":
            return .resumeChecking
        case "元数据握手":
            return .metadataHandshake
        case "数据发送", "进度确认":
            return .uploading
        case "完整性校验与最终确认":
            return .verifying
        default:
            if trimmed.contains("失败") || trimmed.contains("错误") {
                return .failed
            }
            return queued(for: taskType ?? .upload)
        }
    }
}

/// 传输任务对 UI 的完整更新。
/// [修改] 除进度和速度外保留已传字节与失败原因，让传输中心能证明文件流是否真的在发送。
struct TransferTaskUpdate: Equatable {
    var stage: TransferTaskStage
    var progress: Double
    var speed: String
    var transferredBytes: Int64
    var errorMessage: String?

    var status: String {
        stage.rawValue
    }
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

/// 从持久层恢复任务时使用的稳定快照，避免把 NSManagedObject 带出 Core Data 队列。
struct PersistedTransferTaskRecord {
    let task: StorageTransferTask
    let transferredBytes: Int64
    let errorMessage: String?
}

/// 传输任务持久化接口。
/// [修改] TransferTaskManager 可注入内存实现做回归测试，正式环境仍使用 Core Data。
protocol TransferTaskPersisting: AnyObject {
    func loadPendingTasks() -> [PersistedTransferTaskRecord]
    func persistInitialTask(_ task: StorageTransferTask, stage: TransferTaskStage) throws
    func updateTask(
        taskId: String,
        stage: TransferTaskStage,
        progress: Double,
        transferredBytes: Int64,
        errorMessage: String?
    )
    func transferredBytes(taskId: String) -> Int64
    func deleteTask(taskId: String)
    func deleteCompletedTasks()
}
