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

class PersistenceManager {
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
        userName: String? = "default",
        status: String? = nil,
        progress: Double? = nil,
        uploadedBytes: Int64? = nil,
        md5: String? = nil
    ) {
        context.perform {
            let entity = self.fetchEntity(taskId: taskId) ?? TransferTaskEntity(context: self.context)
            entity.taskId = taskId
            
            if let fileUrl = fileUrl {
                print("💾 Persistence: Attempting to create bookmark for \(fileUrl.path)")
                // Save Security-Scoped Bookmark
                do {
                    let bookmark = try fileUrl.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    entity.fileUrl = bookmark
                    print("✅ Persistence: Bookmark created successfully (\(bookmark.count) bytes)")
                } catch {
                    print("❌ Failed to create bookmark for \(fileUrl): \(error)")
                }
            } else {
                 if entity.fileUrl == nil {
                     print("⚠️ Persistence: saveTask called without fileUrl and entity has no existing bookmark.")
                 }
            }
            if let fileName = fileName { entity.fileName = fileName }
            if let fileSize = fileSize { entity.fileSize = fileSize }
            if let targetDirId = targetDirId { entity.targetDirId = targetDirId }
            if let userId = userId { entity.userId = userId }
            if let userName = userName { entity.userName = userName }
            if let status = status { entity.status = status }
            if let progress = progress { entity.progress = progress }
            if let uploadedBytes = uploadedBytes { entity.uploadedBytes = uploadedBytes }
            if let md5 = md5 { entity.md5 = md5 }
            
            if entity.timestamp == nil {
                entity.timestamp = Date()
            }
            
            self.saveContext()
        }
    }
    
    /// Update progress lightly to avoid overhead
    func updateProgress(taskId: String, progress: Double, uploadedBytes: Int64, status: String = "Uploading") {
        context.perform {
            if let entity = self.fetchEntity(taskId: taskId) {
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
            if let entity = self.fetchEntity(taskId: taskId) {
                entity.status = status
                self.saveContext()
            }
        }
    }
    
    /// Fetch pending tasks (Waiting, Uploading, Paused, Failed)
    func fetchPendingTasks() -> [TransferTaskEntity] {
        let request: NSFetchRequest<TransferTaskEntity> = TransferTaskEntity.fetchRequest()
        // Fetch all except Completed
        request.predicate = NSPredicate(format: "status != %@", "Completed")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ Failed to fetch pending tasks: \(error)")
            return []
        }
    }
    
    func deleteTask(taskId: String) {
        context.perform {
            if let entity = self.fetchEntity(taskId: taskId) {
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
            let request: NSFetchRequest<TransferTaskEntity> = TransferTaskEntity.fetchRequest()
            request.predicate = NSPredicate(format: "taskId == %@", taskId)
            request.fetchLimit = 1
            
            do {
                result = try context.fetch(request).first
            } catch {
                print("❌ Error fetching task \(taskId): \(error)")
                result = nil
            }
        }
        
        return result
    }
    
    private func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("❌ Core Data Save Error: \(error)")
            }
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
