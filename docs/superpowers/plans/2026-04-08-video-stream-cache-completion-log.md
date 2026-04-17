# Video Stream Cache Completion Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one completion log when a video file finishes sequential background caching from offset `0` through the full file size, and never print that log for seek-triggered restart pulls.

**Architecture:** Keep the change inside `VideoStreamCache` because that class already owns the sequential cache state, write count, start offset, and file name. Extract a tiny decision helper that can be unit tested from `chat-storageTests`, then call it from the existing full-load completion path so each newly played file can log once when its normal background pull really reaches full cache.

**Tech Stack:** Swift, XCTest, existing `print()` logging in the macOS app target

---

### Task 1: Define and test the completion-log gate

**Files:**
- Modify: `chat-storage/Services/VideoStreamCache.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testVideoStreamCacheCompletionLogOnlyForSequentialFullLoad() throws {
    XCTAssertNotNil(
        VideoStreamCache.completionLogMessage(
            fileName: "demo.mp4",
            fileSize: 1024,
            writtenBytes: 1024,
            downloadStartOffset: 0
        )
    )

    XCTAssertNil(
        VideoStreamCache.completionLogMessage(
            fileName: "demo.mp4",
            fileSize: 1024,
            writtenBytes: 768,
            downloadStartOffset: 0
        )
    )

    XCTAssertNil(
        VideoStreamCache.completionLogMessage(
            fileName: "demo.mp4",
            fileSize: 1024,
            writtenBytes: 1024,
            downloadStartOffset: 512
        )
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -only-testing:chat-storageTests/chat_storageTests/testVideoStreamCacheCompletionLogOnlyForSequentialFullLoad`
Expected: FAIL because `VideoStreamCache.completionLogMessage(...)` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
static func completionLogMessage(
    fileName: String,
    fileSize: Int64,
    writtenBytes: Int64,
    downloadStartOffset: Int64
) -> String? {
    guard downloadStartOffset == 0, writtenBytes == fileSize else { return nil }
    return "✅ [VideoStreamCache] 本次视频文件拉流完成，可以正常拖动播放，文件名称=\(fileName)，文件总流字节大小=\(fileSize)，已拉取的大小=\(writtenBytes)"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -only-testing:chat-storageTests/chat_storageTests/testVideoStreamCacheCompletionLogOnlyForSequentialFullLoad`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add chat-storage/Services/VideoStreamCache.swift chat-storageTests/chat_storageTests.swift docs/superpowers/plans/2026-04-08-video-stream-cache-completion-log.md
git commit -m "feat: log completed sequential video cache"
```

### Task 2: Emit the log from the real completion path

**Files:**
- Modify: `chat-storage/Services/VideoStreamCache.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testVideoStreamCacheCompletionLogIncludesExactByteCounts() throws {
    let message = try XCTUnwrap(
        VideoStreamCache.completionLogMessage(
            fileName: "movie.mov",
            fileSize: 4096,
            writtenBytes: 4096,
            downloadStartOffset: 0
        )
    )

    XCTAssertTrue(message.contains("文件名称=movie.mov"))
    XCTAssertTrue(message.contains("文件总流字节大小=4096"))
    XCTAssertTrue(message.contains("已拉取的大小=4096"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -only-testing:chat-storageTests/chat_storageTests/testVideoStreamCacheCompletionLogIncludesExactByteCounts`
Expected: FAIL until the exact log template is implemented.

- [ ] **Step 3: Write minimal implementation**

```swift
func markFullyLoaded() {
    cacheIOQueue.async { [weak self] in
        guard let self else { return }
        self.isFullyLoaded = true
        try? self.writeHandle?.close()
        self.writeHandle = nil
        self.notifyWaiters()
        if let message = Self.completionLogMessage(
            fileName: self.fileName,
            fileSize: self.fileSize,
            writtenBytes: self.writtenBytes,
            downloadStartOffset: self.downloadStartOffset
        ) {
            print(message)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -only-testing:chat-storageTests/chat_storageTests/testVideoStreamCacheCompletionLogOnlyForSequentialFullLoad -only-testing:chat-storageTests/chat_storageTests/testVideoStreamCacheCompletionLogIncludesExactByteCounts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add chat-storage/Services/VideoStreamCache.swift chat-storageTests/chat_storageTests.swift docs/superpowers/plans/2026-04-08-video-stream-cache-completion-log.md
git commit -m "feat: print full video cache completion log"
```
