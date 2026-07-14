# 主窗口响应式布局与文件详情预览 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让主窗口支持拖动放大、最大化和全屏，并让文件详情在无纵向滚动条的前提下展示图片或视频首帧、完整属性入口和全部操作按钮。

**Architecture:** `chat_storageApp` 只负责窗口默认尺寸、最小尺寸和跨屏约束；`MainChatStorage` 使用现有分栏伸缩能力，并通过纯布局指标控制详情栏密度。文件详情预览复用 `FileThumbnailService` 的图片预览、视频缩略图和两级缓存，不新增媒体传输协议。

**Tech Stack:** Swift 5、SwiftUI、AppKit、AVFoundation、XCTest

---

### Task 1: 主窗口自由缩放与最大化

**Files:**
- Modify: `chat-storage/chat_storageApp.swift:11-106`
- Test: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: 修改窗口布局测试，先表达默认尺寸和最小尺寸契约**

```swift
func testMainWindowLayoutSupportsResponsiveGrowth() throws {
    XCTAssertEqual(AppWindowLayout.mainDefaultWidth, 1240)
    XCTAssertEqual(AppWindowLayout.mainDefaultHeight, 760)
    XCTAssertEqual(AppWindowLayout.mainMinWidth, 1240)
    XCTAssertEqual(AppWindowLayout.mainMinHeight, 760)
    XCTAssertEqual(AppWindowLayout.loginWidth, 720)
    XCTAssertEqual(AppWindowLayout.loginHeight, 456)
}
```

- [ ] **Step 2: 运行测试并确认旧固定尺寸 API 不能满足新测试**

Run: `xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testMainWindowLayoutSupportsResponsiveGrowth test`

Expected: FAIL，提示 `mainDefaultWidth`、`mainMinWidth` 等成员不存在。

- [ ] **Step 3: 将主窗口内容改为最小尺寸加无限扩展**

```swift
enum AppWindowLayout {
    static let mainDefaultWidth: CGFloat = 1240
    static let mainDefaultHeight: CGFloat = 760
    static let mainMinWidth: CGFloat = 1240
    static let mainMinHeight: CGFloat = 760
    static let loginWidth: CGFloat = 720
    static let loginHeight: CGFloat = 456
}
```

主界面使用：

```swift
.frame(
    minWidth: AppWindowLayout.mainMinWidth,
    maxWidth: .infinity,
    minHeight: AppWindowLayout.mainMinHeight,
    maxHeight: .infinity
)
```

登录界面继续使用固定尺寸。主场景使用 `.windowResizability(.contentSize)`，由内容最小值和无限最大值共同决定可调整范围。

- [ ] **Step 4: 修改 AppKit 窗口配置，登录后只设置最小尺寸**

```swift
window.styleMask.insert(.resizable)
window.minSize = NSSize(
    width: AppWindowLayout.mainMinWidth,
    height: AppWindowLayout.mainMinHeight
)
window.maxSize = NSSize(
    width: CGFloat.greatestFiniteMagnitude,
    height: CGFloat.greatestFiniteMagnitude
)
```

仅当登录窗口尺寸小于主窗口最小值时，将其扩展到默认 `1240 x 760` 并居中。屏幕参数变化时调用 `window.constrainFrameRect(window.frame, to: screen)` 校正可见范围，不再无条件重置尺寸。

- [ ] **Step 5: 运行窗口布局测试**

Run: `xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testMainWindowLayoutSupportsResponsiveGrowth test`

Expected: PASS。

### Task 2: 文件详情展示数据和响应式指标

**Files:**
- Modify: `chat-storage/MainChatStorage.swift:516-520,1951-2105,2816-2860`
- Test: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: 添加直接父目录和布局指标测试**

```swift
func testFileDetailDirectoryNameOnlyReturnsDirectParent() throws {
    let detail = FileDto(
        id: 1,
        pId: 2,
        fileName: "movie.mp4",
        filePath: "/Users/demo/storages/account/电影/欧美/movie.mp4",
        fileSize: 1024,
        fileType: "mp4",
        isFile: "Y",
        isExist: "Y",
        hasChild: "N",
        userName: "demo",
        gmtCreated: nil,
        gmtModified: nil,
        del: "N",
        delTime: nil,
        childFileList: nil
    )
    XCTAssertEqual(detail.directoryName, "欧美")
}

func testFileDetailLayoutCompactsForMinimumWindowHeight() throws {
    let compact = FileDetailLayoutMetrics(availableHeight: 650)
    let regular = FileDetailLayoutMetrics(availableHeight: 900)
    XCTAssertLessThan(compact.previewHeight, regular.previewHeight)
    XCTAssertLessThanOrEqual(compact.sectionSpacing, regular.sectionSpacing)
    XCTAssertEqual(compact.actionButtonHeight, 38)
}
```

- [ ] **Step 2: 运行测试并确认父目录和布局指标测试失败**

Run: `xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testFileDetailDirectoryNameOnlyReturnsDirectParent -only-testing:chat-storageTests/chat_storageTests/testFileDetailLayoutCompactsForMinimumWindowHeight test`

Expected: FAIL，当前 `directoryName` 返回完整路径，且 `FileDetailLayoutMetrics` 尚不存在。

- [ ] **Step 3: 实现可测试的高度指标**

```swift
struct FileDetailLayoutMetrics {
    let previewHeight: CGFloat
    let sectionSpacing: CGFloat
    let contentPadding: CGFloat
    let actionButtonHeight: CGFloat

    init(availableHeight: CGFloat) {
        let compact = availableHeight < 720
        previewHeight = compact ? 124 : min(188, availableHeight * 0.24)
        sectionSpacing = compact ? 10 : 16
        contentPadding = compact ? 12 : 16
        actionButtonHeight = 38
    }
}
```

- [ ] **Step 4: 将存储目录限制为直接父目录**

```swift
var directoryName: String {
    if let parentDirName, !parentDirName.isEmpty {
        return parentDirName
    }
    guard !filePath.isEmpty else { return "-" }
    return URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .lastPathComponent
}
```

- [ ] **Step 5: 运行两项数据和指标测试**

Run: `xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testFileDetailDirectoryNameOnlyReturnsDirectParent -only-testing:chat-storageTests/chat_storageTests/testFileDetailLayoutCompactsForMinimumWindowHeight test`

Expected: PASS。

### Task 3: 图片和视频首帧预览

**Files:**
- Modify: `chat-storage/MainChatStorage.swift:516-520,900-925,1165-1180,1951-2105,2762-2795`

- [ ] **Step 1: 增加详情选择和预览任务状态**

```swift
@State private var selectedDetailItem: DirectoryItem?
@State private var detailPreviewImage: NSImage?
@State private var isLoadingDetailPreview = false
@State private var detailLoadTask: Task<Void, Never>?
@State private var detailPreviewTask: Task<Void, Never>?
```

- [ ] **Step 2: 点击文件时保存本地列表项并启动详情与预览加载**

```swift
private func loadFileDetail(fileId: Int64) {
    let item = currentFiles.first(where: { $0.id == fileId })
        ?? fileDetail?.toDirectoryItem()
    selectedDetailItem = item
    loadDetailPreview(for: item)

    detailLoadTask?.cancel()
    isLoadingDetail = true
    detailLoadTask = Task { [service = directoryService] in
        guard let service else {
            await MainActor.run { isLoadingDetail = false }
            return
        }
        do {
            let detail = try await service.fetchFileDetail(fileId: fileId)
            try Task.checkCancellation()
            await MainActor.run {
                guard selectedFileId == fileId else { return }
                fileDetail = detail
                isLoadingDetail = false
            }
        } catch is CancellationError {
        } catch {
            await MainActor.run {
                guard selectedFileId == fileId else { return }
                isLoadingDetail = false
            }
        }
    }
}
```

移除现有 `guard !isLoadingDetail`，保证快速切换文件时新请求能够取消并替换旧请求。

- [ ] **Step 3: 复用缩略图服务加载预览**

```swift
private func loadDetailPreview(for item: DirectoryItem?) {
    detailPreviewTask?.cancel()
    detailPreviewImage = nil
    guard let item, item.isImageFile || item.isVideoFile else {
        isLoadingDetailPreview = false
        return
    }

    isLoadingDetailPreview = true
    detailPreviewTask = Task {
        let image: NSImage?
        if item.isImageFile {
            image = await FileThumbnailService.shared.previewImage(for: item)
        } else {
            image = await FileThumbnailService.shared.thumbnail(for: item)
        }
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard selectedFileId == item.id else { return }
            detailPreviewImage = image
            isLoadingDetailPreview = false
        }
    }
}
```

- [ ] **Step 4: 请求失败时使用列表项降级展示**

详情请求失败只结束 `isLoadingDetail`，不清空 `selectedDetailItem` 和已加载预览。快速切换、删除选中文件或视图消失时取消两类任务。

### Task 4: 无滚动详情栏和全部操作按钮

**Files:**
- Modify: `chat-storage/MainChatStorage.swift:1951-2105`

- [ ] **Step 1: 删除详情区 ScrollView，改为 GeometryReader**

```swift
GeometryReader { proxy in
    let metrics = FileDetailLayoutMetrics(availableHeight: proxy.size.height)
    VStack(spacing: metrics.sectionSpacing) {
        detailPreview(metrics: metrics)
        detailTitle
        detailProperties
        Spacer(minLength: 0)
        detailActions(metrics: metrics)
    }
    .padding(metrics.contentPadding)
}
```

- [ ] **Step 2: 图片和视频使用同一预览容器**

实际图片使用 `Image(nsImage:)`、`.resizable()` 和 `.scaledToFit()`；视频首帧右下角叠加 `play.circle.fill`。加载中显示 `ProgressView`，加载失败或非媒体文件显示 `iconName`。

- [ ] **Step 3: 限制长文本并增加悬停全文**

文件名最多两行并使用 `.truncationMode(.middle).help(fullName)`。每个 `DetailRow` 对值使用单行中间省略，并通过 `.help(value)` 显示完整值。

- [ ] **Step 4: 将操作按钮改为两列网格**

使用两个 `.flexible()` 的 `GridItem` 构建 `LazyVGrid`。将现有在线播放、立即下载、重命名、删除四个 `Button` 原样迁入网格；在线播放按钮继续由 `detail.isPlayableVideoFile` 控制。每个按钮统一使用 `.frame(maxWidth: .infinity)` 和 `.frame(height: metrics.actionButtonHeight)`，不隐藏任何可用操作；非视频文件保留下载、重命名和删除三个按钮。

### Task 5: 完整验证

**Files:**
- Verify: `chat-storage/chat_storageApp.swift`
- Verify: `chat-storage/MainChatStorage.swift`
- Verify: `chat-storageTests/chat_storageTests.swift`

- [ ] **Step 1: 运行相关单元测试**

Run: `xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS' -only-testing:chat-storageTests/chat_storageTests/testMainWindowLayoutSupportsResponsiveGrowth -only-testing:chat-storageTests/chat_storageTests/testFileDetailDirectoryNameOnlyReturnsDirectParent -only-testing:chat-storageTests/chat_storageTests/testFileDetailLayoutCompactsForMinimumWindowHeight test`

Expected: 3 tests PASS。

- [ ] **Step 2: 编译应用**

Run: `xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Debug -destination 'platform=macOS' build`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 人工验收尺寸**

由用户在 Xcode 启动后检查：默认 `1240 x 760`、14 寸最大化、16 寸最大化和扩展屏全屏。确认会话页、云盘三栏、文件表头、详情预览和全部按钮无重叠、无裁切，详情栏无纵向滚动条。
