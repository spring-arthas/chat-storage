//  macOs入口程序
//  chat_storageApp.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/29.
//

import SwiftUI
import AppKit
import os.log

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

    @State private var didAttemptSessionRestoration = false

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
            .onChange(of: authService.isAuthenticated) { authenticated in
                // [修改] 自动刷新重试成功后也要立刻切回主界面，不能停留在登录页。
                if isLoggedIn != authenticated {
                    isLoggedIn = authenticated
                }
            }
            .task {
                guard !didAttemptSessionRestoration else { return }
                didAttemptSessionRestoration = true
                let restored = await authService.restoreSession()
                if restored {
                    isLoggedIn = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard didAttemptSessionRestoration else { return }
                Task { @MainActor in
                    // [修改] 回到前台时换发 transferToken，避免网盘在令牌到期后突然全部失败。
                    let authenticated = await authService.resumeForForeground()
                    if authenticated {
                        isLoggedIn = true
                    }
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
        Self.refreshDockIcon()
        os_log("🔍 [App] init 开始", log: .default, type: .info)

        // [修改] 启动时先恢复上次服务器，随后才能读取该服务器隔离的 Keychain 会话。
        let endpoint = ServerEndpointStore.load()
            ?? ServerEndpoint(host: ServerEndpoint.defaultHost, port: 10_086)
        os_log("🔍 [App] 服务器地址: %{public}@:%{public}@", log: .default, type: .info, endpoint.host, String(endpoint.port))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            os_log("🔍 [App] asyncAfter 触发，调用 connect", log: .default, type: .info)
            SocketManager.shared.connect(host: endpoint.host, port: endpoint.port)
        }
    }

    private static func refreshDockIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
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
