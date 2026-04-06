# 项目概览

> `毒药网盘` (`chat-storage`) 是一个 macOS 原生个人云盘客户端，集成了好友与聊天能力，使用 SwiftUI 构建，并基于自定义二进制 TCP 协议进行通信。

---

## 项目摘要

本仓库包含一个 **macOS 桌面应用**。它通过**长连接原始 TCP Socket**与远端后端通信，而不是通过 HTTP/REST。

这个应用当前的主要职责包括：

- 用户认证（登录 / 注册）
- 远程目录浏览与文件管理
- 支持断点续传的上传 / 下载任务调度
- 基于 Core Data 的本地传输任务持久化
- 好友搜索、好友申请处理，以及聊天相关 UI / 状态管理
- 通过本地 HTTP 桥接，将自定义 Socket 协议数据提供给 `AVPlayer` 进行视频播放

该代码库在依赖上相对克制：

- **不使用 CocoaPods**
- **不使用 Swift Package Manager 第三方依赖**
- **仅依赖系统框架**

---

## 产品范围

从产品层面看，当前应用主要围绕两个用户可见区域展开：

| 功能域 | 用户可执行的操作 |
|------|----------------|
| 云盘存储 | 浏览目录、查看文件、上传下载、管理传输队列、预览或流式播放媒体 |
| 社交 / 聊天 | 登录、搜索用户、发送好友申请、处理待审批请求、管理好友列表、进入聊天相关界面 |

当前代码库中，云盘存储是主业务中心。聊天与好友能力已经接入，但相对仍是次级能力。

---

## 架构快照

### 应用层

- `chat-storage/chat_storageApp.swift`
  - 应用入口
  - 创建共享的 `SocketManager` 与 `AuthenticationService`
  - 在 `LoginView` 与 `MainChatStorage` 之间切换
  - 配置 macOS 窗口尺寸与启动行为

### UI 层

- `chat-storage/LoginView.swift`
  - 登录表单
  - Socket 连接状态展示
  - 服务端配置入口
- `chat-storage/RegisterView.swift`
  - 注册流程
  - 通过原生文件选择器选择头像
- `chat-storage/MainChatStorage.swift`
  - 登录后的主界面壳层
  - 承载云盘 UI、传输面板、好友 / 聊天区域、视频入口，以及大量顶层状态
- `chat-storage/NewFriendView.swift`
  - 待处理好友申请列表与审批流程
- `chat-storage/ConfigServerView.swift`
  - 测试或切换服务端主机与端口
- `chat-storage/Views/StreamingVideoPlayer.swift`
  - 视频播放视图

### 服务层

- `chat-storage/SocketManager.swift`
  - 核心 TCP 连接管理器
  - 帧发送 / 接收循环
  - 基于 Continuation 的请求 / 响应匹配
  - 好友列表、待处理请求、未读数、聊天历史等共享状态
- `chat-storage/Services/AuthenticationService.swift`
  - 登录 / 注册 / 退出登录
  - 维护当前用户与认证状态
- `chat-storage/Services/DirectoryService.swift`
  - 目录增删改查
  - 文件列表 / 详情 / 删除 / 重命名
  - 上传下载相关请求逻辑
- `chat-storage/Services/TransferTaskManager.swift`
  - 全局传输队列
  - 并发上限控制（`maxConcurrentTasks = 5`）
  - 暂停 / 恢复 / 取消 / 恢复持久化任务
- `chat-storage/Services/LocalMediaServer.swift`
  - 运行在 `127.0.0.1` 的本地 HTTP 服务
  - 将 `AVPlayer` 的 Range 请求转成底层 Socket 流读取
- `chat-storage/Services/VideoStreamingService.swift`
  - 面向非顺序访问 / 大范围 seek 的专用视频流服务
- `chat-storage/Persistence.swift`
  - Core Data 栈与传输任务持久化实现

### 模型 / 协议层

- `chat-storage/Models/frame/`
  - 二进制线协议模型（`Frame`、`FrameBuilder`、`FrameParser`、`FrameTypeEnum`）
- `chat-storage/Models/do/`
  - 远端 DTO，例如 `UserDO` 与 `FileDto`
- `chat-storage/Services/TransferModels.swift`
  - 好友、聊天、传输相关 DTO

---

## 网络通信模型

本项目**不是**典型的 REST 客户端架构。

应用使用的是一套自定义帧协议：

- 帧头格式：`Magic(2) + Type(1) + Flags(1) + Length(4) + Data(N)`
- 魔数：`0xFACE`
- 负载通常是 JSON 编码数据
- 请求 / 响应匹配由 `SocketManager.sendFrameAndWait(...)` 负责
- 长时流式场景不会只依赖单次请求 / 响应，而是通过专门的流处理器完成

`FrameTypeEnum` 目前按职责大致分为：

- 基础传输帧（`0x01`-`0x06`）
- 目录操作帧（`0x10`-`0x1F`）
- 目录文件上传帧（`0x20`-`0x2F`）
- 用户 / 好友帧（`0x30`-`0x3F`）
- 文件操作帧（`0x40`-`0x4F`）
- 聊天帧（`0x50`-`0x58`）

这是整个应用最关键的架构事实。大多数服务层和 UI 层设计都围绕这套协议展开。

---

## 核心业务流

### 认证流程

1. `LoginView` / `RegisterView` 收集凭证
2. `AuthenticationService` 构建用户相关请求帧
3. `SocketManager` 发送请求，并等待 `userResponse`
4. 认证状态更新后，应用从登录界面切换到主界面

### 云盘浏览

1. `MainChatStorage` 创建 `DirectoryService`
2. 目录树通过 `dirListReq` 加载
3. 文件列表通过 `fileListReq` 分页获取
4. 文件详情、删除、重命名等操作也都通过帧协议完成

### 传输队列

1. UI 将上传 / 下载任务封装为 `StorageTransferTask`
2. `TransferTaskManager` 保存任务状态并入队
3. 同时最多运行 5 个任务
4. 任务进度与状态会写入 Core Data
5. 未完成任务会在下次启动时恢复

### 视频播放

1. UI 从 `LocalMediaServer` 获取本地流地址
2. `AVPlayer` 向 `127.0.0.1` 发起 HTTP Range 请求
3. 本地代理再通过 Socket 相关视频服务 / 缓存完成实际读取
4. 这样可以在不暴露底层私有协议的前提下，支持播放、拖动和流式加载

### 好友 / 聊天流程

1. 用户搜索、好友列表、待处理申请获取、申请处理都通过 `SocketManager` 进行
2. 共享的 `@Published` 状态驱动对应 SwiftUI 视图刷新
3. 聊天相关状态主要分布在 `SocketManager` 与 `MainChatStorage` 中

---

## 仓库结构

```text
chat-storage/
|-- chat-storage/                 # 主 macOS 应用 target
|   |-- Models/                   # DTO 与帧协议类型
|   |-- Services/                 # 网络、存储、传输、媒体等服务
|   |-- Views/                    # 拆分出的独立视图文件
|   |-- chat_storageApp.swift     # 应用入口
|   |-- MainChatStorage.swift     # 登录后的主界面壳层
|   +-- Persistence.swift         # Core Data 栈
|-- chat-storage.xcodeproj/       # Xcode 工程
|-- chat-storageTests/            # 单元测试
|-- chat-storageUITests/          # UI 测试
|-- .trellis/                     # 项目工作流 / 规范 / 任务系统
|-- CLAUDE.md                     # 仓库级编码说明
+-- AGENTS.md                     # 会话启动说明
```

### 重要的 `.trellis` 文件

- `.trellis/workflow.md`
  - 会话工作流与推荐阅读顺序
- `.trellis/spec/`
  - 面向 AI 辅助开发的项目规范文档
- `.trellis/tasks/`
  - 任务追踪与 PRD 文档
- `.trellis/workspace/`
  - 按开发者隔离的日志与工作记录

---

## 构建、测试与打包

### 用 Xcode 打开

```bash
open chat-storage.xcodeproj
```

### 命令行构建

```bash
xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug build
```

### 运行测试

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'
```

### 打包 DMG

```bash
bash package_dmg.sh
```

### 发布 / 公证打包

```bash
DEVELOPER_TEAM_ID="<TEAM_ID>" \
DEVELOPER_ID_APPLICATION="Developer ID Application: <Name> (<TEAM_ID>)" \
NOTARY_KEYCHAIN_PROFILE="chat-storage-notary" \
bash chat-storage/scripts/build_release_dmg.sh
```

---

## 持久化模型

Core Data 在本项目中使用得**非常克制**：

- **不会**存储云盘文件树主数据
- **不会**作为主要业务数据库
- 主要用于 `TransferTaskEntity` 的持久化
- 用于存储 security-scoped bookmark，以便应用重启后恢复对本地文件 / 目录的访问权限

这是本项目的重要约定：**主业务数据以远端服务端为准；本地持久化主要服务于传输恢复与 macOS 沙盒文件权限恢复。**

---

## 当前工程现实

代码库目前有几项应该明确记录、而不是被忽略的现实约束：

- `MainChatStorage.swift` 体量很大，当前承担了很多功能的主组合入口职责。
- `SocketManager.swift` 既是传输层，又承担了部分社交 / 聊天共享状态持有者的职责。
- `DirectoryService.swift` 同时包含目录 / 文件操作和部分传输相关逻辑，职责边界并不完全纯粹。
- 应用启动时会自动连接，且 `SocketManager.connect()` 当前内置了默认服务端地址与端口。
- 有些文件保留的主要原因是兼容 Xcode 引用或历史结构，而不是当前核心实现：
  - `chat-storage/SocketManager+FrameHandling.swift`
  - `chat-storage/Services/FileTransferService.swift`
  - `chat-storage/Models/DirectoryItem.swift`
  - `chat-storage/Models/FileDto.swift`
- `chat-storage/ContentView.swift` 更像模板 / 演示文件，并不是当前真实应用壳层。

这些点未必都是缺陷，但它们确实是后续开发时必须考虑的结构现实。

---

## 测试现状

当前自动化测试覆盖较轻。

- `chat-storageTests/`
  - 主要是少量围绕主题常量和窗口布局常量的测试
- `chat-storageUITests/`
  - 基本仍是模板式启动测试

因此大部分功能开发后，仍然需要依赖手工验证。

---

## AI 助手默认应当理解的事实

在这个仓库里工作时，除非代码明确证明不是这样，否则默认应理解为：

- 数据源以远端服务端为准，而不是本地数据库
- 新增网络能力通常意味着新增或消费一个新的帧类型
- SwiftUI 视图通常依赖通过环境对象注入的共享单例
- 传输恢复与 bookmark 持久化在 macOS 上是高优先级稳定性能力
- 一些文件属于历史兼容垫片，未经确认不要随意“清理”

---

## 技术栈

- **语言**：Swift
- **UI 框架**：SwiftUI
- **平台 API**：AppKit、AVKit、Network、Core Data
- **持久化**：`NSPersistentCloudKitContainer`，用于本地传输任务存储
- **网络通信**：基于 `InputStream` / `OutputStream` 的自定义二进制 TCP 协议
- **并发模型**：Swift Concurrency（`async/await`、`CheckedContinuation`）结合部分 GCD / 锁协调
- **哈希 / 文件能力**：`CommonCrypto`、Foundation 文件 API

---

## 非目标

本仓库**不是**：

- Web 前端项目
- REST API 客户端项目
- 高度模块化的 Swift Package 工作区
- 自动化测试覆盖很全面的工程

明确这些非目标，有助于避免引入不适合当前架构的模式。
