# Logging Guidelines

> How logging is done in this project.

---

## Overview

Logging uses Swift's `print()` with emoji-prefixed messages. No third-party logging library. All output goes to the Xcode console / stdout.

---

## Emoji Convention

| Emoji | Domain | When to use |
|-------|--------|-------------|
| `📂` | Directory / file | Directory CRUD, file listing, path operations |
| `📤` | Sending | Before sending a frame to the server |
| `📥` | Receiving | After receiving a server response |
| `✅` | Success | Operation completed successfully |
| `❌` | Error / failure | Caught errors, failed operations |
| `⚠️` | Warning | Recoverable issues, stale bookmarks |
| `🔌` | Connection | Socket connect / disconnect events |
| `📡` | Network | Socket stream opened, waiting for data |
| `🔐` | Auth | Login, register, logout |
| `💾` | Persistence | Core Data save, bookmark operations |
| `🔍` | Search / lookup | Fetching details, searching records |
| `🏃` | Task / progress | Transfer task state changes |

---

## Log Format

```swift
// Start of operation
print("📂 开始加载目录树...")

// Received data with context
print("📥 收到目录响应，开始解析...")

// Success with count
print("✅ 目录树加载完成，共 \(directoryItems.count) 个顶级项")

// Error with context
print("❌ Socket 写入失败: \(outputStream.streamError?.localizedDescription ?? "未知错误")")

// Persistence operations
print("💾 Persistence: Attempting to create bookmark for \(fileUrl.path)")
print("✅ Persistence: Bookmark created successfully (\(bookmark.count) bytes)")
```

---

## What to Log

- Start and end of every network operation
- Transfer task state transitions (submit, start, complete, fail, pause)
- Socket connection state changes
- Core Data operations (save, fetch, bookmark create/resolve)
- All caught errors with enough context to diagnose

---

## What NOT to Log

- User passwords or credentials (never log auth request body)
- Full file content (log only: name, size, type)
- Per-chunk progress during file transfer (only log at meaningful milestones)
- `// print(...)` commented-out noise — either keep it or remove it

---

## Verbose Debug Logs

Some frame-level logs are commented out for normal operation:

```swift
// print("📤 发送帧: \(frame.type.description), 长度: \(data.count) 字节")
```

Temporarily uncomment when debugging protocol issues. Do not leave verbose frame logs uncommented in committed code.
