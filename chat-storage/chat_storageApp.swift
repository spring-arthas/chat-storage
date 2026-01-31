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

    // 登录状态
    @State private var isLoggedIn = false

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                // 主界面
                MainChatStorage(isLoggedIn: $isLoggedIn)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(socketManager)
                    .frame(minWidth: 1100, minHeight: 700) // 主界面最小尺寸增大以容纳进度条列
            } else {
                // 登录界面
                LoginView(isLoggedIn: $isLoggedIn)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(socketManager)
                    .frame(width: 500, height: 550) // 登录界面固定尺寸
            }
        }
        .windowStyle(isLoggedIn ? .hiddenTitleBar : .hiddenTitleBar) // 两者都隐藏标题栏，或根据需求调整
        .windowResizability(isLoggedIn ? .contentMinSize : .contentSize) // 登录界面固定内容大小，主界面限制最小尺寸
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
