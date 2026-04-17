# 状态管理

> 当前项目中前端状态的真实分层方式。

---

## 概述

本项目没有 Redux、TCA 或其他集中式状态框架。状态管理完全建立在 SwiftUI 和 `ObservableObject` 之上。

当前实际模式可以分成四类：

- 应用壳层状态
- 全局共享服务状态
- 页面局部 UI 状态
- 持久化恢复出来的状态

理解这四类边界，是避免状态混乱的关键。

---

## 1. 应用壳层状态

### `chat_storageApp.swift`

应用入口当前主要持有：

```swift
@State private var isLoggedIn = false
@StateObject private var socketManager = SocketManager.shared
@StateObject private var authService = AuthenticationService.shared
```

这里的职责是：

- 决定当前展示登录页还是主界面
- 把共享对象注入到根视图树
- 处理窗口尺寸随登录态切换

### 说明

虽然 `AuthenticationService` 本身也有 `isAuthenticated`，但当前真正控制根视图切换的是 `isLoggedIn` 这个 App 层状态，而不是直接绑定 `authService.isAuthenticated`。

这是当前实现现状，后续修改认证流时要注意这两个状态不是同一个字段。

---

## 2. 全局共享服务状态

### `SocketManager`

当前最重要的共享状态源之一，承载：

- 连接状态
- 好友列表
- 待处理好友申请
- 聊天历史
- 未读数
- 当前活跃聊天对象
- 上传 / 下载速度显示

这些状态会被多个页面或多个界面区域同时消费，因此不应该复制到各个 View 中形成独立事实源。

### `AuthenticationService`

主要持有：

- 当前用户
- 认证状态

它是认证相关业务的共享状态源，但如上所述，当前页面切换仍依赖 `isLoggedIn`。

### `TransferTaskManager`

虽然不是在应用入口统一注入，但它本质上也承担共享任务状态的职责：

- 任务更新字典
- 活跃任务
- 等待队列
- 恢复任务

当前它主要在 `MainChatStorage` 中被观察和消费。

---

## 3. 页面局部状态

### `MainChatStorage.swift`

这是当前局部状态最密集的页面，包含大量 `@State`：

- 目录相关状态
- 文件列表状态
- 选择状态
- 搜索状态
- 分页状态
- 各类弹窗状态
- 文件详情状态
- 主题状态
- 面板拖拽与布局状态

这些状态虽然数量很多，但大多数都只服务于这个页面本身，因此仍然适合留在页面本地。

### 典型局部状态类型

#### 展示控制

- `showingAlert`
- `showingCreateDirDialog`
- `showingRenameDialog`
- `showingFileRenameDialog`
- `showingDeleteAlert`

#### 页面选择

- `selectedTab`
- `selectedDirectoryId`
- `selectedFiles`
- `selectedFileId`

#### 数据结果

- `directoryTree`
- `fileList`
- `fileDetail`
- `transferList`

#### 交互过程

- `isLoadingDirectory`
- `isCreatingDirectory`
- `isRenaming`
- `isFileRenaming`
- `isDeleting`

---

## 4. 持久化恢复状态

这个项目有一类状态不是服务端即时返回的，也不是单纯页面局部状态，而是**从本地恢复出来的运行状态**。

主要包括：

- 未完成的传输任务
- 任务进度
- 本地文件访问 bookmark
- 下载目录 bookmark

相关来源包括：

- `PersistenceManager` / Core Data
- `DownloadDirectoryManager` / `UserDefaults`

这些状态的典型特征是：

- 它们会跨应用重启存在
- 它们不是后端主数据
- 但对“继续工作”非常关键

因此它们应被视为“运行恢复状态”，不要和普通页面缓存混为一谈。

---

## 服务对象在视图层的接入现状

### `DirectoryService`

当前在 `MainChatStorage` 里并不是 `@StateObject`，而是：

```swift
@State private var directoryService: DirectoryService?
```

这说明当前项目里并不是所有服务都走统一模式。

`DirectoryService` 更像一个页面内按需初始化、随后被方法调用的服务对象，而不是一个重度依赖 `@Published` 刷新的共享状态容器。

### `DownloadDirectoryManager`

当前通过 `@StateObject` 在主页面观察，因为下载目录变化确实会影响 UI 展示和下载行为。

---

## 当前项目中的数据刷新策略

整体上，本项目更偏向：

- 操作后重新拉取
- 局部覆盖状态
- 少做乐观更新

常见场景：

- 创建目录后刷新目录树 / 文件列表
- 重命名后刷新列表与详情
- 删除后刷新当前列表
- 处理好友申请后重新获取申请列表和好友列表

这意味着当前代码的状态一致性更多依赖“操作成功后再刷新”，而不是复杂的本地状态推导。

---

## 当前项目不是怎样的

为了避免误判，这里明确几件事：

- 不是所有状态都在一个 Store 中集中管理
- 不是所有服务都统一由应用入口注入
- 不是所有错误展示都统一用 alert
- 不是所有远端数据都有本地缓存层

因此设计新功能时，不要套用不属于当前项目的状态管理模型。

---

## 常见状态管理错误

### 1. 复制共享状态

例如把好友列表、未读数、聊天记录又在某个 View 里维护一份独立版本。

### 2. 错误提升局部状态

例如把某个弹窗开关、某个输入框值提成全局对象字段。

### 3. 忽略恢复状态

比如传输任务当前会话能跑，但重启后无法恢复，因为没接持久化链路。

### 4. 操作成功后不刷新依赖区域

协议调用成功不代表页面状态已经同步完成。

---

## 状态设计建议

新增功能前，先回答下面几个问题：

1. 这份数据是只在当前页面使用，还是多个页面共享？
2. 它来自服务端、来自本地恢复，还是纯 UI 瞬时状态？
3. 成功操作后，哪些区域必须一起刷新？
4. 应用重启后，它是否还需要存在？

如果这四个问题答不清，状态设计通常还不够稳。

---

## 检查单

- [ ] 共享事实是否只由一个状态源持有
- [ ] 局部交互状态是否仍留在页面内部
- [ ] 传输 / 下载目录等恢复状态是否考虑了重启场景
- [ ] 成功操作后是否刷新了所有依赖区域
- [ ] 没有把服务端主数据误当作长期本地真相

---

**核心原则**：先区分“共享事实”“页面状态”“恢复状态”，再决定放在哪里。
