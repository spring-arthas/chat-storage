# chat-storage 项目架构与功能分析

> 生成时间：2026-04-20  
> 项目路径：`/Users/hljy/macProjects/chat-storage`

---

## 一、项目概述

**chat-storage**（内部名称：毒药网盘）是一个 **macOS 原生个人云盘客户端**，使用 SwiftUI 构建，集成了云盘存储、好友管理和聊天能力。

### 核心定位

| 维度 | 说明 |
|------|------|
| **平台** | macOS 桌面应用 |
| **UI 框架** | SwiftUI + 少量 AppKit 桥接 |
| **通信方式** | 自定义二进制 TCP 长连接协议（非 HTTP/REST） |
| **依赖管理** | 仅依赖系统框架，无 CocoaPods / SPM 第三方依赖 |
| **持久化** | Core Data（仅用于传输任务恢复与 macOS 沙盒 Bookmark） |
| **测试覆盖** | 较轻，主要依赖手动验证 |

---

## 二、整体架构分层

```
┌────────────────────────────────────────────────────┐
│                    UI 层 (SwiftUI)                  │
│  LoginView / RegisterView / MainChatStorage        │
│  NewFriendView / ConfigServerView                  │
│  Views/StreamingVideoPlayer                        │
│  Services/RecursiveDirectoryView（误放路径）        │
├────────────────────────────────────────────────────┤
│                   服务层 (Services)                 │
│  AuthenticationService  DirectoryService           │
│  TransferTaskManager    FileDownloadService        │
│  LocalMediaServer       VideoStreamingService      │
│  VideoStreamCache       VideoStreamLoaderDelegate  │
│  VideoWindowManager                                │
├────────────────────────────────────────────────────┤
│              核心通信层 (SocketManager)              │
│  TCP 连接管理 / 帧收发 / 请求响应匹配               │
│  好友 / 聊天共享状态持有                            │
├────────────────────────────────────────────────────┤
│                协议层 (Models/frame)                │
│  Frame / FrameBuilder / FrameParser / FrameTypeEnum │
├────────────────────────────────────────────────────┤
│               模型 / DTO 层 (Models)                │
│  UserDO / FileDto / UserRequest / TransferModels   │
├────────────────────────────────────────────────────┤
│              持久化层 (Persistence.swift)            │
│  Core Data 栈 / TransferTaskEntity / Bookmark 恢复  │
└────────────────────────────────────────────────────┘
```

---

## 三、目录结构说明

```text
chat-storage/
├── chat-storage/                  # 主 macOS 应用 Target
│   ├── chat_storageApp.swift      # 应用入口，登录态 / 主界面切换
│   ├── MainChatStorage.swift      # 登录后主界面壳层（体量最大）
│   ├── LoginView.swift            # 登录界面
│   ├── RegisterView.swift         # 注册界面（含头像选择）
│   ├── NewFriendView.swift        # 待处理好友申请界面
│   ├── ConfigServerView.swift     # 服务端地址配置弹窗
│   ├── ContentView.swift          # 模板占位，非真实入口
│   ├── InputValidator.swift       # 输入校验辅助工具
│   ├── SocketManager.swift        # 核心 TCP 连接与共享状态管理
│   ├── SocketManager+FrameHandling.swift  # 历史占位，逻辑已并入主文件
│   ├── Persistence.swift          # Core Data 栈与 Bookmark 恢复
│   ├── Models/
│   │   ├── frame/                 # 二进制帧协议核心类型
│   │   │   ├── Frame.swift
│   │   │   ├── FrameBuilder.swift
│   │   │   ├── FrameParser.swift
│   │   │   └── FrameTypeEnum.swift
│   │   ├── do/
│   │   │   ├── UserDO.swift
│   │   │   └── FileDto.swift      # 同时定义了 DirectoryItem
│   │   ├── request/
│   │   │   └── UserRequest.swift
│   │   ├── DirectoryItem.swift    # ⚠️ 废弃占位
│   │   └── FileDto.swift          # ⚠️ 废弃占位
│   ├── Services/
│   │   ├── AuthenticationService.swift
│   │   ├── DirectoryService.swift  # 高复杂度，职责偏宽
│   │   ├── FileDownloadService.swift
│   │   ├── FileTransferService.swift  # ⚠️ 历史占位
│   │   ├── TransferTaskManager.swift
│   │   ├── StorageTransferTask.swift
│   │   ├── TransferModels.swift
│   │   ├── ManagedCriticalState.swift
│   │   ├── LocalMediaServer.swift
│   │   ├── VideoStreamCache.swift
│   │   ├── VideoStreamingService.swift
│   │   ├── VideoStreamLoaderDelegate.swift
│   │   ├── VideoWindowManager.swift
│   │   ├── VideoPlayerView.swift
│   │   └── RecursiveDirectoryView.swift  # ⚠️ 本质是前端 View
│   └── Views/
│       └── StreamingVideoPlayer.swift
├── chat-storage.xcodeproj/        # Xcode 工程文件
├── chat-storageTests/             # 单元测试（覆盖较轻）
├── chat-storageUITests/           # UI 测试（基本是模板）
├── .trellis/                      # 项目工作流 / 规范 / 任务系统
│   ├── spec/                      # AI 辅助开发规范文档
│   └── tasks/                     # 任务追踪与 PRD
├── .claude/                       # Claude AI Agent 配置
│   ├── agents/                    # 子 Agent 提示词
│   ├── commands/trellis/          # 自定义 Claude 命令
│   └── hooks/                     # 会话钩子脚本（Python）
├── .trae/                         # Trae AI 开发历史记录
├── CLAUDE.md                      # 仓库级编码说明
└── AGENTS.md                      # 会话启动说明
```

---

## 四、核心功能模块详解

### 4.1 用户认证模块

**相关文件：** `LoginView.swift`、`RegisterView.swift`、`AuthenticationService.swift`

**功能：**
- 用户登录 / 注册 / 退出登录
- Socket 连接状态展示
- 服务端地址配置（`ConfigServerView`）
- 注册时支持通过原生文件选择器上传头像

**流程：**
```
LoginView/RegisterView → AuthenticationService
  → 构建用户帧 → SocketManager.sendFrameAndWait()
  → 解析 userResponse → 更新认证状态
  → 切换到 MainChatStorage
```

---

### 4.2 云盘存储模块

**相关文件：** `MainChatStorage.swift`、`DirectoryService.swift`、`RecursiveDirectoryView.swift`

**功能：**
- 远程目录树浏览与展示
- 文件列表分页获取
- 文件详情查看
- 文件 / 目录删除
- 文件重命名（帧类型 `0x44 FILE_RENAME_REQ`）
- 目录创建 / 重命名 / 删除
- 文件上传（含断点续传）
- 文件下载

**帧类型对应：**

| 操作 | 帧类型 | 方向 |
|------|--------|------|
| 目录列表 | `0x10` dirListReq | C→S |
| 文件列表 | `0x40` fileListReq | C→S |
| 文件详情 | `0x41` fileDetailReq | C→S |
| 文件删除 | `0x42` fileDeleteReq | C→S |
| 文件操作响应 | `0x43` FILE_RESPONSE | S→C |
| 文件重命名 | `0x44` FILE_RENAME_REQ | C→S |
| 上传相关 | `0x20`-`0x2F` | 双向 |

---

### 4.3 传输任务调度模块

**相关文件：** `TransferTaskManager.swift`、`StorageTransferTask.swift`、`FileDownloadService.swift`、`Persistence.swift`

**功能：**
- 全局传输任务队列管理
- 最大并发数控制（`maxConcurrentTasks = 5`）
- 任务暂停 / 恢复 / 取消
- 基于 Core Data 的任务状态持久化
- 应用重启后未完成任务自动恢复
- macOS 沙盒环境下的 Security-Scoped Bookmark 恢复

**任务状态机：**
```
[等待] → [运行中] → [完成]
           ↕
        [暂停]
           ↕
        [失败] → [重试]
```

---

### 4.4 视频流播放模块

**相关文件：** `LocalMediaServer.swift`、`VideoStreamingService.swift`、`VideoStreamCache.swift`、`VideoStreamLoaderDelegate.swift`、`VideoWindowManager.swift`、`VideoPlayerView.swift`、`Views/StreamingVideoPlayer.swift`

**功能：**
- 通过本地 HTTP 代理桥接 AVPlayer 与自定义 TCP 协议
- 支持 HTTP Range 请求（断点续播 / seek）
- 视频帧缓存（`VideoStreamCache`）
- 独立视频窗口管理（`VideoWindowManager`）

**播放链路：**
```
UI 请求播放
  → LocalMediaServer 分配本地 HTTP 地址 (127.0.0.1)
  → AVPlayer 发起 HTTP Range 请求
  → LocalMediaServer 拦截 Range 请求
  → VideoStreamingService 通过 TCP Socket 读取远端数据
  → VideoStreamCache 缓存数据
  → 返回 HTTP 响应给 AVPlayer
```

> **设计意图：** AVPlayer 不感知底层私有协议，本地代理完全隔离了两层通信。

---

### 4.5 好友与聊天模块

**相关文件：** `SocketManager.swift`（状态持有）、`NewFriendView.swift`、`MainChatStorage.swift`

**功能：**
- 用户搜索
- 发送好友申请
- 好友申请审批（`NewFriendView`）
- 好友列表管理
- 聊天界面入口与状态管理
- 未读消息数维护

**相关帧类型：**

| 操作 | 帧范围 |
|------|--------|
| 用户 / 好友操作 | `0x30`-`0x3F` |
| 聊天消息 | `0x50`-`0x58` |

---

## 五、网络通信协议

### 帧结构

```
┌──────────┬──────────┬───────────┬───────┬─────────────┬────────────┐
│ Magic[0] │ Magic[1] │ frameType │ flags │  dataLen    │    data    │
│  0xFA    │  0xCE    │   1 byte  │ 1 byte│  4 bytes    │  N bytes   │
│  (固定)  │  (固定)  │  帧类型   │ 0x00  │ Big-Endian  │ UTF-8 JSON │
└──────────┴──────────┴───────────┴───────┴─────────────┴────────────┘
```

### 帧类型分布

| 范围 | 用途 |
|------|------|
| `0x01`-`0x06` | 基础传输帧 |
| `0x10`-`0x1F` | 目录操作帧 |
| `0x20`-`0x2F` | 文件上传帧 |
| `0x30`-`0x3F` | 用户 / 好友帧 |
| `0x40`-`0x4F` | 文件操作帧 |
| `0x50`-`0x58` | 聊天帧 |

### 通信模式

| 模式 | 使用场景 | 实现机制 |
|------|---------|----------|
| **单次请求/响应** | 登录、目录加载、文件操作 | `sendFrameAndWait()` + CheckedContinuation |
| **流式处理** | 下载、视频流、部分聊天 | 注册 StreamHandler 持续接收帧 |

---

## 六、状态管理

### 全局共享状态

| 状态持有者 | 持有内容 | 注入方式 |
|-----------|---------|----------|
| `SocketManager.shared` | 好友列表、待处理申请、未读数、聊天历史、连接状态 | `@EnvironmentObject` |
| `AuthenticationService.shared` | 当前用户信息、认证状态 | `@EnvironmentObject` |

### 局部状态

- `MainChatStorage.swift` 内含大量 `@State` / `@StateObject` 局部状态
- 视图通过 `@Published` 属性驱动 SwiftUI 刷新

---

## 七、持久化策略

Core Data 在本项目中**使用非常克制**：

| 用途 | 是否使用 Core Data |
|------|-------------------|
| 传输任务状态（`TransferTaskEntity`）| ✅ 是 |
| Security-Scoped Bookmark（文件访问权限恢复）| ✅ 是 |
| 云盘文件树 / 目录主数据 | ❌ 否（以远端服务端为准）|
| 聊天记录 | ❌ 否 |
| 好友列表 | ❌ 否 |

> **核心约定：主业务数据以远端服务端为准；本地持久化只服务于传输恢复与 macOS 沙盒权限恢复。**

---

## 八、已完成 / 进行中的任务记录

| 任务目录 | 描述 | 状态 |
|----------|------|------|
| `04-05-Video-streaming-optimization-01` | 视频流性能优化 | 已归档 |
| `04-05-File-List-Modify-Name-01` | 文件重命名功能（帧 0x44）| 已归档 |
| `04-08-video-file-pre-view` | 文件列表图片/视频缩略图预览 | 进行中 |
| `04-20-video-view`（当前）| 视频查看相关 | 进行中 |

---

## 九、当前架构风险点

### 已知技术债

| 文件 | 问题描述 |
|------|----------|
| `MainChatStorage.swift` | 体量过大，混合了大量业务逻辑与 UI |
| `SocketManager.swift` | 同时承担传输层 + 社交状态持有职责，边界不清 |
| `DirectoryService.swift` | 职责过宽，包含目录、文件、上传、视频流、任务恢复等多种逻辑 |
| `SocketManager+FrameHandling.swift` | 历史占位，主逻辑已并入主文件 |
| `Services/FileTransferService.swift` | 历史占位，已迁移 |
| `Models/DirectoryItem.swift` + `Models/FileDto.swift` | 废弃占位，不是真实类型入口 |
| `ContentView.swift` | 模板文件，非真实入口 |

### 并发风险

- Swift Concurrency（`async/await`）与部分 GCD / 锁并行使用，需注意线程安全
- 流式处理链路（下载 / 视频）需覆盖取消、超时、断连等异常场景

### 错误处理

| 错误类型 | 定义位置 | 使用场景 |
|---------|---------|----------|
| `SocketError` | `SocketManager.swift` | TCP 连接 / 超时 / 发送失败 |
| `FrameError` | `Models/frame/Frame.swift` | 帧解析 / 编解码错误 |
| `AuthError` | `AuthenticationService.swift` | 登录 / 注册失败 |
| `DirectoryError` | `DirectoryService.swift` | 目录 / 文件业务错误 |
| `FileTransferError` | `DirectoryService.swift` | 上传链路错误 |

---

## 十、技术栈总结

| 技术 | 用途 |
|------|------|
| **Swift** | 主开发语言 |
| **SwiftUI** | 主 UI 框架 |
| **AppKit** | 部分 macOS 原生能力桥接 |
| **AVKit / AVFoundation** | 视频播放 |
| **Network Framework** | TCP Socket 底层支持 |
| **Core Data** | 传输任务持久化 |
| **NSPersistentCloudKitContainer** | Core Data 栈初始化 |
| **CommonCrypto** | 文件 MD5 哈希计算 |
| **Swift Concurrency** | `async/await`、`CheckedContinuation` |
| **GCD + 锁** | 部分并发协调 |

---

## 十一、开发规范摘要

### 新增网络能力
1. 在 `FrameTypeEnum.swift` 新增帧类型枚举
2. 在对应 Service 中构建请求帧并调用 `SocketManager.sendFrameAndWait()`
3. 解析响应并更新状态，错误通过 `throws` 向上传递
4. View 层 `catch` 错误并展示

### 新增视图
- 尽量拆分 `body` 中的逻辑为子 View 或 `@ViewBuilder` 方法
- 全局状态通过 `@EnvironmentObject` 注入，不重复声明
- 不在 View 中直接操作 Socket 或写持久化逻辑

### 禁忌
- 不引入第三方 SPM / CocoaPods 依赖
- 不把更多业务逻辑继续堆进 `MainChatStorage.body`
- 不误删历史占位文件（需确认无 Xcode 引用）
- 不假设服务端响应格式统一（需按接口实际格式判断）

---

*本文档由 Perplexity AI 基于项目源码与 .trellis 规范自动生成，仅供参考。*
