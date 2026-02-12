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
