# Cloud Upload Root Directory Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent cloud-drive uploads unless the user has selected a valid non-root directory with a positive ID, and show the existing prompt alert when validation fails.

**Architecture:** Add a small pure validator beside the cloud-drive view so directory-selection rules are testable without presenting SwiftUI. The upload button resolves the selected node, asks the validator for an allowed target, and only then opens `NSOpenPanel`; the file-selection handler accepts a non-optional directory so invalid IDs cannot enter transfer tasks.

**Tech Stack:** Swift 5, SwiftUI, AppKit `NSOpenPanel`, XCTest, Xcode build system

---

### Task 1: Define and test the cloud upload target contract

**Files:**
- Modify: `chat-storageTests/chat_storageTests.swift`
- Modify: `chat-storage/MainChatStorage.swift`

- [ ] **Step 1: Write the failing validator tests**

Add tests that build a root directory and a child directory, then assert:

```swift
func testCloudUploadTargetRejectsMissingInvalidAndRootSelections() throws {
    let root = DirectoryItem(id: 100, pId: -1, fileName: "user", childFileList: nil)
    let child = DirectoryItem(id: 200, pId: 100, fileName: "docs", childFileList: nil)

    for selection in [nil, 0, -1, root.id] as [Int64?] {
        let resolved = selection == child.id ? child : (selection == root.id ? root : nil)
        let result = CloudUploadTargetValidator.validate(
            selectedDirectoryId: selection,
            rootDirectoryId: root.id,
            resolvedDirectory: resolved
        )
        guard case .failure(let error) = result else {
            return XCTFail("Expected upload target rejection for selection: \(String(describing: selection))")
        }
        XCTAssertEqual(error, .invalidTarget)
        XCTAssertEqual(error.errorDescription, "根目录不允许上传，请先选择一个子目录")
    }
}

func testCloudUploadTargetRejectsUnknownPositiveDirectory() throws {
    let result = CloudUploadTargetValidator.validate(
        selectedDirectoryId: 200,
        rootDirectoryId: 100,
        resolvedDirectory: nil
    )

    guard case .failure(let error) = result else {
        return XCTFail("Expected unknown directory rejection")
    }
    XCTAssertEqual(error, .invalidTarget)
}

func testCloudUploadTargetAllowsResolvedPositiveChildDirectory() throws {
    let child = DirectoryItem(id: 200, pId: 100, fileName: "docs", childFileList: nil)
    let result = CloudUploadTargetValidator.validate(
        selectedDirectoryId: child.id,
        rootDirectoryId: 100,
        resolvedDirectory: child
    )

    guard case .success(let target) = result else {
        return XCTFail("Expected child directory to be uploadable")
    }
    XCTAssertEqual(target.id, child.id)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testCloudUploadTargetRejectsMissingInvalidAndRootSelections -only-testing:chat-storageTests/chat_storageTests/testCloudUploadTargetRejectsUnknownPositiveDirectory -only-testing:chat-storageTests/chat_storageTests/testCloudUploadTargetAllowsResolvedPositiveChildDirectory
```

Expected: compilation fails because `CloudUploadTargetValidator` does not exist.

- [ ] **Step 3: Add the minimal pure validator**

Add beside the cloud-drive view declarations:

```swift
enum CloudUploadTargetError: LocalizedError, Equatable {
    case invalidTarget

    var errorDescription: String? {
        "根目录不允许上传，请先选择一个子目录"
    }
}

enum CloudUploadTargetValidator {
    static func validate(
        selectedDirectoryId: Int64?,
        rootDirectoryId: Int64?,
        resolvedDirectory: DirectoryItem?
    ) -> Result<DirectoryItem, CloudUploadTargetError> {
        guard let selectedDirectoryId,
              selectedDirectoryId > 0,
              let rootDirectoryId,
              rootDirectoryId > 0,
              selectedDirectoryId != rootDirectoryId,
              let resolvedDirectory,
              resolvedDirectory.id == selectedDirectoryId,
              !resolvedDirectory.isFile else {
            return .failure(.invalidTarget)
        }
        return .success(resolvedDirectory)
    }
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command again.

Expected: all three focused tests pass.

### Task 2: Enforce validation at the cloud upload entry point

**Files:**
- Modify: `chat-storage/MainChatStorage.swift`
- Test: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: Write a failing source-contract regression test**

```swift
func testCloudUploadEntryRequiresValidatedNonOptionalDirectory() throws {
    let source = try sourceFileContents("chat-storage/MainChatStorage.swift")

    XCTAssertTrue(source.contains("private func handleCloudUpload()"))
    XCTAssertTrue(source.contains("CloudUploadTargetValidator.validate("))
    XCTAssertTrue(source.contains("private func handleSelectFiles(targetDirectory: DirectoryItem)"))
    XCTAssertFalse(source.contains("targetDirectory?.id ?? 0"))
    XCTAssertFalse(source.contains("targetDirectory?.fileName ?? \"根目录\""))
}
```

- [ ] **Step 2: Run the source-contract test and verify RED**

Run:

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testCloudUploadEntryRequiresValidatedNonOptionalDirectory
```

Expected: test fails because the upload entry still calls the optional handler and retains the zero-ID fallback.

- [ ] **Step 3: Route the button through validation and remove fallbacks**

Change the button action to `handleCloudUpload()`. Add:

```swift
private func handleCloudUpload() {
    let resolvedDirectory = selectedDirectoryId.flatMap {
        findDirectoryItem(id: $0, nodes: directoryTree)
    }
    let result = CloudUploadTargetValidator.validate(
        selectedDirectoryId: selectedDirectoryId,
        rootDirectoryId: directoryTree.first?.id,
        resolvedDirectory: resolvedDirectory
    )

    switch result {
    case .success(let targetDirectory):
        handleSelectFiles(targetDirectory: targetDirectory)
    case .failure(let error):
        alertMessage = error.errorDescription ?? "根目录不允许上传，请先选择一个子目录"
        showingAlert = true
    }
}
```

Change the handler signature and task fields to:

```swift
private func handleSelectFiles(targetDirectory: DirectoryItem) {
    // existing NSOpenPanel configuration
    panel.message = "选择文件上传到目录: \(targetDirectory.fileName)"
    // ...
    let targetName = targetDirectory.fileName
    // ...
    targetDirId: targetDirectory.id,
}
```

- [ ] **Step 4: Run focused validator and source-contract tests**

Run:

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testCloudUploadTargetRejectsMissingInvalidAndRootSelections -only-testing:chat-storageTests/chat_storageTests/testCloudUploadTargetRejectsUnknownPositiveDirectory -only-testing:chat-storageTests/chat_storageTests/testCloudUploadTargetAllowsResolvedPositiveChildDirectory -only-testing:chat-storageTests/chat_storageTests/testCloudUploadEntryRequiresValidatedNonOptionalDirectory
```

Expected: all four tests pass.

- [ ] **Step 5: Verify the complete project**

Run:

```bash
xcodebuild test -project chat-storage.xcodeproj -scheme chat-storage -destination 'platform=macOS'
xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug build
git diff --check -- chat-storage/MainChatStorage.swift chat-storageTests/chat_storageTests.swift
```

Expected: tests and build exit successfully; `git diff --check` reports no whitespace errors.
