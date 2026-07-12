//
//  ChatEmojiStore.swift
//  chat-storage
//

import Foundation

enum ChatEmojiStore {
    private static let recentEmojisKey = "chat.recentEmojis"

    static func storeRecent(_ emoji: String) {
        let defaults = UserDefaults.standard
        var emojis = defaults.stringArray(forKey: recentEmojisKey) ?? []
        emojis.removeAll(where: { $0 == emoji })
        emojis.insert(emoji, at: 0)
        defaults.set(Array(emojis.prefix(24)), forKey: recentEmojisKey)
    }
}
