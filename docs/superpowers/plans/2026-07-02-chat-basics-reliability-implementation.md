# 聊天基础体验与可靠性第一阶段 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现聊天基础体验第一阶段：可靠发送、emoji 输入、引用回复、消息菜单、本地删除/撤回协议、粘贴图片预览，并保证协议帧不与现有好友备注 `0x57/0x58` 冲突。

**Architecture:** 客户端先补协议常量、DTO 可选字段和可靠发送状态，然后把现有聊天 UI 行为就地增强，避免一次性大规模移动文件造成 Xcode 工程风险。服务端补新客户端 `0x50` 正式处理、`0x52` 回执、`0x51` 在线推送、`0x59/0x5A/0x5B` 消息动作帧，并保持老文本帧逻辑不变。

**Tech Stack:** SwiftUI/AppKit/XCTest, Java 8/JUnit4/MyBatis, 自定义 `0xFACE` 二进制帧协议。

---

### Task 1: 客户端协议与 DTO 红线

**Files:**
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/Models/frame/FrameTypeEnum.swift`
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/Services/TransferModels.swift`
- Test: `/Users/hljy/macProjects/chat-storage/chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: 写失败测试**

添加 XCTest，验证 `0x57/0x58` 保留给好友备注，新增聊天动作帧使用 `0x59/0x5A/0x5B`，并验证聊天 DTO 可解析新增可选字段。

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests
```

Expected: 新增帧类型或 DTO 字段不存在导致失败。

- [ ] **Step 3: 实现最小代码**

在 `FrameTypeEnum` 增加：

```swift
case chatMessageActionReq = 0x59
case chatMessageActionResp = 0x5A
case chatMessageActionPush = 0x5B
```

在聊天 DTO 中增加 `clientMsgId`、引用字段、删除/撤回字段，全部为可选。

- [ ] **Step 4: 运行测试确认通过**

Run 同 Step 2，Expected: PASS。

### Task 2: 客户端可靠发送状态

**Files:**
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/MainChatStorage.swift`
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/SocketManager.swift`
- Test: `/Users/hljy/macProjects/chat-storage/chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: 写失败测试**

添加纯 Swift 测试，验证本地消息可通过 `clientMsgId` 匹配回执，且不会更新第一条 `messageId == nil` 的无关消息。

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests
```

- [ ] **Step 3: 实现最小代码**

扩展 `ChatMessage`，加入 `clientMsgId`、`errorMessage`、`quote`、`retracted` 状态；`SocketManager.sendChatMessage` 生成 `clientMsgId` 并写入 `ChatSendRequestDto`；`0x52` handler 优先按 `clientMsgId` 匹配。

- [ ] **Step 4: 添加发送超时**

为每条发送中消息启动超时任务，超时后仅标记对应 `clientMsgId` 的消息为失败。

### Task 3: 输入区、emoji、引用和消息菜单

**Files:**
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/MainChatStorage.swift`

- [ ] **Step 1: 改造 `MacResponsiveTextView`**

增加 `onPasteImage` 和 `insertToken` 支持，保留 Enter 发送、Shift/Option+Enter 换行。

- [ ] **Step 2: 改造 emoji 行为**

点击 emoji 时插入到文本光标位置，保存最近使用，不再直接发送单个 emoji。

- [ ] **Step 3: 增加引用回复**

消息右键菜单增加“引用”，输入区显示引用预览，发送后清空引用。

- [ ] **Step 4: 增加消息菜单**

消息右键菜单增加复制、本地删除、撤回；复制走 `NSPasteboard`，删除/撤回调用 SocketManager 新动作方法。

### Task 4: 粘贴图片预览

**Files:**
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/MainChatStorage.swift`
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/SocketManager.swift`

- [ ] **Step 1: 捕获 Cmd+V 图片**

`CustomNSTextView.paste(_:)` 检测 `NSImage`，阻止默认粘贴并回调上层。

- [ ] **Step 2: 预览与发送保护**

展示图片预览。后端 IMAGE 支持未验证时，不发送非法消息；只展示明确失败。

### Task 5: 后端聊天发送和动作协议

**Files:**
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/service/chat/handler/ChatRealDataHandler.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/service/chat/handler/ChatDecodeHandler.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/handler/event/concret/WriteEventHandler.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/service/ChatMessageService.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/service/impl/ChatMessageServiceImpl.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/mapper/ChatMessageRepository.java`
- Modify: `/Users/hljy/IdeaProjects/net-server/src/main/java/com/alibaba/server/nio/repository/chat/repository/dataobject/UserFriendMessageDo.java`
- Test: `/Users/hljy/IdeaProjects/net-server/src/test/java/com/alibaba/server/nio/service/chat/ChatClientFrameProtocolTest.java`

- [ ] **Step 1: 写失败测试**

添加 JUnit 测试验证 `WriteEventHandler` 能透传 `0x51/0x52/0x54/0x56/0x58/0x5A/0x5B`，并验证 `0x57/0x58` 不被聊天动作占用。

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn -Dtest=ChatClientFrameProtocolTest test
```

- [ ] **Step 3: 实现最小代码**

`ChatDecodeHandler` 映射 `0x59`；`ChatRealDataHandler.clientFrameHandler` 处理 `0x50` 和 `0x59`；`WriteEventHandler` 允许 `0x5A/0x5B` 响应帧直接输出。

- [ ] **Step 4: 落库与历史响应**

新增 `ChatMessageService.sendClientMessage`、`deleteLocal`、`retract`。新增数据库字段只允许 nullable additive；如果测试环境表暂未有新列，代码必须优雅降级，不影响普通 TEXT 发送。

### Task 6: 验证

**Files:**
- No direct source edit unless verification reveals defects.

- [ ] **Step 1: 客户端构建/测试**

Run:

```bash
xcodebuild test -project /Users/hljy/macProjects/chat-storage/chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'
```

- [ ] **Step 2: 后端 JDK8 测试**

Run:

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home mvn test
```

- [ ] **Step 3: 回归检查**

确认登录、好友列表、好友备注 `0x57/0x58`、聊天历史、文件列表、上传、缩略图、视频在线播放协议未被改动或破坏。

