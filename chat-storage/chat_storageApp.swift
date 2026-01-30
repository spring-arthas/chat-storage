//
//  chat_storageApp.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/29.
//

import SwiftUI

@main
struct chat_storageApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            LoginView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
