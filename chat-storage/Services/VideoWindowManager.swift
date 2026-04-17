import SwiftUI
import AppKit

/// 视频播放窗口管理器（单例）
class VideoWindowManager: NSObject {
    static let shared = VideoWindowManager()

    private var window: NSWindow?
    private var currentFileId: Int64?
    private var viewModel: StreamingVideoViewModel?

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
        vm.onPlaybackSessionTerminated = { [weak self, weak vm] in
            self?.closeWindowForFinishedSession(viewModel: vm, fileId: fileId)
        }
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
        let oldWindow = window
        let oldViewModel = viewModel

        // 先切断当前引用，避免旧窗口异步回调误伤新窗口状态。
        window = nil
        viewModel = nil
        currentFileId = nil

        // 显式调用 stopPlaying，不等待 SwiftUI onDisappear（Issue 1）
        oldViewModel?.stopPlaying()

        // 关闭旧窗口前先移除 delegate，防止旧窗口 close 的异步回调覆盖新窗口引用。
        oldWindow?.delegate = nil
        oldWindow?.close()
    }

    private func closeWindowForFinishedSession(viewModel: StreamingVideoViewModel?, fileId: Int64) {
        guard let targetViewModel = viewModel else { return }
        guard let currentViewModel = self.viewModel,
              currentViewModel === targetViewModel,
              currentFileId == fileId else {
            return
        }
        forceClose()
    }
}

extension VideoWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        guard closingWindow === window else {
            // 旧窗口的迟到回调，忽略，避免覆盖当前新窗口状态。
            return
        }
        // 双重保险：窗口关闭时显式释放资源，不依赖 SwiftUI onDisappear 的异步时序（Issue 1）
        viewModel?.stopPlaying()
        viewModel = nil
        currentFileId = nil
        window = nil
    }
}
