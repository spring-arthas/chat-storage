import SwiftUI
import AppKit

/// 视频播放窗口管理器
class VideoWindowManager: NSObject {
    static let shared = VideoWindowManager()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
    }
    
    /// 打开视频播放窗口
    /// - Parameters:
    ///   - fileId: 文件 ID
    ///   - fileName: 文件名
    ///   - fileSize: 文件大小
    func show(fileId: Int64, fileName: String, fileSize: Int64) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // 创建播放容器视图
        let playerView = StreamingVideoPlayer(fileId: fileId, fileName: fileName, fileSize: fileSize)
            .environmentObject(SocketManager.shared)
        
        let hostingView = NSHostingView(rootView: playerView)
        
        // 创建 NSWindow
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
        
        // 配置标题栏：显示原生文件名标题，并与播放内容区区分开
        newWindow.titlebarAppearsTransparent = false
        newWindow.titleVisibility = .visible
        
        // 设置背景色
        newWindow.backgroundColor = .black
        
        self.window = newWindow
        
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
    }
    
    func close() {
        window?.close()
        window = nil
    }
}

extension VideoWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时，SwiftUI View 的 onDisappear 会被触发，从而停止播放
        window = nil
    }
}
