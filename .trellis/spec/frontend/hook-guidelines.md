# Hook Guidelines

> SwiftUI property wrapper patterns used in this project.

---

## Overview

This project uses SwiftUI's built-in property wrappers. There are no custom "hooks" — the SwiftUI equivalents are `@State`, `@StateObject`, `@EnvironmentObject`, `@Binding`, and `@Published`.

---

## Property Wrapper Reference

| Wrapper | Scope | Use when |
|---------|-------|----------|
| `@State` | Local to view | Simple value types (String, Bool, Int) owned by this view |
| `@StateObject` | Owned by view | A service/ObservableObject this view creates and owns |
| `@EnvironmentObject` | Injected globally | Singletons passed down from `chat_storageApp.swift` |
| `@Binding` | Passed from parent | A value the parent owns but this view needs to read/write |
| `@Published` | Inside ObservableObject | Properties that should trigger view updates |

---

## Data Fetching Pattern

All async data fetching uses `Task { }` triggered from `.onAppear` or button actions:

```swift
.onAppear {
    Task {
        do {
            directoryTree = try await directoryService.loadDirectoryTree()
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}
```

There is no data-fetching framework (no Combine pipelines for network, no async `@Query`). Keep it simple: `Task { try await service.method() }`.

---

## @StateObject Usage

`@StateObject` is used for ObservableObject instances that the view owns:

```swift
// In MainChatStorage — these are created and owned here
@StateObject private var transferManager = TransferTaskManager.shared
@StateObject private var downloadDirectoryManager = DownloadDirectoryManager.shared
```

Do not use `@StateObject` for singletons injected from the app entry point — use `@EnvironmentObject` instead.

---

## @Binding Usage

Bindings thread mutable state from parent to child:

```swift
// Parent owns the state
@State private var isLoggedIn = false

// Passes to child as Binding
LoginView(isLoggedIn: $isLoggedIn)

// Child declares
@Binding var isLoggedIn: Bool
```

The `isLoggedIn` binding is the primary navigation signal between `LoginView` and `MainChatStorage`.

---

## Combine / Publisher Usage

`SocketManager` uses Combine's `@Published` for reactive state. Views observe these via `@EnvironmentObject`:

```swift
// SocketManager
@Published var connectionState: SocketConnectionState = .disconnected
@Published var chatHistory: [Int64: [ChatMessage]] = [:]

// View reads reactively
socketManager.connectionState == .connected
```

Do not subscribe to publishers with `.sink` in views unless absolutely necessary — prefer reading `@Published` values directly via `@EnvironmentObject`.

---

## Common Mistakes

- **`@ObservedObject` for singletons**: Use `@StateObject` (view-owned) or `@EnvironmentObject` (injected). `@ObservedObject` is not used in this project.
- **Async code directly in `body`**: Body must be synchronous. Use `Task { }` in `.onAppear` or button closures.
- **Forgetting `@MainActor` when updating state from background**: Call `await MainActor.run { self.someState = value }` when updating published properties from inside a `Task`.
