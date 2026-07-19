//  macOs入口程序
//  chat_storageApp.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/29.
//

import SwiftUI
import AppKit

enum AppWindowLayout {
    static let mainDefaultWidth: CGFloat = 1240
    static let mainDefaultHeight: CGFloat = 760
    static let mainMinWidth: CGFloat = 1240
    static let mainMinHeight: CGFloat = 760
    static let loginWidth: CGFloat = 720
    static let loginHeight: CGFloat = 456
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
                        .frame(
                            minWidth: AppWindowLayout.mainMinWidth,
                            maxWidth: .infinity,
                            minHeight: AppWindowLayout.mainMinHeight,
                            maxHeight: .infinity
                        )
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

        if isLoggedIn {
            let minimumSize = NSSize(
                width: AppWindowLayout.mainMinWidth,
                height: AppWindowLayout.mainMinHeight
            )
            let defaultSize = NSSize(
                width: AppWindowLayout.mainDefaultWidth,
                height: AppWindowLayout.mainDefaultHeight
            )
            let needsInitialResize = window.contentLayoutRect.width < minimumSize.width
                || window.contentLayoutRect.height < minimumSize.height

            window.styleMask.insert(.resizable)
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.minSize = minimumSize
            window.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            window.standardWindowButton(.zoomButton)?.isEnabled = true
            window.standardWindowButton(.zoomButton)?.isHidden = false

            if needsInitialResize {
                window.setContentSize(defaultSize)
                window.center()
            } else if let screen = window.screen ?? NSScreen.main {
                let constrainedFrame = window.constrainFrameRect(window.frame, to: screen)
                if constrainedFrame != window.frame {
                    window.setFrame(constrainedFrame, display: true)
                }
            }
        } else {
            let fixedSize = NSSize(width: AppWindowLayout.loginWidth, height: AppWindowLayout.loginHeight)
            window.styleMask.remove(.resizable)
            window.minSize = fixedSize
            window.maxSize = fixedSize
            if window.contentLayoutRect.size != fixedSize {
                window.setContentSize(fixedSize)
                window.center()
            }
        }

        window.makeKeyAndOrderFront(nil)
    }
}
