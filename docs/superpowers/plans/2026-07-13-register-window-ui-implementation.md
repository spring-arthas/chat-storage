# 两步注册窗口 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将注册页改为与登录页一致的品牌外壳，并提供基础资料、安全设置两步注册流程。

**Architecture:** 保留 `RegisterView` 单文件和现有注册业务，把页面状态扩展为两个步骤。左侧复制登录页品牌区，右侧根据步骤切换局部表单，第一步校验账号与邮箱，第二步调用现有注册方法。

**Tech Stack:** Swift 5、SwiftUI、AppKit

---

### Task 1: 对齐登录页外壳

**Files:**
- Modify: `chat-storage/RegisterView.swift`

- [ ] 将左侧头像品牌区替换为与 `LoginView` 一致的品牌标记、主文案、说明、装饰圆环和连接状态。
- [ ] 保持 `AppWindowLayout.loginWidth`、`AppWindowLayout.loginHeight` 和 40% / 60% 双栏比例。
- [ ] 将头像选择移动到右侧第一步表单。

### Task 2: 实现两步注册状态

**Files:**
- Modify: `chat-storage/RegisterView.swift`

- [ ] 增加基础资料和安全设置步骤枚举及当前步骤状态。
- [ ] 增加步骤标题、说明和双段进度条。
- [ ] 第一步展示头像、账号、邮箱和下一步按钮。
- [ ] 第二步展示密码、确认密码、上一步和创建账号按钮。
- [ ] 前后切换保留当前表单内容并更新焦点。

### Task 3: 完成步骤校验和视觉统一

**Files:**
- Modify: `chat-storage/RegisterView.swift`

- [ ] 第一步复用 `InputValidator` 校验账号和邮箱。
- [ ] 第二步继续使用原有密码、确认密码和完整注册校验。
- [ ] 将输入框、错误区域和主按钮尺寸改为与登录页一致。
- [ ] 保留头像选择、裁剪、压缩、Base64 编码和注册协议调用。
- [ ] 按用户要求不运行编译、测试或应用启动，由用户在 Xcode 中验证。
