//
//  ChatInputBar.swift
//  chat-storage
//

import AppKit
import SwiftUI

enum ChatInputPlaceholderPolicy {
    static func shouldShow(
        messageText: String,
        isComposing: Bool,
        hasAttachments: Bool,
        hasQuote: Bool
    ) -> Bool {
        messageText.isEmpty && !isComposing && !hasAttachments && !hasQuote
    }
}

struct ChatInputBar: View {
    let friendName: String
    @Binding var messageText: String
    @Binding var showEmojiPicker: Bool
    @Binding var pendingInsertToken: String?
    @Binding var quotedMessage: ChatMessage?
    @Binding var pendingAttachments: [PendingChatAttachment]
    @Binding var pendingAttachmentError: String?
    let onPickAttachments: () -> Void
    let onPasteImage: (NSImage) -> Void
    let onRemovePendingAttachment: (UUID) -> Void
    let onSendMessage: () -> Void
    @State private var isComposing = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            toolBar
            quotePreview
            attachmentPreview
            textEditor
        }
        .background(Color(NSColor.textBackgroundColor))
        .frame(minHeight: 150)
        .overlay(alignment: .topLeading) {
            if showEmojiPicker {
                EmojiPickerPanel { emoji in
                    showEmojiPicker = false
                    pendingInsertToken = emoji
                    ChatEmojiStore.storeRecent(emoji)
                }
                .frame(maxWidth: .infinity)
                .offset(y: -214)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(100)
            }
        }
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
            Button(action: onPickAttachments) {
                Image(systemName: "paperclip")
                    .font(.system(size: 18))
                    .help("选择附件")
            }
            Spacer()
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
    private var attachmentPreview: some View {
        if !pendingAttachments.isEmpty || pendingAttachmentError != nil {
            VStack(alignment: .leading, spacing: 8) {
                if !pendingAttachments.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(pendingAttachments) { item in
                                    PendingChatAttachmentCard(
                                        attachment: item,
                                        onRemove: { onRemovePendingAttachment(item.id) }
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: 440, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(pendingAttachments.count)/\(ChatMixedMessageContent.maxAttachmentCount) 个附件")
                                .font(.caption.weight(.semibold))
                            Text("可继续输入文字后一起发送")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }

                if let pendingAttachmentError {
                    Text(pendingAttachmentError)
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

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    private var textEditor: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if ChatInputPlaceholderPolicy.shouldShow(
                    messageText: messageText,
                    isComposing: isComposing,
                    hasAttachments: !pendingAttachments.isEmpty,
                    hasQuote: quotedMessage != nil
                ) {
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
                    isComposing: $isComposing,
                    onPasteImage: onPasteImage,
                    onSendTriggered: onSendMessage
                )
                .frame(minHeight: 36, maxHeight: 150)
            }
            .background(Color.clear)

            Button(action: onSendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .foregroundColor(canSend ? .accentColor : .secondary)
            .disabled(!canSend)
            .help("发送")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}

private struct PendingChatAttachmentCard: View {
    let attachment: PendingChatAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                if let image = attachment.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: fileIcon)
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)
                        .frame(width: 42, height: 54)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.fileName)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                    Text(sizeText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 92, alignment: .leading)
            }
            .padding(7)
            .frame(width: 158, height: 68, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.18)))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.borderless)
            .offset(x: 5, y: -5)
        }
        .frame(width: 164, height: 72)
    }

    private var sizeText: String {
        guard let size = attachment.fileSize else { return attachment.isImage ? "图片" : "文件" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var fileIcon: String {
        attachment.localAttachment().directoryItem().iconName
    }
}
