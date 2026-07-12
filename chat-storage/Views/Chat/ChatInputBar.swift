//
//  ChatInputBar.swift
//  chat-storage
//

import AppKit
import SwiftUI

struct ChatInputBar: View {
    let friendName: String
    @Binding var messageText: String
    @Binding var showEmojiPicker: Bool
    @Binding var pendingInsertToken: String?
    @Binding var quotedMessage: ChatMessage?
    @Binding var pendingImages: [PendingChatImage]
    @Binding var pendingImageError: String?
    @Binding var isSending: Bool
    let onSendNudge: () -> Void
    let onPickImages: () -> Void
    let onPasteImage: (NSImage) -> Void
    let onRemovePendingImage: (UUID) -> Void
    let onSendMessage: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            toolBar

            if showEmojiPicker {
                EmojiPickerPanel { emoji in
                    showEmojiPicker = false
                    pendingInsertToken = emoji
                    ChatEmojiStore.storeRecent(emoji)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            quotePreview
            imagePreview
            textEditor
        }
        .background(Color(NSColor.textBackgroundColor))
        .frame(minHeight: 150)
    }

    private var toolBar: some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showEmojiPicker.toggle()
                }
            }) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 18))
                    .foregroundColor(showEmojiPicker ? .accentColor : .secondary)
            }
            Button(action: onPickImages) { Image(systemName: "photo.on.rectangle").font(.system(size: 18)).help("选择图片") }
            Button(action: {}) { Image(systemName: "scissors").font(.system(size: 18)) }
            Button(action: {}) { Image(systemName: "mic").font(.system(size: 18)) }
            Spacer()
            Button(action: onSendNudge) { Image(systemName: "hand.tap").font(.system(size: 18)).help("抖一抖") }
            Button(action: {}) { Image(systemName: "phone").font(.system(size: 18)) }
            Button(action: {}) { Image(systemName: "video").font(.system(size: 18)) }
        }
        .foregroundColor(.secondary)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var quotePreview: some View {
        if let quotedMessage {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quotedMessage.isMe ? "我" : friendName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                    Text(quotedMessage.displayText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: { self.quotedMessage = nil }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if !pendingImages.isEmpty || pendingImageError != nil {
            VStack(alignment: .leading, spacing: 8) {
                if !pendingImages.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        LazyVGrid(columns: imageGridColumns, alignment: .leading, spacing: 8) {
                            ForEach(pendingImages) { item in
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: item.previewImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                        )

                                    Button(action: { onRemovePendingImage(item.id) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.black.opacity(0.55))
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(isSending)
                                    .offset(x: 5, y: -5)
                                }
                                .frame(width: 64, height: 64)
                            }
                        }
                        .frame(maxWidth: 224, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(pendingImages.count)/\(ChatMixedMessageContent.maxImageCount) 张图片")
                                .font(.caption.weight(.semibold))
                            Text(isSending ? "上传中..." : "可继续输入文字后一起发送")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }

                if let pendingImageError {
                    Text(pendingImageError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .padding(.horizontal, 12)
        }
    }

    private var imageGridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(64), spacing: 8), count: min(3, max(1, pendingImages.count)))
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
    }

    private var textEditor: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if messageText.isEmpty {
                    Text("请输入消息...")
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                        .padding(.top, 4)
                        .font(.system(size: 14))
                        .allowsHitTesting(false)
                }
                MacResponsiveTextView(
                    text: $messageText,
                    insertToken: $pendingInsertToken,
                    onPasteImage: onPasteImage,
                    onSendTriggered: onSendMessage
                )
                .frame(minHeight: 36, maxHeight: 150)
            }
            .background(Color.clear)

            Button(action: onSendMessage) {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.borderless)
            .foregroundColor(canSend ? .accentColor : .secondary)
            .disabled(isSending || !canSend)
            .help("发送")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}
