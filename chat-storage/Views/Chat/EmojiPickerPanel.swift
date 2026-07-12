//
//  EmojiPickerPanel.swift
//  chat-storage
//

import SwiftUI

struct EmojiPickerPanel: View {
    let onEmojiSelected: (String) -> Void

    private let categories: [(String, String, [String])] = [
        ("笑脸", "face.smiling", [
            "😀","😁","😂","🤣","😃","😄","😅","😆","😉","😊",
            "😋","😎","😍","🥰","😘","😗","😙","😚","🙂","🤗",
            "🤩","🤔","🤨","😐","😑","😶","🙄","😏","😣","😥",
            "😮","🤐","😯","😪","😫","🥱","😴","😌","😛","😜",
            "😝","🤤","😒","😓","😔","😕","🙃","🤑","😲","☹️",
            "🙁","😖","😞","😟","😤","😢","😭","😦","😧","😨",
            "😩","🤯","😬","😰","😱","🥵","🥶","😳","🤪","😠"
        ]),
        ("手势", "hand.raised", [
            "👋","🤚","🖐","✋","🖖","👌","🤏","✌️","🤞","🤟",
            "🤘","🤙","👈","👉","👆","🖕","👇","☝️","👍","👎",
            "✊","👊","🤛","🤜","👏","🙌","👐","🤲","🤝","🙏",
            "✍️","💪","🦾","🦿","🦵","🦶","👂","🦻"
        ]),
        ("人物", "person", [
            "👶","🧒","👦","👧","🧑","👱","👨","🧔","👩","🧓",
            "👴","👵","🙍","🙎","🙅","🙆","💁","🙋","🧏","🙇",
            "🤦","🤷","👮","💂","👷","🤴","👸","🦸","🦹"
        ]),
        ("动物", "pawprint", [
            "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯",
            "🦁","🐮","🐷","🐸","🐵","🙈","🙉","🙊","🐔","🐧",
            "🐦","🐤","🦆","🦅","🦉","🦇","🐺","🐴","🦄","🐢",
            "🐍","🦎","🐊","🦕","🦖","🦈","🐋","🐬","🦭","🐘"
        ]),
        ("食物", "fork.knife", [
            "🍎","🍊","🍋","🍇","🍓","🍈","🍒","🍑","🥭","🍍",
            "🥥","🥝","🍅","🍆","🥑","🥦","🌽","🥕","🧄","🧅",
            "🍔","🍟","🍕","🌮","🌯","🥪","🥙","🧆","🥚","🍳",
            "🍿","🧂","🥞","🧇","🧈","🍱","🍜","🍣","🍦","☕️"
        ]),
        ("活动", "sportscourt", [
            "⚽️","🏀","🏈","⚾️","🎾","🏐","🏉","🎱","🏓","🏸",
            "🥊","🥋","🎽","🛹","🛷","⛸","🏂","🏋️","🤸","🤺",
            "🏊","🚴","🧘","🎯","🎳","🎲","🎮","🎸","🎺","🎻"
        ]),
        ("旅行", "car", [
            "🚗","🚕","🚙","🚌","🏎","🚓","🚒","🚐","🚚","✈️",
            "🚀","🛸","🚁","🛶","⛵️","🚢","🚂","🏠","🏢","🗼",
            "🗽","⛩","🎡","🎢","🎠","🌍","🌏","🌙","☀️","🌈"
        ]),
        ("符号", "heart", [
            "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔",
            "❣️","💕","💞","💓","💗","💖","💘","💝","💯","✅",
            "❎","🔴","🟠","🟡","🟢","🔵","🟣","⚫️","⚪️","🟤",
            "🔶","🔷","🔸","🔹","🔺","🔻","💠","🔘","🔲","🔳"
        ]),
        ("物品", "star", [
            "🎁","🎈","🎉","🎊","🎀","🏆","🥇","🥈","🥉","🎖",
            "🔑","🗝","🔒","🔓","🔔","🔕","🎵","🎶","💡","🔦",
            "📱","💻","⌨️","🖥","🖨","📷","📸","📹","🎥","📺",
            "📚","📖","✏️","🖊","📝","💼","🎒","🌂","☂️","🧲"
        ])
    ]

    @State private var selectedCategoryIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategoryIndex = index
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: category.1)
                                .font(.system(size: 13))
                            Text(category.0)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            selectedCategoryIndex == index
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .foregroundColor(selectedCategoryIndex == index ? .accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 0)],
                    spacing: 0
                ) {
                    ForEach(categories[selectedCategoryIndex].2, id: \.self) { emoji in
                        EmojiCell(emoji: emoji, onTap: onEmojiSelected)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .frame(height: 160)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: -3)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }
}

private struct EmojiCell: View {
    let emoji: String
    let onTap: (String) -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: { onTap(emoji) }) {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.secondary.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
    }
}
