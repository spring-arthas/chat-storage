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
    let currentUserAvatarBase64: String?
    let friendAvatarBase64: String?
    let friendAvatarColor: Color
    let onCopy: (ChatMessage) -> Void
    let onQuote: (ChatMessage) -> Void
    let onDeleteLocal: (ChatMessage) -> Void
    let onRetract: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void
    let onRetryAttachment: (ChatMessage, ChatAttachment) -> Void
    let onRemoveAttachment: (ChatMessage, ChatAttachment) -> Void
    let onDoubleTap: () -> Void
    let onPreviewImage: (ChatImageAttachment, [ChatImageAttachment]) -> Void
    let onDownloadAttachment: (ChatAttachment) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isMe {
                Spacer(minLength: 60)
                HStack(alignment: .bottom, spacing: 4) {
                    ChatBubbleView(
                        message: message,
                        friendName: friendName,
                        onRetry: onRetry,
                        onRetryAttachment: { onRetryAttachment(message, $0) },
                        onRemoveAttachment: { onRemoveAttachment(message, $0) },
                        onPreviewImage: onPreviewImage,
                        onDownloadAttachment: onDownloadAttachment
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
                renderAvatar(
                    base64String: message.avatar ?? currentUserAvatarBase64,
                    fallbacName: "我",
                    fallbackColor: .gray
                )
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
                        onRetryAttachment: { onRetryAttachment(message, $0) },
                        onRemoveAttachment: { onRemoveAttachment(message, $0) },
                        onPreviewImage: onPreviewImage,
                        onDownloadAttachment: onDownloadAttachment
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
    let onRetryAttachment: (ChatAttachment) -> Void
    let onRemoveAttachment: (ChatAttachment) -> Void
    let onPreviewImage: (ChatImageAttachment, [ChatImageAttachment]) -> Void
    let onDownloadAttachment: (ChatAttachment) -> Void

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
        let payload = message.preparedPayload
        if !payload.attachments.isEmpty {
            ChatMediaBubbleView(
                images: payload.images,
                files: payload.files,
                text: payload.text,
                isMe: message.isMe,
                clientMsgId: message.clientMsgId,
                onRetryAttachment: onRetryAttachment,
                onRemoveAttachment: onRemoveAttachment,
                onPreviewImage: onPreviewImage,
                onDownloadAttachment: onDownloadAttachment
            )
        } else {
            Text(payload.displayText)
                .font(.system(size: 14))
        }
    }

    private func quoteBlock(_ quoteContent: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.quoteMsgSenderName ?? "引用消息")
                .font(.caption2.weight(.semibold))
            Text(quoteContent)
                .font(.caption2)
                .lineLimit(2)
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
    let files: [ChatAttachment]
    let text: String
    let isMe: Bool
    let clientMsgId: String?
    let onRetryAttachment: (ChatAttachment) -> Void
    let onRemoveAttachment: (ChatAttachment) -> Void
    let onPreviewImage: (ChatImageAttachment, [ChatImageAttachment]) -> Void
    let onDownloadAttachment: (ChatAttachment) -> Void
    @ObservedObject private var transferStore = ChatAttachmentTransferStore.shared

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !images.isEmpty {
                ChatImageGridView(
                    attachments: images,
                    isMe: isMe,
                    onPreviewImage: onPreviewImage
                )
                ForEach(images) { attachment in
                    if let transfer = transferStore.transfer(clientMsgId: clientMsgId, attachment: attachment),
                       transfer.state != .succeeded {
                        ChatAttachmentTransferStatusRow(
                            attachment: attachment,
                            transfer: transfer,
                            isMe: isMe,
                            onRetry: { onRetryAttachment(attachment) },
                            onRemove: { onRemoveAttachment(attachment) }
                        )
                    }
                }
            }
            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(files) { attachment in
                        ChatFileAttachmentCard(
                            attachment: attachment,
                            isMe: isMe,
                            transfer: transferStore.transfer(clientMsgId: clientMsgId, attachment: attachment),
                            download: transferStore.download(for: attachment.fileId),
                            onRetry: { onRetryAttachment(attachment) },
                            onRemove: { onRemoveAttachment(attachment) },
                            onDownload: { onDownloadAttachment(attachment) }
                        )
                    }
                }
            }
            if !trimmedText.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ChatFileAttachmentCard: View {
    let attachment: ChatAttachment
    let isMe: Bool
    let transfer: ChatAttachmentTransferSnapshot?
    let download: ChatAttachmentDownloadSnapshot?
    let onRetry: () -> Void
    let onRemove: () -> Void
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: attachment.directoryItem().iconName)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundColor(isMe ? .white : .accentColor)
                    .frame(width: 34, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ByteCountFormatter.string(fromByteCount: attachment.fileSize, countStyle: .file))
                        .font(.caption2)
                        .opacity(0.72)
                }
                .frame(maxWidth: 210, alignment: .leading)

                Spacer(minLength: 4)

                statusControl
            }
            if let transfer, transfer.state == .uploading {
                ProgressView(value: transfer.progress)
                    .progressViewStyle(.linear)
            } else if let download, download.state == .downloading {
                ProgressView(value: download.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 220, maxWidth: 300, alignment: .leading)
        .background((isMe ? Color.white : Color.accentColor).opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusControl: some View {
        if let transfer {
            switch transfer.state {
            case .waiting, .uploading:
                ProgressView().controlSize(.small)
                Button(action: onRemove) { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
            case .paused, .failed:
                Button(action: onRetry) { Image(systemName: "arrow.clockwise.circle") }
                    .buttonStyle(.borderless)
                    .help("重新上传")
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("删除附件")
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
            case .removed:
                EmptyView()
            }
        } else if let download {
            switch download.state {
            case .downloading:
                ProgressView().controlSize(.small)
            case .failed, .paused:
                Button(action: onDownload) { Image(systemName: "arrow.clockwise.circle") }
                    .buttonStyle(.borderless)
                    .help("重新下载")
            case .completed:
                Button(action: onDownload) { Image(systemName: "checkmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help(download.targetPath)
            case .notDownloaded:
                Button(action: onDownload) { Image(systemName: "arrow.down.circle") }
                    .buttonStyle(.borderless)
            }
        } else {
            Button(action: onDownload) { Image(systemName: "arrow.down.circle") }
                .buttonStyle(.borderless)
                .disabled(attachment.isLocalPending)
        }
    }
}

private struct ChatAttachmentTransferStatusRow: View {
    let attachment: ChatAttachment
    let transfer: ChatAttachmentTransferSnapshot
    let isMe: Bool
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(attachment.fileName)
                .font(.caption2)
                .lineLimit(1)
            if transfer.state == .uploading || transfer.state == .waiting {
                ProgressView(value: transfer.progress)
                    .frame(width: 70)
                Text("\(Int(transfer.progress * 100))%")
                    .font(.caption2)
            } else {
                Image(systemName: "exclamationmark.circle")
                Button("重试", action: onRetry).buttonStyle(.borderless)
                Button("删除", action: onRemove).buttonStyle(.borderless)
            }
        }
        .foregroundColor(isMe ? .white.opacity(0.9) : .secondary)
    }
}

private struct ChatImageGridView: View {
    let attachments: [ChatImageAttachment]
    let isMe: Bool
    let onPreviewImage: (ChatImageAttachment, [ChatImageAttachment]) -> Void

    var body: some View {
        if let attachment = attachments.first, attachments.count == 1 {
            ChatImageThumbnailCell(
                attachment: attachment,
                isMe: isMe,
                size: attachment.bubblePreviewSize(),
                onOpen: {
                    onPreviewImage(attachment, attachments)
                }
            )
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(attachments) { attachment in
                    ChatImageThumbnailCell(
                        attachment: attachment,
                        isMe: isMe,
                        size: CGSize(width: 92, height: 92),
                        onOpen: {
                            onPreviewImage(attachment, attachments)
                        }
                    )
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(92), spacing: 6), count: min(3, max(1, attachments.count)))
    }
}

private struct ChatImageThumbnailCell: View {
    let attachment: ChatImageAttachment
    let isMe: Bool
    let size: CGSize
    let onOpen: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var didFailThumbnail = false
    @State private var reloadToken = 0

    private var bubbleSource: DirectoryItem? {
        attachment.bubbleThumbnailDirectoryItem()
    }

    private var thumbnailLoadKey: String {
        "\(bubbleSource?.id ?? attachment.fileId)-\(reloadToken)"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill((isMe ? Color.white : Color.accentColor).opacity(0.12))
                .frame(width: size.width, height: size.height)

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
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
            } else if !attachment.isLocalPending && bubbleSource == nil {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                    Text("暂无缩略图")
                        .font(.caption)
                }
                .foregroundColor(isMe ? .white.opacity(0.82) : .secondary)
            } else if didFailThumbnail {
                VStack(spacing: 6) {
                    Text("图片加载失败")
                        .font(.caption)
                    Button("重试") { reloadToken += 1 }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
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
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { onOpen() }
        .help("查看原图")
        .accessibilityLabel("查看图片")
        .task(id: thumbnailLoadKey) {
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
            guard let bubbleSource = attachment.bubbleThumbnailDirectoryItem() else {
                return
            }
            let loaded = await FileThumbnailService.shared.thumbnail(for: bubbleSource)
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
            ZoomablePreviewImageView(image: image)
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
        let loaded = await FileThumbnailService.shared.previewImage(for: selectedAttachment, forceReload: forceReload)
        await MainActor.run {
            self.image = loaded
            self.didFail = loaded == nil
        }
    }
}

private struct ZoomablePreviewImageView: View {
    let image: NSImage

    @State private var zoomScale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1

    private let minZoomScale: CGFloat = 0.2
    private let maxZoomScale: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let displayScale = clamp(zoomScale * pinchScale)

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: max(1, image.size.width * displayScale),
                        height: max(1, image.size.height * displayScale)
                    )
                    .padding(.horizontal, 84)
                    .padding(.vertical, 28)
                    .frame(minWidth: viewportSize.width, minHeight: viewportSize.height)
            }
            .onAppear {
                zoomScale = initialZoomScale(imageSize: image.size, viewportSize: viewportSize)
            }
            .onChange(of: viewportSize) { newValue in
                zoomScale = initialZoomScale(imageSize: image.size, viewportSize: newValue)
            }
            .gesture(
                MagnificationGesture()
                    .updating($pinchScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        zoomScale = clamp(zoomScale * value)
                    }
            )
        }
    }

    private func initialZoomScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return 1
        }

        let paddedWidth = max(1, viewportSize.width - 168)
        let paddedHeight = max(1, viewportSize.height - 56)
        let widthFit = paddedWidth / imageSize.width
        let heightFit = paddedHeight / imageSize.height
        let ratio = imageSize.height / max(1, imageSize.width)

        if ratio >= 3 {
            return clamp(min(widthFit, 1))
        }

        return clamp(min(min(widthFit, heightFit), 1))
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(maxZoomScale, max(minZoomScale, value))
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
