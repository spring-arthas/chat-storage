# 登录窗口 UI 改造实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 macOS 登录窗口改造成已确认的横向双区工作台式界面，并保证现有认证、注册和服务器配置功能不受影响。

**Architecture:** 保留 `LoginView` 现有环境对象、绑定状态和 `handleLogin()` 业务入口，只重组 SwiftUI 展示层。窗口尺寸继续由 `AppWindowLayout` 统一管理，登录页面拆分为品牌区、表单区、输入组件、登录按钮和底部入口，避免固定窗体内出现遮挡。

**Tech Stack:** Swift 5、SwiftUI、AppKit、XCTest、Xcode/macOS

---

### Task 1: 固化登录窗口尺寸约束

**Files:**
- Modify: `chat-storageTests/chat_storageTests.swift`
- Modify: `chat-storage/chat_storageApp.swift`

- [ ] **Step 1: 修改窗口尺寸测试并验证失败**

将 `testMainWindowLayoutBoundsAreFixed()` 中登录窗口断言调整为：

```swift
XCTAssertEqual(AppWindowLayout.loginWidth, 720)
XCTAssertEqual(AppWindowLayout.loginHeight, 456)
```

运行：

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testMainWindowLayoutBoundsAreFixed
```

预期：测试失败，实际值仍为 `500` 和 `550`。

- [ ] **Step 2: 更新生产代码中的窗口尺寸**

将 `AppWindowLayout` 的登录窗口尺寸改为：

```swift
static let loginWidth: CGFloat = 720
static let loginHeight: CGFloat = 456
```

- [ ] **Step 3: 重新运行尺寸测试**

运行同一条 `xcodebuild test` 命令。

预期：目标测试通过。

### Task 2: 实现双区登录界面

**Files:**
- Modify: `chat-storage/LoginView.swift`

- [ ] **Step 1: 清理不适合正式界面的默认状态**

将 `username` 和 `password` 初始值改为空字符串，增加密码显隐状态：

```swift
@State private var username = ""
@State private var password = ""
@State private var isPasswordVisible = false
```

- [ ] **Step 2: 将页面拆分为左右两个稳定区域**

`loginContent` 使用固定比例横向布局：

```swift
HStack(spacing: 0) {
    brandPanel
        .frame(width: AppWindowLayout.loginWidth * 0.4)
    loginForm
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

左侧使用深色固定背景，包含品牌、说明和连接状态；右侧使用语义化系统背景色并垂直居中表单。

- [ ] **Step 3: 实现输入框和密码显隐交互**

账号与密码输入框使用统一的局部组件样式。密码区域根据 `isPasswordVisible` 切换 `TextField` 和 `SecureField`，右侧使用 `eye` / `eye.slash` 图标按钮，按钮提供可访问性标签。

- [ ] **Step 4: 实现稳定的错误区和登录按钮**

错误区固定最小高度并最多显示两行；删除旧页面重复错误展示。密码区域和登录按钮之间保留至少 18pt 间距。加载中按钮显示 `ProgressView` 与“正在登录…”，按钮尺寸不发生变化。

- [ ] **Step 5: 保留注册和服务器设置入口**

表单底部左侧调用 `showConfigServer = true`，右侧调用 `showRegister = true`。继续使用现有 `.sheet` 和 `RegisterView` 分支，不增加新的导航状态。

### Task 3: 构建与视觉验证

**Files:**
- Verify: `chat-storage/LoginView.swift`
- Verify: `chat-storage/chat_storageApp.swift`

- [ ] **Step 1: 运行完整单元测试**

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS'
```

预期：已有测试和新增尺寸断言全部通过。

- [ ] **Step 2: 运行 Debug 构建**

```bash
xcodebuild build -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS'
```

预期：输出 `BUILD SUCCEEDED`。

- [ ] **Step 3: 启动应用并检查登录窗口**

验证以下状态：

- 所有内容完整显示在 `720 × 456` 窗体内。
- 密码框和登录按钮之间有清晰间距。
- 登录按钮下方两项入口完整可见。
- 错误提示不会覆盖登录按钮或底部入口。
- 深色与浅色外观中文字均可读。
- 账号、密码、回车提交、登录加载、注册切换和服务器设置保持可用。

- [ ] **Step 4: 提交实现代码**

只暂存本次修改的文件以及测试文件中的窗口尺寸断言，不纳入 `FileDto.swift` 的已有改动或 `.superpowers/` 视觉草稿：

```bash
git add chat-storage/LoginView.swift chat-storage/chat_storageApp.swift chat-storageTests/chat_storageTests.swift docs/superpowers/plans/2026-07-13-login-window-ui-implementation.md
git commit -m "feat: 重构 macOS 登录窗口界面"
```
