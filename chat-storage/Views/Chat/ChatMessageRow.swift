//
//  ChatMessageRow.swift
//  chat-storage
//

import AppKit
import SwiftUI

struct ChatImagePreviewContext: Identifiable {
    let selectedAttachment: ChatImageAttachment
    let attachments: [ChatImageAttachment]

    var id: Int64 { selectedAttachment.fileId }
}

struct ChatMessageRow: View {
    let message: ChatMessage
    let friendName: String
    let friendAvatarBase64: String?
    let friendAvatarColor: Color
    let onCopy: (ChatMessage) -> Void
    let onQuote: (ChatMessage) -> Void
    let onDeleteLocal: (ChatMessage) -> Void
    let onRetract: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void
    let onDoubleTap: () -> Void
    let onPreviewImage: (ChatImageAttachment, [ChatImageAttachment]) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isMe {
                Spacer(minLength: 60)
                HStack(alignment: .bottom, spacing: 4) {
                    ChatBubbleView(
                        message: message,
                        friendName: friendName,
                        onRetry: onRetry,
                        onPreviewImage: onPreviewImage
                    )
                        .padding(10)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(TailChatBubbleShape(isMe: true))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                renderAvatar(base64String: message.avatar, fallbacName: "我", fallbackColor: .gray)
            } else {
                renderAvatar(
                    base64String: message.avatar ?? friendAvatarBase64,
                    fallbacName: String(friendName.prefix(1)),
                    fallbackColor: friendAvatarColor
                )
                HStack(alignment: .bottom, spacing: 4) {
                    ChatBubbleView(
                        message: message,
                        friendName: friendName,
                        onRetry: onRetry,
                        onPreviewImage: onPreviewImage
                    )
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .foregroundColor(.primary)
                        .clipShape(TailChatBubbleShape(isMe: false))
                        .overlay(TailChatBubbleShape(isMe: false).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                Spacer(minLength: 60)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.9, anchor: message.isMe ? .trailing : .leading)),
            removal: .opacity
        ))
        .contextMenu {
            messageContextMenu
        }
        .padding(.vertical, 2)
        .id(message.id)
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        Button("复制") {
            onCopy(message)
        }
        .disabled(message.retracted || message.sendStatus == .retracted)

        Button("引用") {
            onQuote(message)
        }
        .disabled(message.retracted || message.sendStatus == .retracted)

        if message.isMe && message.sendStatus == .failed {
            Button("重试") {
                onRetry(message)
            }
        }

        Divider()

        Button("本地删除") {
            onDeleteLocal(message)
        }

        if message.isMe, message.messageId != nil, !message.retracted, message.sendStatus != .retracted {
            Button("撤回") {
                onRetract(message)
            }
        }
    }

    @ViewBuilder
    private func renderAvatar(base64String: String?, fallbacName: String, fallbackColor: Color) -> some View {
        InteractiveAvatarView(
            base64String: base64String,
            fallbacName: fallbacName,
            fallbackColor: fallbackColor,
            cache: ChatAvatarCache.shared
        )
    }
}

private struct ChatBubbleView: View {
    let message: ChatMessage
    let friendName: String
    let onRetry: (ChatMessage) -> Void
    let onPreviewImage: (ChatImageAttachment, [ChatImageAttachment]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.retracted || message.sendStatus == .retracted {
                Text(message.isMe ? "你撤回了一条消息" : "\(friendName)撤回了一条消息")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundColor(message.isMe ? .white.opacity(0.82) : .secondary)
            } else {
                if let quoteContent = message.quoteMsgContent, !quoteContent.isEmpty {
                    quoteBlock(quoteContent)
                }

                messageContentView

                if message.isMe {
                    sendStatusView
                }
            }
        }
    }

    @ViewBuilder
    private var messageContentView: some View {
        let payload = ChatMessagePayload.parse(content: message.content, msgType: message.type)
        if !payload.images.isEmpty {
            ChatMediaBubbleView(
                images: payload.images,
                text: payload.text,
                isMe: message.isMe,
                onPreviewImage: onPreviewImage
            )
        } else {
            Text(payload.displayText)
                .font(.system(size: 14))
                .textSelection(.enabled)
        }
    }

    private func quoteBlock(_ quoteContent: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.quoteMsgSenderName ?? "引用消息")
                .font(.caption2.weight(.semibold))
            Text(quoteContent)
                .font(.caption2)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background((message.isMe ? Color.white : Color.accentColor).opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var sendStatusView: some View {
        switch message.sendStatus {
        case .uploadingMedia:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                Text("上传中")
                    .font(.caption2)
            }
            .opacity(0.78)
        case .sending:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                Text("发送中")
                    .font(.caption2)
            }
            .opacity(0.78)
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                Text(message.errorMessage ?? "发送失败")
                Button(action: { onRetry(message) }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption2)
        case .success, .retracted:
            EmptyView()
        }
    }
}

private struct ChatMediaBubbleView: View {
    let images: [ChatImageAttachment]
    let text: String
    let isMe: Bool
    let onPreviewImage: (ChatImageAttachment, [ChatImageAttachment]) -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: trimmedText.isEmpty ? 0 : 8) {
            ChatImageGridView(
                attachments: images,
                isMe: isMe,
                onPreviewImage: onPreviewImage
            )
            if !trimmedText.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ChatImageGridView: View {
    let attachments: [ChatImageAttachment]
    let isMe: Bool
    let onPreviewImage: (ChatImageAttachment, [ChatImageAttachment]) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellSize), spacing: 6), count: columnCount)
    }

    private var columnCount: Int {
        min(3, max(1, attachments.count))
    }

    private var cellSize: CGFloat {
        attachments.count == 1 ? 172 : 92
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(attachments) { attachment in
                ChatImageThumbnailCell(
                    attachment: attachment,
                    isMe: isMe,
                    size: cellSize,
                    onOpen: {
                        onPreviewImage(attachment, attachments)
                    }
                )
            }
        }
    }
}

private struct ChatImageThumbnailCell: View {
    let attachment: ChatImageAttachment
    let isMe: Bool
    let size: CGFloat
    let onOpen: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var didFailThumbnail = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill((isMe ? Color.white : Color.accentColor).opacity(0.12))
                .frame(width: size, height: size)

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        if attachment.isLocalPending {
                            ZStack {
                                Color.black.opacity(0.18)
                                ProgressView()
                                    .controlSize(.small)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
            } else if didFailThumbnail {
                Text("[图片]")
                    .font(.caption)
                    .foregroundColor(isMe ? .white.opacity(0.82) : .secondary)
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("图片")
                        .font(.caption)
                }
                .foregroundColor(isMe ? .white.opacity(0.82) : .secondary)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture(count: 1).onEnded { onOpen() })
        .help("查看原图")
        .accessibilityLabel("查看图片")
        .task(id: attachment.fileId) {
            await MainActor.run {
                self.thumbnail = nil
                self.didFailThumbnail = false
            }
            if attachment.isLocalPending {
                await MainActor.run {
                    let localImage = ChatPendingImageStore.shared.image(for: attachment.fileId)
                    self.thumbnail = localImage
                    self.didFailThumbnail = localImage == nil
                }
                return
            }
            let loaded = await FileThumbnailService.shared.thumbnail(for: attachment.thumbnailDirectoryItem())
            await MainActor.run {
                self.thumbnail = loaded
                self.didFailThumbnail = loaded == nil
            }
        }
    }
}

struct ChatImagePreviewOverlay: View {
    let context: ChatImagePreviewContext
    let attachments: [ChatImageAttachment]
    let onClose: () -> Void
    @State private var selectedAttachment: ChatImageAttachment
    @State private var image: NSImage? = nil
    @State private var didFail = false
    @State private var reloadToken = 0

    init(context: ChatImagePreviewContext, onClose: @escaping () -> Void) {
        self.context = context
        self.onClose = onClose
        let availableAttachments = context.attachments.isEmpty
            ? [context.selectedAttachment]
            : context.attachments
        self.attachments = availableAttachments
        _selectedAttachment = State(initialValue: context.selectedAttachment)
    }

    private var currentIndex: Int {
        attachments.firstIndex { $0.fileId == selectedAttachment.fileId } ?? 0
    }

    private var canNavigate: Bool {
        attachments.count > 1
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                previewHeader

                ZStack {
                    Color.black

                    if canNavigate {
                        previewTapNavigationZones
                    }

                    previewContent
                        .allowsHitTesting(didFail)

                    if canNavigate {
                        previewNavigationControls
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
        .task(id: previewLoadKey) {
            await reloadPreviewImage(forceReload: reloadToken > 0)
        }
    }

    private var previewHeader: some View {
        HStack(spacing: 12) {
            Text(selectedAttachment.fileName)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(.white)

            Spacer()

            if canNavigate {
                Text("\(currentIndex + 1)/\(attachments.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.14))
            .clipShape(Circle())
            .help("关闭")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.84))
    }

    private var previewLoadKey: String {
        "\(selectedAttachment.previewFileId ?? selectedAttachment.fileId)-\(reloadToken)"
    }

    @ViewBuilder
    private var previewContent: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 84)
                .padding(.vertical, 28)
        } else if didFail {
            VStack(spacing: 12) {
                Text("图片加载失败")
                    .foregroundColor(.white.opacity(0.82))
                Button(action: {
                    reloadToken += 1
                }) {
                    Label("重新加载", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())
                .foregroundColor(.white)
            }
        } else {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                Text("正在加载高清图...")
                    .foregroundColor(.white.opacity(0.82))
            }
        }
    }

    private var previewNavigationControls: some View {
        HStack {
            navigationButton(systemName: "chevron.left", action: showPreviousImage)
                .disabled(currentIndex == 0)

            Spacer(minLength: 0)

            navigationButton(systemName: "chevron.right", action: showNextImage)
                .disabled(currentIndex >= attachments.count - 1)
        }
        .padding(.horizontal, 18)
    }

    private var previewTapNavigationZones: some View {
        HStack(spacing: 0) {
            Button(action: showPreviousImage) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(currentIndex == 0)
            .help("上一张")

            Button(action: showNextImage) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= attachments.count - 1)
            .help("下一张")
        }
    }

    private func navigationButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: systemName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 76, height: 140)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showPreviousImage() {
        guard currentIndex > 0 else { return }
        reloadToken = 0
        selectedAttachment = attachments[currentIndex - 1]
    }

    private func showNextImage() {
        guard currentIndex < attachments.count - 1 else { return }
        reloadToken = 0
        selectedAttachment = attachments[currentIndex + 1]
    }

    private func reloadPreviewImage(forceReload: Bool) async {
        await MainActor.run {
            self.image = nil
            self.didFail = false
        }
        if selectedAttachment.isLocalPending {
            await MainActor.run {
                let localImage = ChatPendingImageStore.shared.image(for: selectedAttachment.fileId)
                self.image = localImage
                self.didFail = localImage == nil
            }
            return
        }
        let loaded = await FileThumbnailService.shared.previewImage(
            for: selectedAttachment.previewDirectoryItem(),
            forceReload: forceReload
        )
        await MainActor.run {
            self.image = loaded
            self.didFail = loaded == nil
        }
    }
}

struct TailChatBubbleShape: Shape {
    var isMe: Bool
    var cornerRadius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height
        let r = cornerRadius

        if isMe {
            path.move(to: CGPoint(x: 0, y: r))
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w - r, y: h))
            path.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: w, y: h - r))
            path.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: r, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            path.closeSubpath()
        }

        return path
    }
}
