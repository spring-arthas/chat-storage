# Transfer List UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve transfer-list header readability in light and dark mode, and remove the misleading white drag handle between the file area and transfer panel.

**Architecture:** Keep the change inside `MainChatStorage.swift` because both the transfer panel layout and the shared `FileTableHeaderView` live there already. Add a small theme-level style hook for the high-contrast transfer header so the visual change is explicit and testable, then remove the standalone drag-handle row without changing the fixed panel height.

**Tech Stack:** SwiftUI, XCTest

---

### Task 1: Add a testable transfer-header style hook

**Files:**
- Modify: `chat-storage/MainChatStorage.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testTransferHeaderUsesPrimaryTextContrastInBothThemes() throws {
    XCTAssertEqual(TelegramTheme.transferHeaderTextHex(isDark: true), TelegramTheme.textPrimaryHex)
    XCTAssertEqual(TelegramTheme.transferHeaderTextHex(isDark: false), TelegramTheme.lightTextPrimaryHex)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -only-testing:chat-storageTests/chat_storageTests/testTransferHeaderUsesPrimaryTextContrastInBothThemes`
Expected: FAIL because `TelegramTheme.transferHeaderTextHex` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
static func transferHeaderTextHex(isDark: Bool = true) -> String {
    isDark ? textPrimaryHex : lightTextPrimaryHex
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -only-testing:chat-storageTests/chat_storageTests/testTransferHeaderUsesPrimaryTextContrastInBothThemes`
Expected: PASS

### Task 2: Apply the UI polish in the transfer panel

**Files:**
- Modify: `chat-storage/MainChatStorage.swift`

- [ ] **Step 1: Apply the transfer-header emphasis**

Use the new high-contrast text color in the transfer-list header call site, without changing file-table column structure.

- [ ] **Step 2: Remove the drag-handle row**

Delete the standalone `Capsule()` row between the file browser and transfer list, while keeping the existing divider and fixed `transferPanelHeight`.

- [ ] **Step 3: Verify layout behavior**

Run: `xcodebuild -project chat-storage.xcodeproj -scheme chat-storage build`
Expected: `** BUILD SUCCEEDED **`
