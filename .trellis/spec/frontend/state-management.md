# State Management

> How state is managed in this project's SwiftUI views.

---

## Overview

State management uses SwiftUI's native property wrappers only. No third-party state management library (no Redux, no TCA). The pattern is:

- **Global state** → `@Published` properties on ObservableObject singletons, injected as `@EnvironmentObject`
- **Local UI state** → `@State` properties on the view struct
- **Server data** → fetched on demand via `Task { }`, stored in `@State`

---

## State Categories

### Global State (EnvironmentObject)

Owned by `chat_storageApp.swift`, available to all views:

| Object | Key properties |
|--------|---------------|
| `SocketManager` | `connectionState`, `chatHistory`, `unreadCounts`, `friendList`, `pendingFriendRequests` |
| `AuthenticationService` | `currentUser`, `isAuthenticated` |

### View-Owned Service State (StateObject in MainChatStorage)

```swift
@StateObject private var transferManager = TransferTaskManager.shared
@StateObject private var downloadDirectoryManager = DownloadDirectoryManager.shared
```

### Local View State (@State)

Declared per-view for UI-specific concerns:

```swift
// Navigation / modal
@State private var isLoggedIn = false
@State private var showingAlert = false
@State private var alertMessage = ""

// Loaded data
@State private var directoryTree: [DirectoryItem] = []
@State private var fileList: [FileDto] = []

// Pagination
@State private var currentPage: Int = 1
@State private var totalPages: Int = 1

// Loading state
@State private var isLoadingDirectory = false
```

---

## When to Use Global State

Promote to global (`@Published` on a service singleton) when:
- Multiple views need the same data (e.g., `chatHistory` needed by both `MainChatStorage` and chat detail views)
- The data persists across navigation (e.g., `friendList`, `unreadCounts`)
- The data is produced by a background event (e.g., incoming frame from `SocketManager`)

Keep in local `@State` when:
- Only this view needs it
- It's a UI transient (loading spinner, error message, selected tab)
- It's fetched fresh each time the view appears

---

## Server State (Data from Remote)

There is no cache layer. Server data is fetched on `.onAppear`, stored in `@State`, and re-fetched on navigation or user action. No optimistic updates.

```swift
// Standard pattern: fetch on appear
.onAppear {
    Task {
        do {
            let result = try await directoryService.fetchFileList(dirId: selectedDirectoryId ?? 0)
            self.fileList = result.recordList
            self.totalPages = result.totalPage
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}
```

Pagination state (`currentPage`, `totalPages`, `totalCount`) is always local `@State`.

---

## Login State

`isLoggedIn: Bool` is `@State` in `chat_storageApp.swift` and threaded down as `@Binding`. It controls the root view switch between `LoginView` and `MainChatStorage`:

```swift
if isLoggedIn {
    MainChatStorage(isLoggedIn: $isLoggedIn)
} else {
    LoginView(isLoggedIn: $isLoggedIn)
}
```

Logout sets `isLoggedIn = false`, which SwiftUI uses to destroy `MainChatStorage` and recreate `LoginView`.

---

## Common Mistakes

- **Using `@ObservedObject` instead of `@StateObject` or `@EnvironmentObject`**: This project does not use `@ObservedObject`. Singletons use `@EnvironmentObject`; owned services use `@StateObject`.
- **Mutating `@Published` from a background thread**: Always use `await MainActor.run { }` or ensure the ObservableObject is `@MainActor`.
- **Re-fetching server data on every body re-render**: Use `.onAppear` or explicit user actions, not computed properties that call services.
