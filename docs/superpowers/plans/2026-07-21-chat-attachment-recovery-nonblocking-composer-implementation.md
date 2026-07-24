# Chat Attachment Recovery And Nonblocking Composer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复历史图片引用、附件连续上传与单附件重传，并让聊天输入区在后台传输期间保持可编辑和可发送。

**Architecture:** 聊天附件按 `clientMsgId` 进入有限并发的后台批次协调器，每个批次独占并复用一条 10087 连接，批次内部顺序上传。输入草稿状态与附件传输状态彻底分离；服务端对附件校验失败返回携带 `clientMsgId`、附件字段和 `fileId` 的结构化回执，客户端据此将具体附件降级为可重传状态。

**Tech Stack:** SwiftUI/AppKit/Swift Concurrency/Core Data、自定义 TCP 帧协议、Java 8/Fastjson/MyBatis/MySQL。

---

### Task 1: 修复上传连接真实状态与重连

**Files:**
- Modify: `chat-storage/SocketManager.swift`
- Modify: `chat-storage/Services/Chat/ChatAttachmentUploadService.swift`

- [x] **Step 1: 让断开连接始终重置真实状态**

`SocketManager.disconnect(notifyUI:)` 无论是否需要额外 UI 通知，都必须把 `connectionState` 更新为 `.disconnected`，并清空输入输出流；流代理回调只处理当前仍绑定的流，忽略旧连接延迟到达的事件。

- [x] **Step 2: 用真实可写流判断连接完成**

增加 `isTransportReady`，同时检查 `.connected`、输出流身份和 `.open/.writing` 状态；`ChatAttachmentUploadSession.ensureConnected()` 仅在该条件成立时返回。

- [x] **Step 3: 重连后等待新连接可写**

`reconnect()` 主动断开、让出一次事件循环、重新连接 10087，并等待 `isTransportReady`，避免下一附件在空流上发送 `RESUME_CHECK`。

### Task 2: 修复源文件校验与同路径重传

**Files:**
- Modify: `chat-storage/Services/Chat/ChatAttachmentModels.swift`
- Modify: `chat-storage/Services/Chat/ChatAttachmentUploadService.swift`
- Modify: `chat-storage/Services/Chat/ChatAttachmentTransferStore.swift`

- [x] **Step 1: 重传前校验持久化源文件**

校验文件存在、实际大小大于 0、实际大小与记录大小一致；分别返回“文件不存在”“文件为空”“大小已变化”的可操作错误。

- [x] **Step 2: 避免源路径等于稳定副本路径时自删除**

`prepareImageFile(fileURL:)` 和 `prepareAttachmentFile(fileURL:)` 比较标准化路径；相同时直接复用，不执行 `removeItem + copyItem`。

- [x] **Step 3: 缺失文件仍恢复重传记录**

Core Data 恢复 `PendingChatAttachment` 时不因文件已丢失而返回 `nil`，让用户点击重传后获得明确校验错误。

### Task 3: 实现消息级后台附件协调器

**Files:**
- Create: `chat-storage/Services/Chat/ChatAttachmentTransferCoordinator.swift`
- Modify: `chat-storage.xcodeproj/project.pbxproj`
- Modify: `chat-storage/MainChatStorage.swift`

- [x] **Step 1: 创建有限并发协调器**

协调器按 `batchId` 串行执行同一消息的上传或重传任务，并限制同时活跃批次数；同一附件的重复排队请求去重，但当前任务执行期间再次点击可排入下一次执行。

- [x] **Step 2: 首次发送立即清空草稿并后台入队**

本地乐观消息和 Core Data 批次创建成功后立即清空文字、附件和引用；上传任务交给协调器，`sendMessage()` 不等待附件完成。

- [x] **Step 3: 单附件重传排队且不锁输入区**

点击重传先把具体附件置为 `.waiting`，再按批次排队；上传中的其他消息和当前输入草稿互不影响。

- [x] **Step 4: 记录失败阶段**

通过连接、断点检查、元数据、数据发送、进度确认、完整性校验和最终确认的状态回调，在失败消息中保存最近阶段。

### Task 4: 修复 Enter、IME 与 placeholder

**Files:**
- Modify: `chat-storage/Views/Chat/ChatInputBar.swift`
- Modify: `chat-storage/Views/Chat/MacResponsiveTextView.swift`
- Modify: `chat-storage/MainChatStorage.swift`

- [x] **Step 1: 移除输入区上传锁**

删除 `ChatInputBar.isSending` 和 `MainChatStorage.isUploadingAttachment` 对附件选择、删除、发送按钮及文本编辑的控制。

- [x] **Step 2: 统一 Enter 行为**

普通 Enter 调用发送；Shift+Enter 插入换行；`NSTextView.hasMarkedText()` 为真时返回系统默认处理，让中文输入法先确认候选词。

- [x] **Step 3: 综合草稿状态显示 placeholder**

仅当文字为空、附件为空且引用为空时显示“请输入消息...”；表情插入文字后自动隐藏。

### Task 5: 返回并消费结构化附件校验错误

**Files:**
- Modify: `src/main/java/com/alibaba/server/nio/service/file/handler/ChatAttachmentContentValidator.java`
- Modify: `src/main/java/com/alibaba/server/nio/service/file/handler/TextTransmissionHandler.java`
- Modify: `chat-storage/Services/TransferModels.swift`
- Modify: `chat-storage/SocketManager.swift`
- Modify: `chat-storage/Services/Chat/ChatAttachmentTransferStore.swift`

- [x] **Step 1: 服务端抛出附件字段级异常**

附件不存在、归属错误、不可用、文件名或大小不一致时携带错误码、字段名和 `fileId`。

- [x] **Step 2: 聊天回执始终携带 clientMsgId**

成功和失败的 0x52 回执均返回原请求的 `clientMsgId`；附件校验失败时在 `data` 中附加 `attachmentField`、`fileId` 和 `errorCode`。

- [x] **Step 3: 客户端把被拒绝附件降级为失败**

客户端即使收到 `success=false` 包装也解析内部 `ChatReceiptDto`；按 `fileId` 定位附件，清空旧上传结果并置为 `.failed`，防止整条消息重复发送同一错误 JSON。

### Task 6: 扩展历史附件安全修复脚本

**Files:**
- Modify: `sql/repair_chat_attachment_message_453_20260721.sql`
- Create: `sql/audit_chat_attachment_references_20260721.sql`

- [x] **Step 1: 定向修复必须按每类候选唯一性判断**

原图、缩略图、预览图分别统计候选数量，只有三者都唯一且消息内容仍是预期坏值时才备份和更新。

- [x] **Step 2: 增加只读审计脚本**

扫描 IMAGE/MIXED 消息 JSON 中的原图、缩略图和预览图 ID，输出文件表缺失、逻辑删除或不可用的引用；不自动修改无法唯一匹配的数据。

### Task 7: 静态核对与用户验收交接

**Files:**
- Inspect: all files changed by Tasks 1-6

- [x] **Step 1: 运行静态差异检查**

Run: `git diff --check`

Expected: 无空白错误。按用户要求不执行 Xcode/Maven 编译、不启动服务、不运行自动化测试、不执行 SQL。

- [x] **Step 2: 核对云盘上传边界**

确认云盘 `TransferTaskManager` 仍调用 `uploadFile` 默认 `connectionReuse=false`，只有 `ChatAttachmentUploadSession` 使用 `CHAT_ATTACHMENT + connectionReuse=true`。

- [x] **Step 3: 输出手工验收清单**

覆盖重启历史图片、9 个不同附件、批次中途失败、单附件重传、并行继续聊天、Enter/Shift+Enter/中文输入法、placeholder、服务端附件拒绝和历史 SQL 修复前后校验。
