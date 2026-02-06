//  macOs入口程序
//  chat_storageApp.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/29.
//

import SwiftUI

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
                        .frame(minWidth: 1650, idealWidth: 3300, minHeight: 1050, idealHeight: 2100) // 尺寸扩大 0.5 倍
                } else {
                    // 登录界面
                    LoginView(isLoggedIn: $isLoggedIn)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(socketManager)
                        .environmentObject(authService)
                        .frame(width: 500, height: 550) // 登录界面固定尺寸
                }
            }
            .onAppear {
                // 确保窗口在启动时居中显示
                DispatchQueue.main.async {
                    if let window = NSApplication.shared.windows.first {
                        window.center()
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
            .onChange(of: isLoggedIn) { newValue in
                if newValue {
                    // 登录成功后，延迟执行居中，确保窗口尺寸调整已完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if let window = NSApplication.shared.windows.first {
                            window.center()
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(isLoggedIn ? .contentMinSize : .contentSize)
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
}
