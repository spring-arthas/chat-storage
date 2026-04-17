# 属性包装器与状态接入

> 当前项目中 SwiftUI 属性包装器和视图状态接入方式的实际使用说明。

---

## 概述

这个项目没有 React 式自定义 hooks，也没有引入额外状态框架。前端状态主要依赖 SwiftUI 原生属性包装器：

- `@State`
- `@StateObject`
- `@EnvironmentObject`
- `@Binding`
- `@ObservedObject`
- `@Published`

需要注意的是：项目里虽然整体有主流模式，但并不是完全没有例外，因此规则要按“主要写法 + 已存在例外”理解。

---

## 属性包装器使用总览

| 包装器 | 当前主要用途 |
|--------|--------------|
| `@State` | 当前视图私有 UI 状态、输入框状态、弹窗状态、分页状态、选中状态 |
| `@StateObject` | 当前视图负责观察和持有的对象，常见于 `MainChatStorage` |
| `@EnvironmentObject` | 应用入口注入的全局共享服务 |
| `@Binding` | 父子视图之间传递可写状态 |
| `@ObservedObject` | 由外部创建并传入、当前视图只负责观察的对象 |
| `@Published` | `ObservableObject` 内用于驱动 SwiftUI 刷新的共享状态 |

---

## `@State`

### 当前项目里适合放进 `@State` 的内容

- 输入框内容
- 是否显示弹窗 / 对话框 / 覆盖层
- 当前选中的 tab、目录、文件
- 分页信息
- 当前页局部加载态
- 搜索关键字
- 只属于单个页面的展示状态

典型例子在 `MainChatStorage.swift` 中非常多，例如：

- `showingAlert`
- `alertMessage`
- `currentPage`
- `selectedFiles`
- `showingFileRenameDialog`
- `fileRenameValue`

### 不适合放进 `@State` 的内容

- 需要多个页面共享的事实数据
- 由后台消息推送更新的数据
- 需要跨页面持续存在的全局状态

---

## `@EnvironmentObject`

### 当前项目中的主流注入对象

由 `chat_storageApp.swift` 注入：

```swift
@StateObject private var socketManager = SocketManager.shared
@StateObject private var authService = AuthenticationService.shared
```

视图内读取：

```swift
@EnvironmentObject var socketManager: SocketManager
@EnvironmentObject var authService: AuthenticationService
```

### 适用场景

- 连接状态
- 当前用户
- 好友列表
- 待处理好友申请
- 聊天历史
- 未读数

### 注意点

主流模式是用环境对象拿全局单例，而不是在 View 里直接 `.shared`。

但当前仓库存在少量历史例外，因此应理解为“优先模式”，不是“仓库中绝无例外”。

---

## `@StateObject`

### 当前项目里的典型用法

`MainChatStorage.swift` 里：

```swift
@StateObject private var transferManager = TransferTaskManager.shared
@StateObject private var downloadDirectoryManager = DownloadDirectoryManager.shared
```

这里的核心含义是：

- 当前页面需要响应这些对象的发布变化
- 页面生命周期内持续依赖它们

### 另一个已存在的例外

`RegisterView.swift` 当前也是 `@StateObject private var authService ...`

这是仓库现状，不代表未来新页面都应这么做。新增页面时优先沿用应用入口已注入的环境对象模式。

---

## `@Binding`

### 当前项目里的典型场景

#### 1. 登录态切换

```swift
// App 持有
@State private var isLoggedIn = false

// 子视图读写
LoginView(isLoggedIn: $isLoggedIn)
MainChatStorage(isLoggedIn: $isLoggedIn)
```

#### 2. 目录树选中和展开状态

`RecursiveDirectoryView.swift` 中会通过 `@Binding` 共享：

- `selectedId`
- `expandedIds`

### 适用判断

如果一个值由父组件持有，但子组件需要修改它，就应优先考虑 `@Binding`。

---

## `@ObservedObject`

### 当前项目中的明确实例

`StreamingVideoPlayer.swift`：

```swift
@ObservedObject var viewModel: StreamingVideoViewModel
```

这说明当前项目并不是完全不用 `@ObservedObject`。

### 何时适合用

- 对象由外部创建
- 当前视图只是观察它
- 生命周期不由当前视图拥有

因此不要把“仓库主要不用 `@ObservedObject`”理解成“绝对禁止”。

---

## `@Published`

### 当前项目里的主要共享状态来源

#### `SocketManager`

典型字段：

- `connectionState`
- `pendingFriendRequests`
- `friendList`
- `chatHistory`
- `unreadCounts`
- `activeChatFriendId`
- `uploadSpeedStr`
- `downloadSpeedStr`

#### `AuthenticationService`

- `currentUser`
- `isAuthenticated`

#### 其他对象

- `TransferTaskManager`
- `DownloadDirectoryManager`
- `StreamingVideoViewModel`

### 更新注意事项

不是所有 `ObservableObject` 都标注了 `@MainActor`。

因此当你在异步上下文里更新这些状态时，要先确认：

- 当前是否已经在主线程
- 是否需要 `await MainActor.run { ... }`

尤其是 `SocketManager`、`AuthenticationService` 这类对象，不能默认线程安全地直接乱改。

---

## 当前项目中的异步接入模式

主流方式是：

- 在按钮 action 里包 `Task { }`
- 在 `.onAppear` 里发起异步加载
- 在服务层完成协议调用
- 返回结果后更新视图状态

典型形式：

```swift
Task {
    do {
        let result = try await service.fetchSomething()
        await MainActor.run {
            self.someState = result
        }
    } catch {
        await MainActor.run {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

当前项目没有统一的数据获取框架，也没有把网络请求封装成 Combine pipeline。

---

## 当前项目里最容易犯的包装器错误

### 1. 该共享的不共享

把本该来自 `SocketManager` 的数据又在 View 里复制一份独立真相。

### 2. 该局部的不局部

把只属于当前页面的弹窗状态、输入状态提成全局对象字段。

### 3. 忽略已存在例外

模板式地写“项目完全不用 `@ObservedObject`”或“所有认证服务都来自环境对象”，都不准确。

### 4. 在错误线程更新发布状态

如果更新发生在后台异步任务中，且对象未标注 `@MainActor`，要主动切回主线程。

---

## 检查单

- [ ] 当前状态是真正只属于这个 View 吗？
- [ ] 如果不是，是否应该交给现有共享状态源持有？
- [ ] 这个对象是当前 View 拥有的，还是外部传进来的？
- [ ] 更新 `@Published` 时线程是否安全？
- [ ] 有没有因为偷懒，在 View 里复制出第二份共享状态？

---

**核心原则**：先明确“谁拥有状态”，再决定用哪个属性包装器。
