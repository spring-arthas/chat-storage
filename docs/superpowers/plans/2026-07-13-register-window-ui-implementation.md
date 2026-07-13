# 注册窗口 UI 改造实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有固定登录窗体内实现与登录页一致、无裁切的双区注册界面。

**Architecture:** 保留 `RegisterView` 当前认证服务和注册方法，将 `body` 重组为左侧品牌头像区与右侧紧凑表单区。使用局部 ViewModifier 统一输入框视觉，使用固定错误区域和按钮高度控制布局稳定性。

**Tech Stack:** Swift 5、SwiftUI、AppKit

---

### Task 1: 重组注册页状态和布局

**Files:**
- Modify: `chat-storage/RegisterView.swift`

- [ ] 将旧单列 `VStack` 替换为宽度 40% / 60% 的无间隔 `HStack`。
- [ ] 删除旧的 `minHeight: 600`，使用 `AppWindowLayout.loginWidth` 和 `AppWindowLayout.loginHeight`。
- [ ] 将头像选择、品牌说明和返回登录入口放入左侧深色区域。
- [ ] 将四个注册字段、错误区域和注册按钮放入右侧表单。

### Task 2: 完善注册交互状态

**Files:**
- Modify: `chat-storage/RegisterView.swift`

- [ ] 增加用户名、密码、确认密码和邮箱的焦点枚举。
- [ ] 增加密码与确认密码显隐状态。
- [ ] 为字段绑定回车焦点流转和输入时错误清理。
- [ ] 增加固定高度错误区域。
- [ ] 增加注册按钮禁用判断、固定加载状态和重复提交保护。

### Task 3: 保持业务逻辑并完成静态检查

**Files:**
- Verify: `chat-storage/RegisterView.swift`

- [ ] 保留头像选择、裁剪、压缩和 Base64 编码逻辑。
- [ ] 保留现有输入校验、注册服务调用和成功返回登录逻辑。
- [ ] 检查 SwiftUI 括号、作用域和修饰器结构。
- [ ] 运行 `git diff --check`，不自动编译或启动应用。
- [ ] 只提交本次注册 UI 文件和文档，不纳入已有目录树改动与 `.superpowers/` 草稿。
