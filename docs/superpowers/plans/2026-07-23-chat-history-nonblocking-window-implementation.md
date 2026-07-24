# Chat History Nonblocking Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep chat scrolling responsive by bounding the rendered history window and moving all database, parsing, merge, sorting, and image work off the UI thread.

**Architecture:** Core Data remains the complete history store while `SocketManager.chatHistory` becomes a bounded visible projection. A pure window policy merges older/newer pages off-main, cursor state tracks both directions, and image rows never auto-fetch originals.

**Tech Stack:** Swift 5/6, SwiftUI for macOS, Core Data, XCTest, ImageIO.

---

### Task 1: Bounded history window

**Files:**
- Modify: `chat-storage/Services/Chat/ChatMessageModels.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [x] Write tests proving latest/newer merges keep the newest 160 messages and older merges keep the oldest side of the current window while reporting which side was trimmed.
- [x] Run the focused tests and confirm they fail because `ChatHistoryWindowPolicy` and `hasNewer` do not exist.
- [x] Add `ChatHistoryMergeDirection`, `ChatHistoryWindowResult`, `ChatHistoryWindowPolicy`, and `ChatHistoryCursorState.hasNewer`.
- [x] Re-run the focused tests and confirm they pass.

### Task 2: Bidirectional indexed local paging

**Files:**
- Modify: `chat-storage/Services/Chat/ChatHistoryStore.swift`
- Modify: `chat-storage/chat_storage.xcdatamodeld/chat_storage.xcdatamodel/contents`
- Test: `chat-storageTests/chat_storageTests.swift`

- [x] Write a failing test for ascending `fetchNewer(afterMessageId:limit:)` pagination.
- [x] Write a failing source test for a composite account/friend/message fetch index.
- [x] Implement `fetchNewer` on the existing background context and add the model fetch index.
- [x] Re-run both focused tests.

### Task 3: Nonblocking timeline publication and double-ended window loading

**Files:**
- Modify: `chat-storage/MainChatStorage.swift`
- Modify: `chat-storage/SocketManager.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [x] Write source and behavior tests requiring window merges to run in `Task.detached`, incremental pages to be persisted before one UI merge, and message-count auto-scroll to be removed.
- [x] Add older/newer window load tasks, bottom cursor loading, window revision scroll restoration, and bounded publishing.
- [x] Preserve the latest conversation summary independently when an older window trims newer rows.
- [x] Re-run history-focused tests.

### Task 4: Parse message payload once

**Files:**
- Modify: `chat-storage/Services/Chat/ChatMessageModels.swift`
- Modify: `chat-storage/Views/Chat/ChatMessageRow.swift`
- Modify: `chat-storage/SocketManager.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [x] Write a failing test that `ChatMessage` updates its prepared payload when content changes.
- [x] Write a failing source test that the row body does not call `ChatMessagePayload.parse` and does not enable text selection.
- [x] Add a prepared payload to `ChatMessage`, refresh it from the controlled content update path, and render it directly.
- [x] Re-run focused tests.

### Task 5: Prevent scroll-triggered original image traffic

**Files:**
- Modify: `chat-storage/Services/Chat/ChatAttachmentModels.swift`
- Modify: `chat-storage/Views/Chat/ChatMessageRow.swift`
- Modify: `chat-storage/Services/FileThumbnailService.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [x] Write a failing test proving bubble thumbnails prefer thumbnail, then preview, and return `nil` when neither derived file exists.
- [x] Write a failing source test proving a missing derived image shows a placeholder without calling the network thumbnail loader.
- [x] Implement the derived-only bubble source and decode cached thumbnail bytes through ImageIO away from the main actor.
- [x] Re-run image-focused tests.

### Task 6: Verification

**Files:**
- Test: `chat-storageTests/chat_storageTests.swift`

- [x] Run all chat history and image regression tests.
- [x] Run the complete `chat-storageTests` target.
- [x] Run `xcodebuild build -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'`.
- [x] Inspect the final diff to confirm no unrelated user changes were reverted or staged.
