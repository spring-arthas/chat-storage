# 聊天媒体消息与可靠性第二阶段 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 闭环聊天图片消息：粘贴图片、独立上传、发送 IMAGE 消息、缩略图展示、历史恢复，并补强服务端 `clientMsgId` 幂等能力。

**Architecture:** 客户端新增聊天附件模型和上传服务，图片上传使用独立 `SocketManager` 连接 10087，不切换主聊天连接。服务端对 `user_friend_message` 的新增字段采用运行时列探测，有列则写入幂等与引用数据，无列则降级保持旧表可用。

**Tech Stack:** SwiftUI/AppKit/XCTest, Java 8/JUnit4/MyBatis, 自定义 `0xFACE` 二进制帧协议，现有文件上传协议。

---

### Task 1: 客户端图片附件模型

**Files:**
- Create: `/Users/hljy/macProjects/chat-storage/chat-storage/Services/Chat/ChatAttachmentModels.swift`
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage.xcodeproj/project.pbxproj`
- Test: `/Users/hljy/macProjects/chat-storage/chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: 写失败测试**

验证 `ChatImageAttachment` 能编码/解码 JSON，并能构建给 `FileThumbnailService` 使用的 `DirectoryItem`。

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
xcodebuild test -project /Users/hljy/macProjects/chat-storage/chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testChatImageAttachmentContentRoundTrips
```

Expected: `ChatImageAttachment` 不存在导致编译失败。

- [ ] **Step 3: 实现最小模型**

新增 `ChatImageAttachment`，字段为 `kind/fileId/fileName/fileSize/mimeType`，提供 `contentString()`、`parse(_:)` 和 `directoryItem()`。

- [ ] **Step 4: 更新 Xcode 工程引用并跑测试**

Run 同 Step 2，Expected: PASS。

### Task 2: 客户端图片上传服务

**Files:**
- Create: `/Users/hljy/macProjects/chat-storage/chat-storage/Services/Chat/ChatAttachmentUploadService.swift`
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage.xcodeproj/project.pbxproj`
- Test: `/Users/hljy/macProjects/chat-storage/chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: 写失败测试**

验证服务能从 `NSImage` 生成 PNG 临时文件名和 MIME 元数据，不依赖真实网络。

- [ ] **Step 2: 运行测试确认失败**

Run targeted XCTest，Expected: 类型不存在导致失败。

- [ ] **Step 3: 实现最小服务**

新增 `ChatAttachmentUploadService`，负责保存临时 PNG、独立连接上传端口并返回 `ChatImageAttachment`。网络上传方法保留可注入 uploader，测试使用假的 uploader。

- [ ] **Step 4: 运行测试确认通过**

Run targeted XCTest，Expected: PASS。

### Task 3: 客户端发送和渲染 IMAGE 消息

**Files:**
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/Views/Chat/ChatInputBar.swift`
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/Views/Chat/ChatMessageRow.swift`
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/MainChatStorage.swift`

- [ ] **Step 1: 输入区支持发送图片**

将图片预览里的发送按钮回调改为 `onSendImage`，支持上传中状态和失败文案。

- [ ] **Step 2: 会话层调用上传服务**

`ChatDetailView` 调用 `ChatAttachmentUploadService.uploadImage`，上传成功后调用 `socketManager.sendChatMessage(... msgType: "IMAGE")`。

- [ ] **Step 3: 气泡渲染图片缩略图**

`ChatMessageRow` 对 IMAGE 内容解析 `ChatImageAttachment`，用 `FileThumbnailService.thumbnail(for:)` 加载缩略图；失败时显示 `[图片]`。

- [ ] **Step 4: 运行客户端全量测试**

Run:

```bash
xcodebuild test -project /Users/hljy/macProjects/chat-storage/chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'
```

Expected: PASS。

### Task 4: 后端 clientMsgId 幂等与引用字段兼容

**Files:**
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/repository/dataobject/UserFriendMessageDo.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/service/dto/ChatHistoryItemDto.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/mapper/ChatMessageRepository.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/service/ChatMessageService.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/service/impl/ChatMessageServiceImpl.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/service/chat/handler/ChatRealDataHandler.java`
- Test: `/Users/hljy/IdeaProjects/net-server/src/test/java/com/alibaba/server/nio/repository/chat/service/ChatMessageServiceCompatibilityTest.java`

- [ ] **Step 1: 写失败测试**

测试字段能力探测对象在缺少可选列时允许 TEXT 保存降级，在存在 `client_msg_id` 时会先查重。

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn -Dtest=ChatMessageServiceCompatibilityTest test
```

Expected: 新能力不存在导致失败。

- [ ] **Step 3: 实现兼容字段能力**

新增列能力检测和查询方法，有列则写 `clientMsgId/quote*`，无列则跳过。

- [ ] **Step 4: 修改 0x50 handler**

`ChatRealDataHandler` 将 `clientMsgId` 和 quote 字段传入 service，回执和推送继续返回对应字段。

- [ ] **Step 5: 跑后端全量测试**

Run:

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn test
```

Expected: PASS。

### Task 5: 最终回归

**Files:**
- No direct source edit unless verification reveals defects.

- [ ] **Step 1: 客户端全量测试**

Run:

```bash
xcodebuild test -project /Users/hljy/macProjects/chat-storage/chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'
```

- [ ] **Step 2: 后端 JDK8 全量测试**

Run:

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn test
```

- [ ] **Step 3: 手工验证清单**

确认登录、好友列表、聊天 TEXT、好友备注 `0x57/0x58`、云盘上传下载、缩略图和视频在线播放代码路径未被破坏。
