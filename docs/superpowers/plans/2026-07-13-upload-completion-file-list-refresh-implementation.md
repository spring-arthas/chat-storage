# 上传完成自动刷新文件列表 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 上传任务成功后在主线程合并刷新当前文件列表，下载任务完成不触发刷新。

**Architecture:** `TransferTaskManager` 发布上传完成通知，`MainChatStorage` 使用可取消的延迟 Task 合并300毫秒内的连续通知。通知发布和 SwiftUI 状态更新均位于 `MainActor`。

**Tech Stack:** Swift 5、Swift Concurrency、NotificationCenter、SwiftUI、XCTest。

---

### Task 1: 区分上传和下载完成事件

**Files:**
- Modify: `chat-storage/Services/TransferTaskManager.swift`
- Modify: `chat-storageTests/chat_storageTests.swift`

- [ ] 写失败测试，断言上传返回 true、下载返回 false。
- [ ] 运行定向 XCTest，确认辅助方法不存在而失败。
- [ ] 实现类型判断，并仅在上传最终成功后切到 MainActor 发布通知。
- [ ] 运行定向 XCTest，确认通过。

### Task 2: 主线程合并刷新

**Files:**
- Modify: `chat-storage/MainChatStorage.swift`

- [ ] 新增 `uploadTaskDidComplete` 通知名称。
- [ ] 新增可取消的 `uploadCompletionRefreshTask` 状态。
- [ ] 监听通知，300毫秒内的新通知取消并重建延迟任务。
- [ ] 延迟结束后调用 `loadCurrentFiles()`，视图消失时取消任务。
- [ ] 运行 chat-storage 测试与 Debug 编译。
