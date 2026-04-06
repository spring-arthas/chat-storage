# 数据库规范

> 当前项目中 Core Data、本地持久化和 bookmark 恢复的真实使用方式。

---

## 概述

本项目使用 Core Data，但用法非常克制。

当前实际情况是：

- Core Data **不是主业务数据库**
- 云盘文件树、用户数据、好友列表等主数据都不以 Core Data 为准
- Core Data 主要用于传输任务恢复相关元数据
- 本地文件访问权限依赖 security-scoped bookmark

此外，还要特别注意：

- 并不是所有 bookmark 都存在 Core Data 里
- 下载目录 bookmark 当前走的是 `UserDefaults`

---

## Core Data 当前承担的职责

### 主要实体

当前 `chat_storage.xcdatamodeld` 中最关键的实体是：

- `TransferTaskEntity`

其字段包括：

- `taskId`
- `fileName`
- `fileUrl`
- `fileSize`
- `targetDirId`
- `userId`
- `userName`
- `status`
- `progress`
- `uploadedBytes`
- `md5`
- `timestamp`

### 非核心实体

模型里还有模板残留的 `Item`，但当前主要业务并不依赖它。

---

## Core Data 栈现状

`Persistence.swift` 中当前使用的是：

```swift
NSPersistentCloudKitContainer
```

这里更多是沿用了 Xcode 模板生成的容器类型，并不意味着当前项目真的把业务数据当作 CloudKit 同步主数据库使用。

对当前项目而言，最重要的是：

- 本地任务元数据可恢复
- `viewContext` 可用
- 数据读写集中在 `PersistenceManager`

---

## 当前推荐访问方式

### 主路径：通过 `PersistenceManager.shared`

当前业务层操作任务数据时，应优先走：

- `saveTask(...)`
- `updateProgress(...)`
- `updateStatus(...)`
- `fetchPendingTasks()`
- `deleteTask(...)`
- `deleteCompletedTasks()`
- `resolveBookmark(data:)`

### 为什么

因为当前仓库已经把这些操作集中在 `PersistenceManager` 中，便于统一处理：

- `context.perform`
- `context.performAndWait`
- 实体查找
- 保存上下文
- bookmark 解析

### 补充说明

应用入口仍会把 `managedObjectContext` 注入到环境中，但当前真正的传输任务业务逻辑并不是直接在 View 中访问 `viewContext` 完成的。

---

## Bookmark 使用现状

### 1. 任务文件 URL 的 bookmark

传输任务的本地文件 URL 当前会转成 security-scoped bookmark 存进 Core Data：

- 保存路径：`TransferTaskEntity.fileUrl`
- 恢复路径：`PersistenceManager.resolveBookmark(data:)`

这是任务恢复链路的重要组成部分。

### 2. 下载目录 bookmark

下载目录不是走 Core Data，而是由 `DownloadDirectoryManager` 存到：

- `UserDefaults`

也就是说，当前项目有两条本地权限恢复路径：

- 任务文件 bookmark：Core Data
- 下载目录 bookmark：UserDefaults

文档或新实现里不能把它们混成一种机制。

---

## 状态字段使用现状

当前任务状态文案并不完全统一，既有中文也有英文残留。

代码里能看到的典型状态包括：

- `Waiting`
- `Uploading`
- `Downloading`
- `下载中`
- `上传中`
- `已暂停`
- `暂停`
- `Completed`
- `已完成`

### 特别注意

`fetchPendingTasks()` 当前是按：

```swift
status != "Completed"
```

过滤的。

而 `deleteCompletedTasks()` 会同时删除：

- `Completed`
- `已完成`

这说明当前状态值确实存在中英混用现状，新增逻辑时必须兼容。

---

## 下载任务识别方式

当前下载任务在持久化时，会把特殊标记放进 `md5` 字段：

```text
DOWNLOAD_FILE_ID_<remoteFileId>
```

例如：

```text
DOWNLOAD_FILE_ID_12345
```

`TransferTaskManager` 恢复任务时会靠这个标记区分：

- 上传任务
- 下载任务

这不是理想设计，但它是当前真实实现，改恢复逻辑时必须考虑。

---

## 查询与线程规范

### 当前常见模式

- 需要异步访问时：`context.perform { }`
- 需要同步取返回值时：`context.performAndWait { }`

### 当前已有例子

- `fetchEntity(taskId:)`
- `saveTask(...)`
- `deleteCompletedTasks()`

### 规则

- 不要在业务层自己直接裸用 `viewContext` 做跨线程访问
- 不要绕过 `PersistenceManager` 到处散落 Core Data 代码

---

## 当前数据库层最容易出错的点

### 1. 把 Core Data 当主业务真相

这是错误的。主业务数据仍然以服务端为准。

### 2. 只恢复任务元数据，不恢复权限

如果 bookmark 解析失败，任务实际上不能正常继续。

### 3. 忘记下载目录和任务文件不是同一条持久化路径

一个走 Core Data，一个走 UserDefaults。

### 4. 忽略状态中英混用

如果只按一种状态值过滤，恢复和清理都会出问题。

---

## 修改数据库相关功能前的检查单

- [ ] 这次改动真的需要写入 Core Data 吗？
- [ ] 这份数据是不是只是本地恢复状态，而不是主业务数据？
- [ ] 如果涉及文件路径，是否需要 security-scoped bookmark？
- [ ] 这个 bookmark 应该存 Core Data 还是 UserDefaults？
- [ ] 状态过滤是否兼容当前仓库里已存在的中英混用值？

---

**核心原则**：本地持久化在这个项目里是“恢复运行状态”的工具，不是主业务数据源。
