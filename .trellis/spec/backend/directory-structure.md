# 目录结构

> 当前项目中服务层、模型层、协议层和持久化层的真实组织方式。

---

## 概述

这个项目的“后端层”主要指客户端内部的非视图代码。但需要注意，代码组织里存在明显的历史痕迹：

- 一些真正的 SwiftUI 视图文件放在 `Services/`
- 一些旧文件仍然保留作为占位或兼容壳
- 一些类型的真实定义不在最直观的文件里

因此理解目录时，必须按**实际职责**而不是只按路径名。

---

## 当前主要目录布局

```text
chat-storage/
├── Models/
│   ├── frame/
│   │   ├── Frame.swift
│   │   ├── FrameBuilder.swift
│   │   ├── FrameParser.swift
│   │   └── FrameTypeEnum.swift
│   ├── do/
│   │   ├── UserDO.swift
│   │   └── FileDto.swift
│   ├── request/
│   │   └── UserRequest.swift
│   ├── business/
│   │   └── UserSearchModels.swift
│   ├── DirectoryItem.swift          # 废弃占位文件
│   └── FileDto.swift                # 废弃占位文件
├── Services/
│   ├── AuthenticationService.swift
│   ├── DirectoryService.swift
│   ├── FileDownloadService.swift
│   ├── FileTransferService.swift    # 历史占位，主逻辑已迁移
│   ├── TransferTaskManager.swift
│   ├── StorageTransferTask.swift
│   ├── TransferModels.swift
│   ├── ManagedCriticalState.swift
│   ├── LocalMediaServer.swift
│   ├── VideoStreamCache.swift
│   ├── VideoStreamingService.swift
│   ├── VideoStreamLoaderDelegate.swift
│   ├── VideoWindowManager.swift
│   ├── VideoPlayerView.swift
│   └── RecursiveDirectoryView.swift # 路径在 Services，但本质是 SwiftUI 视图
├── SocketManager.swift
├── SocketManager+FrameHandling.swift # 历史占位，逻辑已并入 SocketManager
├── Persistence.swift
└── InputValidator.swift
```

---

## 协议层

位于 `Models/frame/`，负责自定义二进制帧协议：

- `Frame.swift`
  - 帧结构定义
- `FrameTypeEnum.swift`
  - 所有协议消息类型
- `FrameBuilder.swift`
  - 从 `Codable`、字典或原始 JSON 数据构建帧
- `FrameParser.swift`
  - 从原始数据解析帧，以及解码帧内容

这是整个客户端最底层的通信模型。

---

## 模型层

### `Models/do/`

放的是主要 DTO：

- `UserDO`
- `FileDto`

其中 `FileDto.swift` 还同时定义了当前真实使用的 `DirectoryItem`。

### `Models/request/`

目前主要是：

- `UserRequest`

### `Models/business/`

当前 `UserSearchModels.swift` 已基本废弃，文档和代码都不应把它当成主要模型入口。

---

## 服务层

### `SocketManager.swift`

这是当前最核心的服务文件之一，负责：

- TCP 连接
- 发送帧
- 等待响应
- 维护 continuation 映射
- 注册流式处理器
- 持有好友 / 聊天部分共享状态

它既是通信层，又是部分状态层。

### `AuthenticationService.swift`

负责：

- 登录
- 注册
- 退出登录

它本身较轻，主要是构造请求、调用 `SocketManager`、解析结果并更新认证状态。

### `DirectoryService.swift`

这是另一个高复杂度文件，当前同时承担：

- 目录树加载
- 目录创建 / 重命名 / 删除
- 文件列表 / 详情 / 删除 / 重命名
- 上传流程
- 视频流请求
- 下载目录管理相关合并代码
- 任务恢复相关逻辑

这里的职责边界已经明显扩大，后续开发时需要格外小心。

### `TransferTaskManager.swift`

负责：

- 任务入队
- 并发调度
- 暂停 / 恢复 / 取消
- 从数据库恢复任务
- 管理活跃任务与等待队列

### 媒体 / 下载相关服务

当前媒体与下载链路相关文件包括：

- `FileDownloadService.swift`
- `LocalMediaServer.swift`
- `VideoStreamCache.swift`
- `VideoStreamingService.swift`
- `VideoStreamLoaderDelegate.swift`
- `VideoWindowManager.swift`
- `VideoPlayerView.swift`

这些能力和普通目录 / 文件请求不同，不应简单等同于“常规文件下载”。

---

## 持久化层

### `Persistence.swift`

当前这个文件里同时包含：

- `PersistenceController`
- `PersistenceManager`

也就是说：

- Core Data 栈初始化
- 任务实体读写
- bookmark 恢复

都集中在这个文件中。

---

## 重要例外与历史文件

### 1. `SocketManager+FrameHandling.swift`

当前为保留文件，主要逻辑已合并进 `SocketManager.swift`。

### 2. `Services/FileTransferService.swift`

当前是历史占位文件，注释说明主逻辑已迁移。

### 3. `Models/DirectoryItem.swift` / `Models/FileDto.swift`

这两个也是废弃占位，不是当前真实类型定义入口。

### 4. `Services/RecursiveDirectoryView.swift`

路径在 `Services/`，但本质是前端 SwiftUI 视图辅助文件。

因此它不应被误当成纯后端服务。

---

## 当前结构的阅读建议

如果你要改：

- 协议：先看 `Models/frame/`
- 通用连接 / 好友 / 聊天状态：先看 `SocketManager.swift`
- 目录 / 文件 / 上传：先看 `DirectoryService.swift`
- 传输队列：先看 `TransferTaskManager.swift`
- 本地持久化：先看 `Persistence.swift`
- 视频 / 范围请求 / 本地代理：先看媒体相关服务链路

---

## 当前目录结构的风险点

- 不要只看文件名判断真实职责
- 不要只看目录名判断前后端归属
- 不要误删占位文件
- 不要误以为类型一定定义在同名文件中

---

**核心原则**：按“谁真正负责这段逻辑”来理解结构，而不是按文件摆放位置想当然。
