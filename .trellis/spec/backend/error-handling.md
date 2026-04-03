# Error Handling

> How errors are defined, propagated, and handled in this project.

---

## Overview

All errors conform to `LocalizedError` with Chinese-language `errorDescription`. Errors propagate via Swift's `throws` / `async throws`. The top-level catch always lives in the View layer, which presents an alert.

---

## Error Types

### `SocketError` — `SocketManager.swift`

Transport-level TCP errors:

```swift
enum SocketError: LocalizedError {
    case connectionFailed   // 连接失败
    case notConnected       // Socket 未连接
    case sendFailed         // 发送数据失败
    case timeout            // 等待响应超时
    case invalidResponse    // 响应数据无效
    case connectionClosed   // 连接已关闭
    case unknown
}
```

### `FrameError` — `Models/frame/Frame.swift`

Protocol framing errors:

```swift
enum FrameError: LocalizedError {
    case invalidMagic       // 魔数不匹配 (expected 0xFACE)
    case invalidType(UInt8) // 未知帧类型
    case invalidLength
    case insufficientData
    case encodingFailed
    case decodingFailed
}
```

### `AuthError` — `Services/AuthenticationService.swift`

```swift
enum AuthError: LocalizedError {
    case loginFailed(String)    // server message
    case registerFailed(String)
}
```

### `DirectoryError` — `Services/DirectoryService.swift`

Business-logic errors for directory and file operations:

```swift
enum DirectoryError: LocalizedError {
    case serverError(code: Int, message: String)
    case invalidResponse(String)
    case uploadFailed(String)
    case downloadFailed(String)
}
```

---

## Propagation Pattern

Services throw typed errors up; Views catch and display alerts:

```swift
// Service layer
func loadDirectoryTree() async throws -> [DirectoryItem] {
    let responseFrame = try await socketManager.sendFrameAndWait(
        frame, expecting: .dirResponse, timeout: 15.0
    )
    // throws DirectoryError or SocketError
}

// View layer
Task {
    do {
        directoryTree = try await directoryService.loadDirectoryTree()
    } catch {
        alertMessage = error.localizedDescription
        showingAlert = true
    }
}
```

---

## Server Response Error Pattern

Always check `code != 200` before reading `data`. Use `DirectoryError.serverError` for server-side failures:

```swift
guard let dict = try? FrameParser.decodeAsDictionary(responseFrame) else {
    throw DirectoryError.invalidResponse("无法解析响应为字典")
}
if let code = dict["code"] as? Int, code != 200 {
    let message = dict["message"] as? String ?? "未知错误"
    throw DirectoryError.serverError(code: code, message: message)
}
```

---

## Pending Continuation Cleanup

On socket disconnect, `SocketManager.disconnect()` resumes ALL pending continuations with `SocketError.connectionClosed`:

```swift
for (_, continuation) in activeContinuations {
    continuation.resume(throwing: SocketError.connectionClosed)
}
activeContinuations.removeAll()
```

Never leave `CheckedContinuation` without calling `resume` — this leaks memory and permanently blocks the caller.

---

## Common Mistakes

- **`try?` on socket/frame operations**: Silently swallows errors. Use `try` and let errors propagate.
- **`fatalError` in service code**: Only acceptable in Core Data setup (`Persistence.swift`). Use `throw` everywhere else.
- **Not checking `code != 200`**: Always validate the server response code before accessing `data`.
- **Dangling continuations**: If the socket closes mid-request, all active continuations must be cancelled in `disconnect()`.
