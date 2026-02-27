# chat-storage 项目架构与代码逻辑分析

本文档是对 `chat-storage` (macOS 客户端) 项目结构和核心业务逻辑的详细分析总结，以供后续功能开发和维护参考。

## 一、 项目整体结构

该项目是一个基于 **SwiftUI** 的 macOS 桌面应用程序。其通信层没有使用传统的 HTTP/RESTful，而是基于**原生的 TCP Socket**，通过自定义帧 (Frame) 协议来进行全双工通信，并支持大文件的分块上传、下载断点续传。本地数据持久化使用的是 **CoreData**。

核心目录结构划分如下：
- `chat_storageApp.swift`：应用入口，初始化全局的 `SocketManager` 和 `AuthenticationService`，并控制路由（登录页 / 主界面）。
- `MainChatStorage.swift`：主界面视图，包含顶部工具栏、左侧目录树(`RecursiveDirectoryView`)以及右侧文件和传输列表。
- `Services/`：核心业务逻辑服务层
  - `SocketManager.swift`：底层 TCP 网络通信、流式数据解析。
  - `AuthenticationService.swift`：用户登录、注册等认证逻辑。
  - `DirectoryService.swift`：目录的 CRUD 操作、文件列表查询。
  - `TransferTaskManager.swift`：全局文件传输（上传/下载）并发调度与管理。
  - `FileTransferService.swift` / `FileDownloadService.swift`：具体的上传/下载业务逻辑（支持断点续传）。
- `Models/`：数据传输对象 (DTO) 和枚举。
  - `FrameTypeEnum.swift`：定义所有的自定义帧指令（如0x01、0x02等）。
- `Persistence.swift`：使用 CoreData 封装了 `PersistenceManager`，主要用于存储大文件传输的任务进度。

---

## 二、 核心代码逻辑深度分析

### 1. 通信架构：基于 TCP Socket 与自定义帧交互
- **类的职责**: `SocketManager` 是单例模式，内部封装了 `InputStream` 和 `OutputStream`，同时实现了 `StreamDelegate` 来监听底层事件（`hasBytesAvailable`）。
- **帧协议 (Frame Protocol)**: 所有的通信数据被打包成 `Frame`，其中包含了帧类型 `FrameTypeEnum` (如 `metaFrame`, `dataFrame`, `userLoginReq`) 和 Payload 数据（通常是 JSON 序列化后的 Data）。
- **同步/异步请求响应映射**: 
  - `sendFrameAndWait` 方法实现了像 HTTP 类似的 Request-Response 模型：内部通过维护 `activeContinuations` 字典和一个 `UUID` 来挂起一个 Swift Concurrency (`Continuation`)，当通过 `hasBytesAvailable` 监听到对应 `FrameTypeEnum` 的响应包后匹配并唤醒该协程，防止了 Callback Hell，使得业务层可以像调用 HTTP API 一样使用 `try await socketManager.sendFrameAndWait(...)`。
- **流调处理 (Stream Handler)**: 
  - 针对大文件下载等需要连续接受 `dataFrame` 的操作，采用 `registerStreamHandler`，通过回调函数非阻塞地读取长流数据。
- **长连接维护**: 内部维护一个 30 秒间隔的心跳定时器，以及 5 秒间隔的断线自动重连。

### 2. 用户认证链路 (AuthenticationService)
- 登录/注册方法构建 `UserRequest`（包含用户名、密码、邮箱、头像Base64），并封装成 `userLoginReq(0x31)` 帧。
- 等待接收 `userResponse(0x34)`。如果响应 Code = 200，则更新 `@Published var currentUser`，并将 `isAuthenticated` 设为 `true`。
- SwiftUI 的顶层结构 `chat_storageApp` 监听 `isAuthenticated` 变化，自动切换 `LoginView` 和 `MainChatStorage`。

### 3. 文件上传/下载调度与流控 (TransferTaskManager & TransferServices)
该系统的传输模块非常完善，具备**任务并发控制、断点续传、内存流控与状态持久化**。

- **并发控制 (TransferTaskManager)**
  - 系统限制了最大并发传输数量 (`maxConcurrentTasks = 5`)。
  - 任务加入 `pendingQueue`，调度器 (`scheduleNext`) 会动态唤醒。
  - **重要机制**：每次有新的文件传输任务，为了不阻塞主控制 Socket，会独立实例化一个新的 `SocketManager` 并连接到转用的传输端口（上传: 10087，下载: 10088）。传输完成后断开连接。
  
- **断点续传逻辑**
  - **上传 (`FileTransferService`)**: 计算本地文件 MD5，发送 `resumeCheck(0x05)`。服务端如果发现有断点记录 (`resumeAck`)，会返回已经上传了多少字节 `uploadedSize`。客户端直接通过 `try fileHandle.seek(toOffset: uploadedSize)` 跳过已传输数据继续传输 `dataFrame(0x02)`。
  - **下载 (`FileDownloadService`)**: Client 获取本地已知的大小 `startOffset`，通过 `metaFrame(0x01)` 将此 Offset 告诉服务端请求剩余部分。

- **内存背压与流控 (Backpressure Control)**
  - 在大文件下载时，由于网络读取速度可能远大于本地磁盘写入速度，会导致内存剧增。
  - `FileDownloadService` 引入了 `OperationQueue` 和 `pendingWrites` 数组。当队列深度大于 `maxPendingWrites = 100` 时，触发背压：主动调用 `Thread.sleep` 阻塞底层网络读取。直到队列长度下降到 `resumeThreshold = 50` 时再恢复接收，完美防止了 OOM。

### 4. 目录树与文件管理 (DirectoryService)
- **目录树**: 通过递归视图 `RecursiveDirectoryView` 渲染 SwiftUI `List`，支持展开/折叠。
- **文件列表**: 支持分页拉取 (`fileListReq = 0x40`)。返回的结果解析成 `PageResult<FileDto>`，UI 上映射为了带复选框、时间、大小的数据表格。

### 5. 本地持久化与权限 (PersistenceManager)
- 核心采用 **CoreData** (实体 `TransferTaskEntity`)，存储未完成和已完成的传输任务进度。
- **Security-Scoped Bookmark（安全范围书签）**: 在 macOS 中带有沙盒机制的应用，一旦进程重启就会丢失用户选择的文件读写权限。代码中在用户选择下载目录或上传文件时，通过 `bookmarkData(options: .withSecurityScope)` 持久化存储权限令牌到数据库。在 App 重启执行 `resumePendingTasks` 恢复任务时，通过 `resolveBookmark` 兑换回 `URL` 并调用 `startAccessingSecurityScopedResource()` 重新激活磁盘读写权限。

---

## 三、 总结与后续开发建议

目前代码质量较高，架构层次分明。利用了最新的 Swift Concurrency 特性优雅地解决了 TCP Socket 的非阻塞等待问题。

**后续如果需要进行功能开发，需要遵循以下原则**：
1. **网络请求拓展**: 添加新指令应先在 `FrameTypeEnum` 增加枚举，随后在需要的地方沿用 `try await socketManager.sendFrameAndWait(..., expecting: ...)` 的模式即可。
2. **SwiftUI 状态管理**: UI 根据 `@Published` 从 ViewModel (XXService 或 XXManager) 被动获取更新，不要违背 M-V-VM 模式。
3. **大文件传输拓展**: `TransferTaskManager` 只需负责调度，所有 IO 具体读写和内存保护务必放在 `FileTransferService/FileDownloadService`，必须遵循现有的"开启新端口"和"检查背后写入进度"原则。
4. **沙盒读写**: 后续如果有自动化处理文件，务必记得使用 `DownloadDirectoryManager` 或 Bookmark 机制维持 `startAccessingSecurityScopedResource`，否则会引发无权限报错。
