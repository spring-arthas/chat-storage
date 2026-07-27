# Friend Chat Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent, account-and-friend-scoped image background to the message area of each macOS friend conversation.

**Architecture:** A focused `ChatBackgroundStore` actor owns deterministic Application Support paths, JPEG normalization, atomic replacement, loading, and removal. `ChatDetailView` invokes the store from its existing menu and renders the loaded image only behind the message scroll area. Tests inject temporary storage roots and assert both persistence behavior and SwiftUI wiring.

**Tech Stack:** Swift 5, SwiftUI, AppKit, ImageIO, UniformTypeIdentifiers, XCTest, Xcode project file.

---

### Task 1: Persistent Background Store

**Files:**
- Create: `chat-storage/Services/Chat/ChatBackgroundStore.swift`
- Modify: `chat-storage.xcodeproj/project.pbxproj`
- Test: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: Write the failing isolation test**

```swift
func testChatBackgroundStoreSeparatesAccountsAndFriends() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ChatBackgroundStore(rootDirectory: root)

    let first = await store.backgroundURL(accountId: 11, friendId: 21)
    let secondFriend = await store.backgroundURL(accountId: 11, friendId: 22)
    let secondAccount = await store.backgroundURL(accountId: 12, friendId: 21)

    XCTAssertNotEqual(first, secondFriend)
    XCTAssertNotEqual(first, secondAccount)
    XCTAssertTrue(first.path.hasSuffix("11/21/background.jpg"))
}
```

- [ ] **Step 2: Write failing persistence and failure-safety tests**

Add this fixture helper inside `chat_storageTests`:

```swift
private func writeChatBackgroundJPEG(color: NSColor, to url: URL) throws {
    let image = NSImage(size: NSSize(width: 20, height: 12))
    image.lockFocus()
    color.setFill()
    NSRect(x: 0, y: 0, width: 20, height: 12).fill()
    image.unlockFocus()
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
    let data = try XCTUnwrap(
        bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    )
    try data.write(to: url, options: .atomic)
}
```

Add these tests:

```swift
func testChatBackgroundStorePersistsReplacementAndReset() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let firstSource = root.appendingPathComponent("first.jpg")
    let secondSource = root.appendingPathComponent("second.jpg")
    try writeChatBackgroundJPEG(color: .red, to: firstSource)
    try writeChatBackgroundJPEG(color: .blue, to: secondSource)
    let store = ChatBackgroundStore(rootDirectory: root.appendingPathComponent("managed", isDirectory: true))

    let firstData = try await store.importBackground(from: firstSource, accountId: 11, friendId: 21)
    try FileManager.default.removeItem(at: firstSource)
    let reloaded = await store.loadBackgroundData(accountId: 11, friendId: 21)
    XCTAssertEqual(reloaded, firstData)

    let replacement = try await store.importBackground(from: secondSource, accountId: 11, friendId: 21)
    let otherFriend = try await store.importBackground(from: secondSource, accountId: 11, friendId: 22)
    XCTAssertNotEqual(replacement, firstData)
    try await store.removeBackground(accountId: 11, friendId: 21)
    let removed = await store.loadBackgroundData(accountId: 11, friendId: 21)
    let untouched = await store.loadBackgroundData(accountId: 11, friendId: 22)
    XCTAssertNil(removed)
    XCTAssertEqual(untouched, otherFriend)
}

func testChatBackgroundStoreRejectsInvalidReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let validSource = root.appendingPathComponent("valid.jpg")
    let invalidSource = root.appendingPathComponent("invalid.jpg")
    try writeChatBackgroundJPEG(color: .green, to: validSource)
    try Data("not-an-image".utf8).write(to: invalidSource)
    let store = ChatBackgroundStore(rootDirectory: root.appendingPathComponent("managed", isDirectory: true))
    let original = try await store.importBackground(from: validSource, accountId: 11, friendId: 21)

    do {
        _ = try await store.importBackground(from: invalidSource, accountId: 11, friendId: 21)
        XCTFail("Expected invalid image import to fail")
    } catch {
        XCTAssertEqual(error as? ChatBackgroundStore.StoreError, .invalidImage)
    }
    let preserved = await store.loadBackgroundData(accountId: 11, friendId: 21)
    XCTAssertEqual(preserved, original)
}

func testChatBackgroundStoreTreatsCorruptManagedFileAsMissing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ChatBackgroundStore(rootDirectory: root)
    let managedURL = await store.backgroundURL(accountId: 11, friendId: 21)
    try FileManager.default.createDirectory(at: managedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("corrupt".utf8).write(to: managedURL)

    let loaded = await store.loadBackgroundData(accountId: 11, friendId: 21)
    XCTAssertNil(loaded)
}
```

- [ ] **Step 3: Run the focused tests and verify RED**

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' \
  -only-testing:chat-storageTests/chat_storageTests/testChatBackgroundStoreSeparatesAccountsAndFriends \
  -only-testing:chat-storageTests/chat_storageTests/testChatBackgroundStorePersistsReplacementAndReset \
  -only-testing:chat-storageTests/chat_storageTests/testChatBackgroundStoreRejectsInvalidReplacement \
  -only-testing:chat-storageTests/chat_storageTests/testChatBackgroundStoreTreatsCorruptManagedFileAsMissing
```

Expected: compilation fails because `ChatBackgroundStore` does not exist.

- [ ] **Step 4: Implement the store actor**

Create this API:

```swift
actor ChatBackgroundStore {
    static let shared = ChatBackgroundStore()

    enum StoreError: LocalizedError, Equatable {
        case invalidIdentity
        case invalidImage
        case encodingFailed
    }

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default)
    func backgroundURL(accountId: Int64, friendId: Int64) -> URL
    func loadBackgroundData(accountId: Int64, friendId: Int64) -> Data?
    func importBackground(from sourceURL: URL, accountId: Int64, friendId: Int64) throws -> Data
    func removeBackground(accountId: Int64, friendId: Int64) throws
}
```

The default root is `Application Support/<bundle-id>/ChatBackgrounds`. Normalize with `CGImageSourceCreateThumbnailAtIndex`, applying orientation, a maximum long edge of `3840`, and JPEG compression factor `0.88`. Fully validate and encode before creating the destination directory. Persist with `Data.write(to:options: .atomic)` so a failed import preserves the old image.

- [ ] **Step 5: Add the source to the app target**

Add one `PBXFileReference`, one `PBXBuildFile`, one Chat service group entry, and one app `PBXSourcesBuildPhase` entry for `ChatBackgroundStore.swift`. Do not add it to a test sources phase because tests import the app module.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run the exact Step 3 command. Expected: `TEST SUCCEEDED` with all four named tests passing.

- [ ] **Step 7: Commit the store slice**

```bash
git add chat-storage/Services/Chat/ChatBackgroundStore.swift chat-storageTests/chat_storageTests.swift chat-storage.xcodeproj/project.pbxproj
git commit -m "feat: persist per-friend chat backgrounds"
```

### Task 2: Chat Controls and Message-Area Rendering

**Files:**
- Modify: `chat-storage/MainChatStorage.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: Write the failing UI wiring assertion**

```swift
func testChatDetailSupportsPersistentPerFriendBackgrounds() throws {
    let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
    let detail = try sourceSlice(source, from: "private struct ChatDetailView: View {", to: "// 3. Friend Sidebar View")

    XCTAssertTrue(detail.contains("Menu(\"更改聊天背景\")"))
    XCTAssertTrue(detail.contains("chooseChatBackground()"))
    XCTAssertTrue(detail.contains("resetChatBackground()"))
    XCTAssertTrue(detail.contains("ChatBackgroundStore.shared"))
    XCTAssertTrue(detail.contains(".scaledToFill()"))
}
```

- [ ] **Step 2: Run the UI test and verify RED**

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' \
  -only-testing:chat-storageTests/chat_storageTests/testChatDetailSupportsPersistentPerFriendBackgrounds
```

Expected: assertion failure because the existing background menu action is unimplemented.

- [ ] **Step 3: Add menu state and store operations**

Add these `ChatDetailView` properties:

```swift
@State private var chatBackgroundImage: NSImage?
@State private var isManagingChatBackground = false
@State private var chatBackgroundError: String?
private let chatBackgroundStore = ChatBackgroundStore.shared
```

Replace the placeholder action with:

```swift
Menu("更改聊天背景") {
    Button("选择图片") { chooseChatBackground() }
    Button("恢复空白背景", role: .destructive) {
        Task { await resetChatBackground() }
    }
    .disabled(chatBackgroundImage == nil || isManagingChatBackground)
}
```

`chooseChatBackground()` uses an `NSOpenPanel` restricted to `.image`. Loading, importing, and reset require `authService.currentUser?.id`, call `ChatBackgroundStore.shared`, update state on the main actor, preserve the old image on failure, and expose errors through a `聊天背景设置失败` alert.

- [ ] **Step 4: Render only behind the message list**

Use this background as the first layer of the existing message-area `ZStack`:

```swift
GeometryReader { proxy in
    if let chatBackgroundImage {
        Image(nsImage: chatBackgroundImage)
            .resizable()
            .scaledToFill()
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
    } else {
        Color(NSColor.textBackgroundColor).opacity(0.8)
    }
}
```

Keep the header and `ChatInputBar` outside this layer. Make the message container background clear and load the background from `.onAppear`; `ChatDetailView` already has `.id(friend.id)` at its call site.

- [ ] **Step 5: Run all five focused tests**

Run the four Task 1 tests and `testChatDetailSupportsPersistentPerFriendBackgrounds`. Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit the UI slice**

```bash
git add chat-storage/MainChatStorage.swift chat-storageTests/chat_storageTests.swift
git commit -m "feat: add friend chat background controls"
```

### Task 3: Final Verification

**Files:**
- Verify: `chat-storage/Services/Chat/ChatBackgroundStore.swift`
- Verify: `chat-storage/MainChatStorage.swift`
- Verify: `chat-storageTests/chat_storageTests.swift`
- Verify: `chat-storage.xcodeproj/project.pbxproj`

- [ ] **Step 1: Run the complete unit test suite**

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'
```

Expected: `TEST SUCCEEDED` and zero failed tests.

- [ ] **Step 2: Run a Release build in temporary DerivedData**

```bash
build_root=$(mktemp -d /tmp/chat-background-release.XXXXXX)
xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath "$build_root"
find "$build_root" -depth -delete
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Verify the final repository state**

```bash
git diff --check
git status --short --branch
```

Expected: only intentional commits are present, with no `build_data/` or temporary image files in the repository.
