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

    var body: some Scene {
        WindowGroup {
            LoginView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(socketManager)  // 注入到视图树，所有子视图都可访问
        }
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
