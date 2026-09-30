//
//  Persistence.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/29.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "chat_storage")
        
        // 打印数据库位置
        if let url = container.persistentStoreDescriptions.first?.url {
            print("💾 SQLite Database Path: \(url.path)")
        }
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

// MARK: - PersistenceManager (Merged)

import Foundation

class PersistenceManager: TransferTaskPersisting {
    static let shared = PersistenceManager()
    
    private let context: NSManagedObjectContext
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }
    
    // MARK: - Task Management
    
    /// Create or Update a Transfer Task
    func saveTask(
        taskId: String,
        fileUrl: URL? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        targetDirId: Int64? = nil,
        userId: Int32? = nil,
        userName: String? = nil,
        status: String? = nil,
        progress: Double? = nil,
        uploadedBytes: Int64? = nil,
        md5: String? = nil,
        directoryFullPath: String? = nil,
        errorMessage: String? = nil
    ) {
        do {
            try saveTaskNow(
                taskId: taskId,
                fileUrl: fileUrl,
                fileName: fileName,
                fileSize: fileSize,
                targetDirId: targetDirId,
                userId: userId,
                userName: userName,
                status: status,
                progress: progress,
                uploadedBytes: uploadedBytes,
                md5: md5,
                directoryFullPath: directoryFullPath,
                errorMessage: errorMessage
            )
        } catch {
            print("❌ Core Data 保存传输任务失败, taskId=\(taskId), error=\(error.localizedDescription)")
        }
    }

    private func saveTaskNow(
        taskId: String,
        fileUrl: URL? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        targetDirId: Int64? = nil,
        userId: Int32? = nil,
        userName: String? = nil,
        status: String? = nil,
        progress: Double? = nil,
        uploadedBytes: Int64? = nil,
        md5: String? = nil,
        directoryFullPath: String? = nil,
        errorMessage: String? = nil
    ) throws {
        var operationError: Error?
        context.performAndWait {
            do {
                let entity = try self.fetchEntityInContext(taskId: taskId)
                    ?? TransferTaskEntity(context: self.context)
                entity.taskId = taskId

                if let fileUrl {
                    print("💾 Persistence: Attempting to create bookmark for \(fileUrl.path)")
                    let bookmark = try fileUrl.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    entity.fileUrl = bookmark
                    print("✅ Persistence: Bookmark created successfully (\(bookmark.count) bytes)")
                } else if entity.fileUrl == nil {
                    print("⚠️ Persistence: saveTask called without fileUrl and entity has no existing bookmark.")
                }
                if let fileName { entity.fileName = fileName }
                if let fileSize { entity.fileSize = fileSize }
                if let targetDirId { entity.targetDirId = targetDirId }
                if let userId { entity.userId = userId }
                if let userName { entity.userName = userName }
                if let status { entity.status = status }
                if let progress { entity.progress = progress }
                if let uploadedBytes { entity.uploadedBytes = uploadedBytes }
                if let md5 { entity.md5 = md5 }
                if let directoryFullPath { entity.directoryFullPath = directoryFullPath }
                if let errorMessage { entity.errorMessage = errorMessage }

                if entity.timestamp == nil {
                    entity.timestamp = Date()
                }
                try self.saveContextNow()
            } catch {
                operationError = error
            }
        }
        if let operationError {
            throw operationError
        }
    }

    // MARK: - TransferTaskPersisting

    func loadPendingTasks() -> [PersistedTransferTaskRecord] {
        var records: [PersistedTransferTaskRecord] = []
        context.performAndWait {
            let request: NSFetchRequest<TransferTaskEntity> = TransferTaskEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "status != %@ AND status != %@",
                TransferTaskStage.completed.rawValue,
                "Completed"
            )
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

            do {
                let entities = try self.context.fetch(request)
                records = entities.compactMap { entity in
                    guard let taskIdString = entity.taskId,
                          let taskId = UUID(uuidString: taskIdString),
                          let fileName = entity.fileName,
                          let bookmark = entity.fileUrl,
                          let fileURL = self.resolveBookmark(data: bookmark) else {
                        return nil
                    }

                    let isDownload = entity.md5?.hasPrefix("DOWNLOAD_FILE_ID_") == true
                    let taskType: TransferTaskType = isDownload ? .download : .upload
                    let remoteFileId = isDownload
                        ? Int64(entity.md5?.split(separator: "_").last ?? "") ?? 0
                        : 0
                    let byteProgress = entity.fileSize > 0
                        ? Double(entity.uploadedBytes) / Double(entity.fileSize)
                        : 0
                    let progress = min(1, max(entity.progress, byteProgress))
                    let stage = TransferTaskStage.resolve(
                        entity.status ?? "",
                        taskType: taskType
                    )
                    let restoredStage = stage.isActive ? TransferTaskStage.paused : stage
                    let task = StorageTransferTask(
                        id: taskId,
                        taskType: taskType,
                        name: fileName,
                        fileUrl: fileURL,
                        targetDirId: entity.targetDirId,
                        userId: Int64(entity.userId),
                        userName: entity.userName ?? "",
                        fileSize: entity.fileSize,
                        directoryName: "",
                        directoryFullPath: entity.directoryFullPath ?? "",
                        remoteFileId: remoteFileId,
                        progress: progress,
                        status: restoredStage.rawValue
                    )
                    return PersistedTransferTaskRecord(
                        task: task,
                        transferredBytes: entity.uploadedBytes,
                        errorMessage: entity.errorMessage
                    )
                }
            } catch {
                print("❌ 读取待恢复传输任务失败: \(error.localizedDescription)")
                records = []
            }
        }
        return records
    }

    func persistInitialTask(_ task: StorageTransferTask, stage: TransferTaskStage) throws {
        guard let userId = Int32(exactly: task.userId) else {
            throw FileTransferError.serverError("当前用户ID超出文件传输协议范围")
        }
        let downloadMarker = task.taskType == .download
            ? "DOWNLOAD_FILE_ID_\(task.remoteFileId)"
            : nil
        try saveTaskNow(
            taskId: task.id.uuidString,
            fileUrl: task.fileUrl,
            fileName: task.name,
            fileSize: task.fileSize,
            targetDirId: task.targetDirId,
            userId: userId,
            userName: task.userName,
            status: stage.rawValue,
            progress: task.progress,
            uploadedBytes: Int64(Double(task.fileSize) * task.progress),
            md5: downloadMarker,
            directoryFullPath: task.directoryFullPath
        )
    }

    func updateTask(
        taskId: String,
        stage: TransferTaskStage,
        progress: Double,
        transferredBytes: Int64,
        errorMessage: String?
    ) {
        context.performAndWait {
            do {
                guard let entity = try self.fetchEntityInContext(taskId: taskId) else { return }
                entity.status = stage.rawValue
                entity.progress = min(1, max(0, progress))
                entity.uploadedBytes = max(0, transferredBytes)
                entity.errorMessage = errorMessage
                try self.saveContextNow()
            } catch {
                print("❌ 更新传输任务失败, taskId=\(taskId), error=\(error.localizedDescription)")
            }
        }
    }

    func transferredBytes(taskId: String) -> Int64 {
        fetchEntity(taskId: taskId)?.uploadedBytes ?? 0
    }
    
    /// Update progress lightly to avoid overhead
    func updateProgress(taskId: String, progress: Double, uploadedBytes: Int64, status: String = "Uploading") {
        context.perform {
            if let entity = try? self.fetchEntityInContext(taskId: taskId) {
                entity.progress = progress
                entity.uploadedBytes = uploadedBytes
                entity.status = status
                self.saveContext()
            }
        }
    }
    
    /// Update status only
    func updateStatus(taskId: String, status: String) {
        context.perform {
            if let entity = try? self.fetchEntityInContext(taskId: taskId) {
                entity.status = status
                self.saveContext()
            }
        }
    }
    
    /// Fetch pending tasks (Waiting, Uploading, Paused, Failed)
    func fetchPendingTasks() -> [TransferTaskEntity] {
        let request: NSFetchRequest<TransferTaskEntity> = TransferTaskEntity.fetchRequest()
        // [修改] 中英文完成状态都不能被恢复成待处理任务。
        request.predicate = NSPredicate(
            format: "status != %@ AND status != %@",
            "Completed",
            TransferTaskStage.completed.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        var result: [TransferTaskEntity] = []
        context.performAndWait {
            do {
                result = try context.fetch(request)
            } catch {
                print("❌ Failed to fetch pending tasks: \(error)")
                result = []
            }
        }
        return result
    }
    
    func deleteTask(taskId: String) {
        context.perform {
            if let entity = try? self.fetchEntityInContext(taskId: taskId) {
                self.context.delete(entity)
                self.saveContext()
            }
        }
    }
    
    /// Delete all completed tasks (status: "Completed" or "已完成")
    func deleteCompletedTasks() {
        context.perform {
            let request: NSFetchRequest<TransferTaskEntity> = TransferTaskEntity.fetchRequest()
            // 匹配两种状态: 英文 "Completed" 和 中文 "已完成"
            request.predicate = NSPredicate(format: "status == %@ OR status == %@", "Completed", "已完成")
            
            do {
                let entities = try self.context.fetch(request)
                if !entities.isEmpty {
                    for entity in entities {
                        self.context.delete(entity)
                    }
                    self.saveContext()
                    print("💾 Persistence: 已删除 \(entities.count) 个已完成任务")
                } else {
                    print("💾 Persistence: 没有已完成的任务需要删除")
                }
            } catch {
                print("❌ Failed to delete completed tasks: \(error)")
            }
        }
    }
    
    // MARK: - Helpers
    
    /// 获取任务实体（公开方法供 TransferTaskManager 访问，线程安全）
    func fetchEntity(taskId: String) -> TransferTaskEntity? {
        var result: TransferTaskEntity?
        
        // 使用 performAndWait 确保在正确的队列上执行，避免线程安全问题
        context.performAndWait {
            do {
                result = try self.fetchEntityInContext(taskId: taskId)
            } catch {
                print("❌ Error fetching task \(taskId): \(error)")
                result = nil
            }
        }
        
        return result
    }

    private func fetchEntityInContext(taskId: String) throws -> TransferTaskEntity? {
        let request: NSFetchRequest<TransferTaskEntity> = TransferTaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", taskId)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    private func saveContext() {
        if context.hasChanges {
            do {
                try saveContextNow()
            } catch {
                print("❌ Core Data Save Error: \(error)")
            }
        }
    }

    private func saveContextNow() throws {
        if context.hasChanges {
            try context.save()
        }
    }
    
    /// Resolve Bookmark to URL
    func resolveBookmark(data: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                print("⚠️ Bookmark data is stale")
            }
            return url
        } catch {
            print("❌ Failed to resolve bookmark: \(error)")
            return nil
        }
    }
}
