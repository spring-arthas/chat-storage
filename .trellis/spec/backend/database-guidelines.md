# Database Guidelines

> Core Data usage conventions for this project.

---

## Overview

Core Data is used **only** to persist `TransferTaskEntity` records — the in-progress/pending upload-download queue. It is NOT used for main file data (which lives on the remote server) or user data.

The stack is initialized in `Persistence.swift` using `NSPersistentCloudKitContainer`.

---

## Access Pattern

All Core Data access goes through `PersistenceManager.shared` (defined in `Persistence.swift`). Never access `NSManagedObjectContext` directly from a service or view.

```swift
// Correct
PersistenceManager.shared.saveTask(taskId: id, fileName: name, ...)
PersistenceManager.shared.updateProgress(taskId: id, progress: 0.5, uploadedBytes: 512)

// Wrong: never access context directly from outside PersistenceManager
PersistenceController.shared.container.viewContext.fetch(...)
```

---

## Query Patterns

Use typed `NSFetchRequest` with `NSPredicate`:

```swift
let request: NSFetchRequest<TransferTaskEntity> = TransferTaskEntity.fetchRequest()
request.predicate = NSPredicate(format: "status != %@", "Completed")
request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
```

- Use `context.perform { }` for async access
- Use `context.performAndWait { }` when a synchronous result is needed (e.g., `fetchEntity(taskId:)`)

---

## File URL Persistence (Security-Scoped Bookmarks)

File paths are stored as **security-scoped bookmarks**, not plain URL strings. This is required for macOS sandbox compliance.

```swift
// Save: convert URL → bookmark Data
let bookmark = try fileUrl.bookmarkData(options: .withSecurityScope, ...)
entity.fileUrl = bookmark

// Load: convert bookmark Data → URL
let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, ...)
```

Always use `PersistenceManager.resolveBookmark(data:)` — never inline this logic elsewhere.

---

## Download Task Identification

Download tasks are identified by a special marker in the `md5` field:

```
md5 = "DOWNLOAD_FILE_ID_<remoteFileId>"
// Example: "DOWNLOAD_FILE_ID_12345"
```

`TransferTaskManager` reads this marker on launch to distinguish upload vs download tasks when restoring from Core Data.

---

## Status Values

| Value | Meaning |
|-------|---------|
| `"等待中"` | Queued, not yet started |
| `"已暂停"` | Paused (restored from DB) |
| `"Uploading"` / `"Downloading"` | Active transfer |
| `"Completed"` / `"已完成"` | Done — eligible for cleanup |
| `"Failed"` | Error state |

`deleteCompletedTasks()` matches both `"Completed"` and `"已完成"` — always handle both variants.

---

## Migrations

No migration scripts. Core Data model changes require opening `chat_storage.xcdatamodeld` in Xcode and adding a new model version. Lightweight migration is enabled via `automaticallyMergesChangesFromParent = true`.

---

## Common Mistakes

- **Accessing context on wrong thread**: Always wrap in `context.perform { }`.
- **Storing plain URL string**: File URLs must be security-scoped bookmarks. Use `PersistenceManager.saveTask(fileUrl:...)`.
- **Using Core Data for file content**: Core Data holds only task metadata. File content lives on the remote server.
- **Forgetting both status strings**: `"Completed"` and `"已完成"` are both in use — match both when filtering.
