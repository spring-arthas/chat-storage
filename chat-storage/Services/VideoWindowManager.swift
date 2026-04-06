import SwiftUI
import AppKit

/// 视频播放窗口管理器（单例）
class VideoWindowManager: NSObject {
    static let shared = VideoWindowManager()

    private var window: NSWindow?
    private var currentFileId: Int64?
    private weak var viewModel: StreamingVideoViewModel?

    private override init() {
        super.init()
    }

    /// 打开视频播放窗口。
    /// - 若当前已在播放相同文件，直接聚焦窗口。
    /// - 若当前在播放其他文件，强制关闭旧窗口并清理资源后打开新窗口（Issue 3）。
    func show(fileId: Int64, fileName: String, fileSize: Int64) {
        // 相同文件：直接聚焦
        if currentFileId == fileId, let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // 不同文件（或首次）：先强制关闭旧窗口并清理资源
        forceClose()

        let vm = StreamingVideoViewModel()
        self.viewModel = vm
        self.currentFileId = fileId

        let playerView = StreamingVideoPlayer(
            fileId: fileId,
            fileName: fileName,
            fileSize: fileSize,
            viewModel: vm
        ).environmentObject(SocketManager.shared)

        let hostingView = NSHostingView(rootView: playerView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newWindow.center()
        newWindow.title = fileName
        newWindow.setFrameAutosaveName("VideoPlayerWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = hostingView
        newWindow.titlebarAppearsTransparent = false
        newWindow.titleVisibility = .visible
        newWindow.backgroundColor = .black

        self.window = newWindow
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
    }

    /// 强制关闭播放器并释放所有资源。
    func forceClose() {
        // 显式调用 stopPlaying，不等待 SwiftUI onDisappear（Issue 1）
        viewModel?.stopPlaying()
        viewModel = nil
        currentFileId = nil
        window?.close()
        window = nil
    }
}

extension VideoWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 双重保险：窗口关闭时显式释放资源，不依赖 SwiftUI onDisappear 的异步时序（Issue 1）
        viewModel?.stopPlaying()
        viewModel = nil
        currentFileId = nil
        window = nil
    }
}
