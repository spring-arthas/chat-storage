# Directory Structure

> How the View (frontend) layer is organized in this project.

---

## Overview

This is a macOS SwiftUI app. "Frontend" refers to all SwiftUI views and view-supporting types. Views consume services via `@EnvironmentObject` injection; they do not own service instances.

---

## Directory Layout

```
chat-storage/
├── chat_storageApp.swift        # App entry point — @StateObject singletons injected as @EnvironmentObject
├── ContentView.swift            # Root content routing
├── LoginView.swift              # Auth: login form
├── RegisterView.swift           # Auth: registration form
├── ConfigServerView.swift       # Server address/port configuration (sheet)
├── MainChatStorage.swift        # Primary post-login view — file browser, transfer list, tabs
├── NewFriendView.swift          # Friend search, pending requests, friend list
├── InputValidator.swift         # Input validation helpers (shared, not a view)
└── Views/
    └── StreamingVideoPlayer.swift   # AVPlayer-based video player view
```

Services that contain `View` in their filename but are not SwiftUI views:
- `Services/RecursiveDirectoryView.swift` — directory traversal helper, NOT a SwiftUI View

---

## Module Organization

**Auth flow**: `LoginView` → `RegisterView` (conditional replace, no navigation stack)

**Main flow**: `MainChatStorage` is the root post-login view. It uses:
- `TabView` for top-level navigation (friend list tab, file storage tab)
- `DirectoryService` for all file/directory operations
- `TransferTaskManager.shared` as `@StateObject` for the transfer task list

**Sheets**: Configuration and dialogs appear as `.sheet(isPresented:)`. Examples: `ConfigServerView`, create-directory dialog.

**Video playback**: `StreamingVideoPlayer` in `Views/` is spawned in a new window via `VideoWindowManager`.

---

## Naming Conventions

| Pattern | Convention | Example |
|---------|-----------|---------|
| View files | `*View.swift` | `LoginView.swift`, `NewFriendView.swift` |
| App entry | `*App.swift` | `chat_storageApp.swift` |
| Main screen | `MainChatStorage.swift` | (one primary post-login view) |
| Computed view properties | `private var *Content` | `private var loginContent: some View` |
| MARK sections | `// MARK: - Section Name` | `// MARK: - Body`, `// MARK: - State Variables` |

---

## Examples

- Standard view with `@EnvironmentObject`: `LoginView.swift`
- Complex multi-state view: `MainChatStorage.swift`
- Sheet view: `ConfigServerView.swift`
