# 目录结构

> 当前项目中前端相关代码的真实分布方式。

---

## 概述

这个项目是一个 macOS SwiftUI 应用，但前端代码并不是全部集中在单一 `Views/` 目录中。

当前实际情况是：

- 主界面和大部分业务界面直接放在 `chat-storage/` 根目录
- 少量独立播放器视图放在 `chat-storage/Views/`
- 一些明明是 SwiftUI View 的文件，由于历史原因仍放在 `chat-storage/Services/`
- 主题色、局部展示逻辑、视图辅助结构有一部分直接定义在 `MainChatStorage.swift`

因此，判断“是不是前端代码”不能只看目录名。

---

## 当前前端相关文件分布

```text
chat-storage/
├── chat_storageApp.swift              # 应用入口，决定登录态 / 主界面切换
├── LoginView.swift                    # 登录界面
├── RegisterView.swift                 # 注册界面
├── ConfigServerView.swift             # 服务端地址配置弹窗
├── MainChatStorage.swift              # 登录后的主界面主壳层，体量最大
├── NewFriendView.swift                # 待处理好友申请界面
├── InputValidator.swift               # 输入校验辅助
├── ContentView.swift                  # 模板示例文件，不是当前真实入口
├── Views/
│   └── StreamingVideoPlayer.swift     # 视频播放界面与对应 ViewModel
└── Services/
    └── RecursiveDirectoryView.swift   # 目录树 SwiftUI 视图，路径上在 Services 但本质是前端代码
```

---

## 关键文件职责

### `chat_storageApp.swift`

真实应用入口，负责：

- 创建 `SocketManager.shared`
- 创建 `AuthenticationService.shared`
- 维护 `isLoggedIn`
- 切换 `LoginView` 与 `MainChatStorage`
- 设置窗口最小尺寸和登录 / 主界面尺寸策略
- 启动时尝试自动连接服务端

### `MainChatStorage.swift`

这是当前前端层的核心文件。

它同时承担：

- 云盘主界面
- 目录树和文件列表展示
- 分页与搜索状态
- 任务面板展示
- 文件详情侧栏
- 主题切换和大量视觉定义
- 好友 / 聊天区域的组织入口
- 各类弹窗、确认框、上下文菜单

这个文件目前是项目中最重要也最重的前端组合入口。

### `LoginView.swift` / `RegisterView.swift`

认证流的两个主要页面：

- `LoginView` 使用来自应用入口的环境对象
- `RegisterView` 当前是一个历史例外：它内部创建了自己的 `AuthenticationService` 实例，而不是复用 `@EnvironmentObject`

后续改认证流时必须意识到这个差异。

### `ConfigServerView.swift`

用于测试并切换服务端地址。它是一个弹窗型界面，当前主要和 `SocketManager` 的连接状态、目标 host / port 绑定。

### `NewFriendView.swift`

主要负责：

- 拉取待处理好友申请
- 渲染申请列表
- 处理接受 / 拒绝
- 接受时弹出备注名输入层

它依赖 `SocketManager` 作为共享状态源。

### `StreamingVideoPlayer.swift`

这是独立播放器窗口的主视图，特点包括：

- 使用 `NSViewRepresentable` 包装 `AVPlayerView`
- 通过 `@ObservedObject` 接收外部传入的 `StreamingVideoViewModel`
- 使用自定义底部控制条，而不是系统默认播放器控件

---

## 当前结构中的历史性例外

### `ContentView.swift`

这个文件仍然在仓库里，但现在更像是 SwiftUI 模板残留或演示文件，不是当前真实路由入口。

不要把它当成应用首页或主界面基线。

### `Services/RecursiveDirectoryView.swift`

尽管路径在 `Services/`，但它实际是 SwiftUI 目录树组件：

- `RecursiveDirectoryView`
- `DirectoryNodeView`

它属于前端代码，只是文件位置尚未回收整理。

### 主题与样式没有独立目录

当前主题色、按钮样式、`Color` / `NSColor` 扩展等都写在 `MainChatStorage.swift` 里，而不是单独抽成 `Theme/` 或 `UI/` 目录。

这意味着：

- 改主题前要先搜 `MainChatStorage.swift`
- 不要假设仓库里已经存在统一样式中心

---

## 当前前端模块关系

### 登录前

```text
chat_storageApp
→ LoginView
  → RegisterView
  → ConfigServerView
```

### 登录后

```text
chat_storageApp
→ MainChatStorage
  → RecursiveDirectoryView
  → NewFriendView
  → 文件列表 / 详情 / 任务面板
  → 视频打开动作
    → VideoWindowManager
    → StreamingVideoPlayer
```

---

## 命名与组织现状

| 类别 | 当前命名习惯 | 示例 |
|------|--------------|------|
| 视图文件 | 多为 `*View.swift` | `LoginView.swift`、`ConfigServerView.swift` |
| 主界面壳层 | 用业务名直接命名 | `MainChatStorage.swift` |
| 应用入口 | `*App.swift` | `chat_storageApp.swift` |
| 局部视图拆分 | 多用私有计算属性 | `private var loginContent: some View` |
| 目录树节点 | 组件内嵌结构 | `RecursiveDirectoryView`、`DirectoryNodeView` |

当前代码并没有做到完全统一命名，因此新增文件时优先贴近已有主要模式，而不是强行推翻现状。

---

## 修改此结构相关代码时要注意

- 不要把 `ContentView.swift` 当成路由入口。
- 不要因为文件在 `Services/` 就误判它一定是后端代码。
- 不要在 `MainChatStorage.swift` 里无节制继续塞入无关 UI 逻辑，优先评估是否能提取局部组件或私有计算属性。
- 不要假设 `Views/` 目录已经承载了全部前端可复用视图。

---

**核心原则**：按“真实职责”理解文件，不要只按“所在目录”理解文件。
