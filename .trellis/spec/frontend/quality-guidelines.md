# Quality Guidelines

> Code quality standards for View (frontend) development.

---

## Required Patterns

### MARK Sections

All views must use `// MARK: -` to organize code sections in this order:

```swift
// MARK: - Environment Objects
// MARK: - Bindings
// MARK: - State Variables
// MARK: - Body
// MARK: - [Section name for each computed view property]
```

### Async Operations in Task Blocks

All async calls must be wrapped in `Task { }` inside `.onAppear`, button actions, or `onChange`:

```swift
Button("Load") {
    Task {
        do {
            result = try await service.fetch()
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}
```

Never use `async` directly in button closures without `Task { }`.

### Alert Pattern

Use a pair of `@State` variables for all alerts:

```swift
@State private var showingAlert = false
@State private var alertMessage = ""
```

Bind to `.alert(isPresented: $showingAlert) { Alert(title: Text(alertMessage)) }`.

### Window Centering

After login state change, always re-center the window. This is already handled in `chat_storageApp.swift` via `onChange(of: isLoggedIn)`. Do not duplicate this logic in views.

---

## Forbidden Patterns

| Pattern | Why Forbidden |
|---------|--------------|
| Network calls in `body` | Body must be pure/synchronous |
| `SocketManager.shared` accessed from views | Use `@EnvironmentObject var socketManager` |
| `@ObservedObject` | Not used; use `@StateObject` or `@EnvironmentObject` |
| Business logic in computed view properties | Put in `Task { }` blocks, not view builders |
| Hardcoded server address in views | Server config lives in `ConfigServerView` / `SocketManager` |

---

## View Decomposition

When a view's `body` exceeds ~50 lines, decompose into private computed properties:

```swift
var body: some View {
    VStack {
        toolbarSection
        fileListSection
        paginationSection
    }
}

private var toolbarSection: some View { ... }
private var fileListSection: some View { ... }
```

Do not extract tiny views into separate files unless they are reused in multiple places.

---

## Code Review Checklist

- [ ] No `async` code directly in `body`
- [ ] All async calls wrapped in `Task { }` with `catch { alertMessage = ... }`
- [ ] Services accessed via `@EnvironmentObject`, not `.shared`
- [ ] `// MARK: -` sections present and in correct order
- [ ] Sheets pass `@EnvironmentObject` explicitly
- [ ] No inline business/network logic in computed view properties
