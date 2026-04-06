# 组件规范

> 当前项目中 SwiftUI 视图的常见写法、拆分方式和注入方式。

---

## 概述

本项目所有主要界面都基于 SwiftUI，但组件组织方式不是“高度原子化小组件”路线，而更偏向：

- 顶层大视图承载业务状态
- 通过私有计算属性拆分局部 UI
- 只在必要时抽成独立文件

这种风格在 `MainChatStorage.swift` 中最明显。

因此，组件规范的目标不是鼓励无限拆分，而是保证在当前风格下仍保持可读、可维护。

---

## 当前项目中的典型视图结构

多数视图会使用 `// MARK: -` 进行分区，常见顺序是：

```swift
struct SomeView: View {

    // MARK: - Environment Objects
    @EnvironmentObject var socketManager: SocketManager

    // MARK: - Bindings
    @Binding var isLoggedIn: Bool

    // MARK: - State Variables
    @State private var isLoading = false

    var body: some View {
        mainContent
    }

    // MARK: - Main Content
    private var mainContent: some View {
        // ...
    }
}
```

这不是强制语法规则，但它已经是当前仓库里最接近主流的组织方式。

---

## 组件拆分原则

### 适合拆成私有计算属性的情况

- 同一个视图内部存在明显的区块结构
- 需要把 `body` 从大段嵌套中解放出来
- 区块不需要单独复用，只是为了降低阅读成本

常见形式：

```swift
var body: some View {
    VStack {
        headerSection
        contentSection
        footerSection
    }
}

private var headerSection: some View { ... }
private var contentSection: some View { ... }
```

### 适合拆成独立 View 文件的情况

- 在多个页面 / 面板中复用
- 逻辑和状态已经形成一个相对独立的交互单元
- 单独维护比继续塞进 `MainChatStorage.swift` 更清晰

### 当前不建议的做法

- 只为了“看起来组件化”就把很小的局部片段拆出去
- 把强依赖父级状态的局部块过早抽成独立文件

在这个项目里，过度拆分通常会让状态流更难跟踪。

---

## 依赖注入方式

### 主流模式：`@EnvironmentObject`

应用入口 `chat_storageApp.swift` 注入了两个全局共享对象：

- `SocketManager`
- `AuthenticationService`

大多数需要它们的视图会这样接入：

```swift
@EnvironmentObject var socketManager: SocketManager
@EnvironmentObject var authService: AuthenticationService
```

这仍然是当前项目的主流模式。

### 局部拥有型对象：`@StateObject`

`MainChatStorage` 里当前会持有一些本页主导生命周期的共享对象，例如：

```swift
@StateObject private var transferManager = TransferTaskManager.shared
@StateObject private var downloadDirectoryManager = DownloadDirectoryManager.shared
```

这里的含义不是“创建新实例”，而是“这个页面负责观察并持有它们的生命周期绑定关系”。

### 已存在的历史例外

`RegisterView` 不是通过 `@EnvironmentObject` 使用认证服务，而是自己创建：

```swift
@StateObject private var authService: AuthenticationService
```

这是当前代码现状。后续修改认证流程时，不要假设注册页与登录页完全一致。

---

## `@ObservedObject` 的使用现状

项目并不是完全不使用 `@ObservedObject`。

现有明确例子：

- `StreamingVideoPlayer` 使用 `@ObservedObject var viewModel: StreamingVideoViewModel`

这是合理的，因为：

- `viewModel` 由外部创建并传入
- 当前 View 负责展示，不负责拥有它的创建逻辑

因此，规则应该是：

- 对于外部注入、由外部拥有生命周期的对象，可以使用 `@ObservedObject`
- 不要把“项目里基本少用”误写成“绝对禁止”

---

## 当前常见交互组件形式

### 1. `.sheet`

用于服务端配置等弹窗型子界面。

示例模式：

```swift
.sheet(isPresented: $showConfigServer) {
    ConfigServerView()
        .environmentObject(socketManager)
}
```

当前项目中，弹出子界面时常显式传递环境对象，保持依赖清晰。

### 2. `.overlay`

用于页面内浮层，比如：

- 备注名输入层
- 加载遮罩
- 错误态覆盖层

### 3. `.alert`

主要出现在 `MainChatStorage.swift` 这一类大页面中，用于操作失败或提示。

但注意：**并不是所有页面都统一使用 alert**。

例如：

- `LoginView` / `RegisterView` 更多使用页面内错误文本
- `NewFriendView` 也有本地错误展示

### 4. `.contextMenu`

目录树和文件项操作广泛使用右键上下文菜单，属于当前交互风格的重要部分。

---

## 窗口与尺寸现状

窗口尺寸主要由 `chat_storageApp.swift` 控制：

- 登录窗口宽高：`500 x 550`
- 主界面最小尺寸：`1080 x 700`

单个视图有时也会设置自己的最小尺寸，例如：

- `RegisterView`
- `StreamingVideoPlayer`

因此当前实际规则是：

- 主窗口切换与基础尺寸由应用入口控制
- 个别子界面 / 独立窗口可以在自身再加最小约束

不要沿用旧文档里已经过时的大窗口尺寸描述。

---

## 当前组件风格中的常见问题

### 1. 在 `body` 里夹带业务逻辑

不应该在视图构建过程中发请求、做解析、改共享状态。

应该把这些逻辑放到：

- 按钮 action
- `.onAppear`
- `.onChange`
- 提取出的私有方法

### 2. 继续把所有东西都塞进 `MainChatStorage.swift`

这是当前项目最容易继续恶化的点。

新需求进入主界面时，优先问：

- 能不能拆成私有计算属性？
- 能不能拆成一个只做展示的小 View？
- 能不能把业务逻辑挪到已有服务？

### 3. 让 View 直接承担协议层细节

View 可以发起动作，但不应直接承担：

- 帧构造
- JSON 解析
- 响应格式兼容

这些应留在服务层或协议边界。

---

## 代码审查检查单

- [ ] 视图层没有直接构造底层协议帧
- [ ] 大块 UI 已按区段拆成私有计算属性或合理子视图
- [ ] 共享依赖优先通过环境对象或既有状态持有方式接入
- [ ] 没有把短暂页面状态错误地提升成全局状态
- [ ] 弹窗、覆盖层、上下文菜单使用方式与现有项目风格一致
- [ ] 没有继续无边界扩大 `MainChatStorage.swift` 的职责

---

**核心原则**：优先保持依赖清晰和状态边界清晰，再考虑组件是否“足够优雅”。
