# 聊天输入区与混合附件消息 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复聊天输入交互并支持一条消息发送多个图片或普通文件。

**Architecture:** 输入区改为悬浮表情面板和统一待发送附件数组；附件模型统一为 `ChatAttachment`，保留旧图片字段和解析入口；上传复用现有独立文件传输连接，服务端只扩展 MIXED 内容校验。

**Tech Stack:** SwiftUI/AppKit/XCTest, Java 8/JUnit4, 现有自定义 socket 文件传输协议。

---

### Task 1: 输入区交互

**Files:** `chat-storage/Views/Chat/ChatInputBar.swift`, `chat-storage/Views/Chat/MacResponsiveTextView.swift`, `chat-storage/Views/Chat/EmojiPickerPanel.swift`, `chat-storage/MainChatStorage.swift`

- [x] 写测试断言表情面板使用悬浮层、工具栏不含剪刀/语音/抖一抖/电话/视频、文本视图处理 PNG/TIFF 剪贴板。
- [x] 将 `EmojiPickerPanel` 从 VStack 流式布局移到 toolbar 上方的 overlay，移除父层裁剪，保留 `showEmojiPicker.toggle()`。
- [x] 删除无效工具按钮及 `onSendNudge` 输入参数，保留已有双击反应逻辑。
- [x] 在 `CustomNSTextView` 中按 `NSPasteboard.PasteboardType.png/.tiff` 和 `NSImage(pasteboard:)` 读取图片，失败时调用 `super.paste`。

### Task 2: 统一附件模型

**Files:** `chat-storage/Services/Chat/ChatAttachmentModels.swift`, `chat-storage/Services/Chat/ChatMessageModels.swift`, `chat-storage/Services/Chat/ChatAttachmentUploadService.swift`

- [x] 写测试覆盖普通文件附件 JSON、MIXED v2 混合图片/文件解析和本地待发送附件创建。
- [x] 将可编码附件统一为 `ChatAttachment`，通过类型别名兼容现有 `ChatImageAttachment` 调用；普通文件不携带图片派生字段。
- [x] 将 `ChatMixedMessageContent.attachments` 改为统一附件数组，`ChatMessagePayload` 分别暴露 `images` 和 `files`。
- [x] 新增普通文件准备与上传入口，图片继续使用原图、缩略图和高清预览逻辑。

### Task 3: 发送、渲染和下载

**Files:** `chat-storage/Views/Chat/ChatInputBar.swift`, `chat-storage/MainChatStorage.swift`, `chat-storage/Views/Chat/ChatMessageRow.swift`

- [x] 写测试覆盖多选普通文件、混合附件乐观消息和失败重试保留整条附件列表。
- [x] 将待发送状态改为统一附件数组，附件选择器允许多选任意文件，图片生成预览，普通文件生成文件卡片。
- [x] 全部附件上传成功后构造 `MIXED v2` 并只发送一次；失败时显示错误并保留待重试数据。
- [x] 消息气泡渲染图片网格和普通文件卡片；普通文件点击后复用 `TransferTaskManager` 下载。

### Task 4: 服务端 MIXED 校验

**Files:** `/Users/hljy/IdeaProjects/code/net-server/src/main/java/com/alibaba/server/nio/service/file/handler/ChatAttachmentContentValidator.java`, `.../ChatAttachmentContentValidatorTest.java`

- [x] 写失败测试：MIXED v2 可接受属于发送方的普通文件，错误归属和大小仍被拒绝。
- [x] 将 MIXED 附件校验拆为通用文件校验与图片专有字段校验，允许 `kind=image|file`，继续限制最多 9 个附件。
- [x] 保持 IMAGE 和 MIXED v1 图片行为兼容，并补充普通文件 JSON 的测试数据。

### Task 5: 静态回归核对

- [x] 运行 `git diff --check`。
- [x] 静态确认主聊天连接、云盘上传下载、旧 IMAGE/MIXED v1 解析路径未被删除。
- [x] 按用户要求不在本轮编译或运行测试。
