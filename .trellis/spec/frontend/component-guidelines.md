# Component Guidelines

> How SwiftUI views are built in this project.

---

## Overview

All UI is built with SwiftUI. Views are `struct` conforming to `View`. The primary composition mechanism is computed `var` properties returning `some View`, and `.sheet()` for modal presentation.

---

## Standard View Structure

Use `// MARK: -` sections in this order:

```swift
struct MyView: View {

    // MARK: - Environment Objects
    @EnvironmentObject var socketManager: SocketManager
    @EnvironmentObject var authService: AuthenticationService

    // MARK: - Bindings
    @Binding var isLoggedIn: Bool

    // MARK: - State Variables
    @State private var username: String = ""
    @State private var isLoading: Bool = false

    // MARK: - Body
    var body: some View {
        mainContent
    }

    // MARK: - Main Content
    private var mainContent: some View {
        // view composition
    }
}
```

---

## EnvironmentObject Injection

Global singletons (`SocketManager`, `AuthenticationService`) are injected as `@EnvironmentObject` from `chat_storageApp.swift`. Views must declare them with `@EnvironmentObject var` — never instantiate or access `.shared` directly in a view:

```swift
// Correct
@EnvironmentObject var socketManager: SocketManager

// Wrong: never access .shared from a view
let sm = SocketManager.shared
```

The exception: `TransferTaskManager.shared` and `DownloadDirectoryManager.shared` are wrapped in `@StateObject` inside `MainChatStorage` (not in the app entry point) because they are only needed there.

---

## Computed View Properties

Break large `body` into private computed properties rather than inline nesting:

```swift
var body: some View {
    VStack {
        headerSection
        contentSection
        footerSection
    }
}

private var headerSection: some View {
    // ...
}
```

---

## Window Sizing

Window frame sizes are set in `chat_storageApp.swift`:
- Login window: `.frame(width: 500, height: 550)` — fixed size
- Main window: `.frame(minWidth: 1650, idealWidth: 3300, minHeight: 1050, idealHeight: 2100)`

Views themselves do not constrain their own frame — sizing is handled at the window level.

---

## Sheets and Dialogs

Use `.sheet(isPresented:)` for configuration dialogs. Always pass `@EnvironmentObject` into sheets explicitly:

```swift
.sheet(isPresented: $showConfigServer) {
    ConfigServerView()
        .environmentObject(socketManager)
}
```

Alert dialogs use `@State private var showingAlert = false` + `@State private var alertMessage = ""` pattern, bound to `.alert(isPresented:)`.

---

## Styling

- No CSS; all styling uses SwiftUI modifiers
- Gradients: `.linearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)`
- No third-party UI libraries

---

## Common Mistakes

- **Accessing service `.shared` directly in a view**: Always use `@EnvironmentObject`.
- **Business logic in `body`**: Extract network calls into `Task { }` blocks triggered by `.onAppear` or button actions; never inline `async` logic in `body`.
- **Forgetting `.environmentObject()` on sheets**: Sheets do not inherit the parent's environment automatically — always pass explicitly.
