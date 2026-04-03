# Quality Guidelines

> Code quality standards for backend (service/model) development.

---

## Required Patterns

### Singleton Pattern

All core services use `static let shared` with a private initializer:

```swift
class SocketManager: NSObject, ObservableObject {
    static let shared = SocketManager()
    private override init() { ... }
}
```

Never instantiate core services directly. The only place that wraps them in `@StateObject` is `chat_storageApp.swift`.

### Frame Protocol Usage

Always use `FrameBuilder.build()` for Codable payloads and `FrameParser.decodePayload()` for responses. Never construct raw frame bytes manually:

```swift
// Correct: FrameBuilder for Codable payload
let frame = try FrameBuilder.build(type: .userLoginReq, payload: request)

// Also correct: Frame() directly for empty-body requests
let frame = Frame(type: .dirListReq, data: Data(), flags: 0x00)

// Wrong: manually packing bytes
```

### Async/Await for Network Calls

All socket calls must use `async throws`. Never use completion handlers for new network code:

```swift
let responseFrame = try await socketManager.sendFrameAndWait(
    frame,
    expecting: .dirResponse,
    timeout: 15.0
)
```

### Thread Safety for Shared Mutable State

Use `ManagedCriticalState` (in `Services/ManagedCriticalState.swift`) for state shared across concurrent `Task`s:

```swift
private let state = ManagedCriticalState(TaskState())
state.withCriticalRegion { $0.tasks[id] = task }
```

For `SocketManager`'s pending-response maps, use `continuationLock` (NSLock) — always lock before accessing `activeContinuations` or `continuationTypeMap`.

### MD5 Calculation

Use `CommonCrypto` (already imported in `DirectoryService.swift`). **Do not use `CryptoKit`** — the project intentionally uses `CommonCrypto` for MD5.

### `@MainActor` for UI-Publishing Services

Services that publish `@Published` properties consumed directly by SwiftUI must be `@MainActor`:

```swift
@MainActor
class DirectoryService: ObservableObject { ... }
```

`SocketManager` and `AuthenticationService` are `ObservableObject` but NOT `@MainActor` — their UI updates require `await MainActor.run { }`.

---

## Forbidden Patterns

| Pattern | Why Forbidden |
|---------|--------------|
| `CryptoKit` for MD5 | Project uses `CommonCrypto`; do not mix crypto frameworks |
| Deleting stub files | `FileTransferService.swift` and `SocketManager+FrameHandling.swift` must stay |
| Adding logic to stub files | These files are Xcode reference holders only |
| `Thread.sleep` > 100ms | Blocks RunLoop; acceptable only in `switchConnection` (100ms) |
| Bypassing `PersistenceManager` for Core Data | All DB access goes through `PersistenceManager.shared` |
| Leaving `CheckedContinuation` without `resume` | Memory leak + permanent caller block |
| `try?` on frame/socket operations | Silently swallows errors that must surface to UI |
| Inline request struct defined outside function | Define inline `struct` inside the function body (existing pattern in `DirectoryService.swift`) |

---

## Concurrency Model

| Component | Threading |
|-----------|-----------|
| `SocketManager` | Runs on main RunLoop via `CFStreamCreatePairWithSocketToHost` + `StreamDelegate` |
| `TransferTaskManager` | Swift `Task { }` per transfer, max 5 concurrent, coordinated via `ManagedCriticalState` |
| `DirectoryService` | `@MainActor` — all methods run on main thread |
| `PersistenceManager` | `context.perform { }` for async, `context.performAndWait { }` for sync |

---

## Testing

Tests live in `chat-storageTests/`. Run with:

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'

# Single test
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage \
  -destination 'platform=macOS' \
  -only-testing:chat-storageTests/TestClassName/testMethodName
```

---

## Code Review Checklist

- [ ] No new logic added to stub files (`FileTransferService.swift`, `SocketManager+FrameHandling.swift`)
- [ ] All network calls use `async throws` (no completion handler pattern)
- [ ] Server response checks `code != 200` before using `data`
- [ ] Mutable shared state uses `ManagedCriticalState` or `continuationLock`
- [ ] MD5 uses `CommonCrypto`, not `CryptoKit`
- [ ] No dangling `CheckedContinuation` possible
- [ ] Emoji log prefix follows convention
