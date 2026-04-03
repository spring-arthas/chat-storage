//  macOs入口程序
//  chat_storageApp.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/29.
//

import SwiftUI
import AppKit

enum AppWindowLayout {
    static let mainMinWidth: CGFloat = 1080
    static let mainMinHeight: CGFloat = 700
    static let loginWidth: CGFloat = 500
    static let loginHeight: CGFloat = 550
    static let visibleAreaRatio: CGFloat = 0.95
}

@main
struct chat_storageApp: App {
    let persistenceController = PersistenceController.shared
    
    // 创建全局 Socket 管理器
    @StateObject private var socketManager = SocketManager.shared
    
    // 创建全局认证服务
    @StateObject private var authService = AuthenticationService.shared

    // 登录状态
    @State private var isLoggedIn = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    // 主界面
                    MainChatStorage(isLoggedIn: $isLoggedIn)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(socketManager)
                        .environmentObject(authService)
                        .frame(minWidth: AppWindowLayout.mainMinWidth, minHeight: AppWindowLayout.mainMinHeight)
                } else {
                    // 登录界面
                    LoginView(isLoggedIn: $isLoggedIn)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(socketManager)
                        .environmentObject(authService)
                        .frame(width: AppWindowLayout.loginWidth, height: AppWindowLayout.loginHeight)
                }
            }
            .onAppear {
                DispatchQueue.main.async { configureWindowForCurrentState() }
            }
            .onChange(of: isLoggedIn) { newValue in
                if newValue {
                    // 请求桌面通知权限
                    NotificationManager.shared.requestAuthorization()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    configureWindowForCurrentState()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                DispatchQueue.main.async {
                    configureWindowForCurrentState()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // 在应用菜单中添加连接控制（可选）
        }
    }
    
    init() {
        // 应用启动时自动连接远程服务端
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SocketManager.shared.connect()
        }
    }

    private func configureWindowForCurrentState() {
        guard let window = NSApplication.shared.windows.first else { return }

        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = screenFrame.width * AppWindowLayout.visibleAreaRatio
        let maxHeight = screenFrame.height * AppWindowLayout.visibleAreaRatio

        if isLoggedIn {
            window.minSize = NSSize(width: AppWindowLayout.mainMinWidth, height: AppWindowLayout.mainMinHeight)

            let targetWidth = min(max(window.frame.width, AppWindowLayout.mainMinWidth), maxWidth)
            let targetHeight = min(max(window.frame.height, AppWindowLayout.mainMinHeight), maxHeight)
            window.setContentSize(NSSize(width: targetWidth, height: targetHeight))
        } else {
            window.minSize = NSSize(width: AppWindowLayout.loginWidth, height: AppWindowLayout.loginHeight)
            let targetWidth = min(AppWindowLayout.loginWidth, maxWidth)
            let targetHeight = min(AppWindowLayout.loginHeight, maxHeight)
            window.setContentSize(NSSize(width: targetWidth, height: targetHeight))
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
