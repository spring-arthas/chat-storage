# Cache Cleanup Connection Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep cache cleanup filesystem-only and prevent server-connection tests from destroying the authenticated main Socket session.

**Architecture:** The server configuration sheet probes an endpoint with an independent `NWConnection`; it never disconnects or reconnects the shared `SocketManager` during a test. A confirmed server switch explicitly invalidates the local session and returns the app to login. Directory responses without an explicit success marker are errors, so authentication failures cannot become empty data.

**Tech Stack:** SwiftUI, Network framework, XCTest, existing `SocketManager` and `DirectoryService`.

---

### Task 1: Add regression tests

**Files:**
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storageTests/chat_storageTests.swift`

- [ ] Add a test that the server test flow uses an independent probe and contains no shared-socket disconnect/switch calls.
- [ ] Add a test that a directory response with `NOT_LOGGED_IN` and no `data` throws instead of returning an empty list.
- [ ] Run the two tests and verify they fail for the current implementation.

### Task 2: Isolate server probing

**Files:**
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/ConfigServerView.swift`

- [ ] Add a small `ServerEndpoint` value type and an `NWConnection`-based probe.
- [ ] Change `handleTestConnection` to probe without calling `socketManager.disconnect()` or `switchConnection`.
- [ ] Only switch the shared connection after the user confirms a different endpoint; invalidate the local authenticated session when that happens.

### Task 3: Make directory parsing fail closed

**Files:**
- Modify: `/Users/hljy/macProjects/chat-storage/chat-storage/Services/DirectoryService.swift`

- [ ] Require an explicit successful `success=true`, `code=200`, or `status=success` marker before accepting a response with no `data`.
- [ ] Expose a narrow test hook for the parser and preserve successful mutation responses that intentionally omit `data`.

### Task 4: Verify

**Files:**
- No additional files.

- [ ] Run the targeted XCTest cases.
- [ ] Run the complete `chat-storageTests` target.
- [ ] Confirm the cache cleanup source still has no Socket lifecycle calls and report any environment limitation for app-level verification.
