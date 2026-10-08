//
//  DynamicTimelineView.swift
//  chat-storage
//
//  动态时间线视图 + 动态卡片 + 媒体网格
//

import SwiftUI
import AppKit

// MARK: - 动态时间线主页

struct DynamicTimelineView: View {
    @StateObject private var viewModel: DynamicTimelineViewModel
    let repository: any DynamicRepository
    let onCompose: () -> Void
    let onOpenDetail: (DynamicPost) -> Void
    let onOpenMedia: (DynamicMedia, [DynamicMedia], DynamicAuthor) -> Void
    @Binding var selectedCategory: Int

    init(
        repository: any DynamicRepository,
        onCompose: @escaping () -> Void,
        onOpenDetail: @escaping (DynamicPost) -> Void,
        onOpenMedia: @escaping (DynamicMedia, [DynamicMedia], DynamicAuthor) -> Void,
        selectedCategory: Binding<Int>
    ) {
        self.repository = repository
        self.onCompose = onCompose
        self.onOpenDetail = onOpenDetail
        self.onOpenMedia = onOpenMedia
        _selectedCategory = selectedCategory
        _viewModel = StateObject(wrappedValue: DynamicTimelineViewModel(
            repository: repository,
            scope: .following
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        loadingView
                    } else if viewModel.posts.isEmpty {
                        emptyView
                    } else {
                        ForEach(viewModel.posts) { post in
                            DynamicPostCard(
                                post: post,
                                comments: viewModel.comments[post.id] ?? [],
                                onOpenDetail: { onOpenDetail(post) },
                                onRepost: { viewModel.toggleRepost(postID: post.id) },
                                onLike: { viewModel.toggleLike(postID: post.id) },
                                onOpenMedia: { media in onOpenMedia(media, post.media, post.author) },
                                onDelete: post.isMine ? { viewModel.delete(postID: post.id) } : nil,
                                onSubmitReply: { content in viewModel.reply(postID: post.id, content: content) },
                                onReplyComment: { content, replyToId in viewModel.replyToComment(postID: post.id, replyToCommentID: replyToId, content: content) },
                                onExpandComments: { expanded in
                                    if expanded {
                                        viewModel.loadComments(postID: post.id, limit: 100)
                                    }
                                },
                                onAppear: { viewModel.loadComments(postID: post.id) }
                            )
                            .id(post.id)
                        }

                        if viewModel.hasMore {
                            ProgressView()
                                .padding(.vertical, 20)
                                .onAppear { viewModel.loadNextPage() }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 20)
        .onAppear { viewModel.loadInitial() }
        .onChange(of: selectedCategory) { newCategory in
            let scope: DynamicTimelineScope
            switch newCategory {
            case 0: scope = .following
            case 1: scope = .mine
            case 2: scope = .liked
            default: scope = .bookmarked
            }
            viewModel.switchScope(scope)
        }
    }

    private var headerBar: some View {
        HStack {
            Spacer()

            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .help("刷新动态")

            Button(action: onCompose) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(TelegramTheme.success, in: Circle())
            }
            .buttonStyle(.plain)
            .help("发布动态")
        }
        .padding(.vertical, 10)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(TelegramTheme.textPrimary)
            Spacer()
            Button(action: { viewModel.clearError() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(TelegramTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(TelegramTheme.success)
            Text("正在加载动态...")
                .font(.system(size: 13))
                .foregroundColor(TelegramTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 42))
                .foregroundColor(TelegramTheme.textSecondary.opacity(0.4))
            Text("还没有动态")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(TelegramTheme.textPrimary)
            Text("好友发布的新内容会出现在这里")
                .font(.system(size: 13))
                .foregroundColor(TelegramTheme.textSecondary)
            Button(action: onCompose) {
                Text("发布第一条动态")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(TelegramTheme.success, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

// MARK: - 动态卡片

struct DynamicPostCard: View {
    let post: DynamicPost
    let comments: [DynamicPost]
    let onOpenDetail: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void
    let onOpenMedia: (DynamicMedia) -> Void
    let onDelete: (() -> Void)?
    let onSubmitReply: (String) -> Void
    let onReplyComment: (String, Int64) -> Void
    let onExpandComments: (Bool) -> Void
    let onAppear: () -> Void

    @State private var isExpanded = false
    @State private var isReplying = false
    @State private var replyText = ""
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部：头像 + 作者信息
            HStack(alignment: .top, spacing: 10) {
                DynamicAvatarView(author: post.author, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Button(action: onOpenDetail) {
                        HStack(spacing: 6) {
                            Text(DynamicText.nonBlank(post.author.nickname) ?? DynamicText.nonBlank(post.author.username) ?? "用户")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(TelegramTheme.textPrimary)
                            Text("@\(DynamicText.nonBlank(post.author.username) ?? "user")")
                                .font(.system(size: 12))
                                .foregroundColor(TelegramTheme.textSecondary)
                            Text("·")
                                .foregroundColor(TelegramTheme.textSecondary.opacity(0.5))
                            Text(DynamicDateText.relative(post.createdAt))
                                .font(.system(size: 12))
                                .foregroundColor(TelegramTheme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if let onDelete {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("删除动态", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(TelegramTheme.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            // 正文
            if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.content)
                        .font(.system(size: 14))
                        .foregroundColor(TelegramTheme.textPrimary)
                        .lineSpacing(3)
                        .lineLimit(isExpanded ? nil : 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenDetail() }

                    if post.content.count > 150 || post.content.filter({ $0 == "\n" }).count > 4 {
                        Button(isExpanded ? "收起" : "展开") {
                            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TelegramTheme.success)
                        .buttonStyle(.plain)
                    }
                }
            }

            // 媒体网格
            if !post.media.isEmpty {
                DynamicMediaGrid(
                    media: post.media,
                    onOpen: onOpenMedia
                )
            }

            // 引用卡片
            if let reference = post.reference {
                DynamicReferenceCard(reference: reference)
            }

            // 转发嵌入
            if let original = post.originalPost?.value {
                DynamicEmbeddedPostCard(post: original, onOpenMedia: onOpenMedia)
            }

            // 互动栏
            DynamicInteractionBar(
                post: post,
                onReply: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isReplying.toggle()
                    }
                    if isReplying { isReplyFocused = true }
                },
                onRepost: onRepost,
                onLike: onLike
            )

            // 评论列表
            DynamicCommentList(
                comments: comments,
                totalCount: post.replyCount,
                dynamicId: post.id,
                onReply: { content, replyToId in onReplyComment(content, replyToId) },
                onExpand: onExpandComments
            )

            // 内联回复区域
            if isReplying {
                replyInputArea
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(TelegramTheme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        .onAppear(perform: onAppear)
    }

    // MARK: - 内联回复输入区

    private var replyInputArea: some View {
        HStack(spacing: 10) {
            // 当前用户头像
            currentUserAvatar
                .frame(width: 32, height: 32)

            TextField("说点什么...", text: $replyText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(TelegramTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TelegramTheme.panelBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isReplyFocused ? TelegramTheme.success.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
                .focused($isReplyFocused)
                .lineLimit(1...4)
                .onSubmit { submitReply() }

            // 发送按钮
            Button(action: submitReply) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? TelegramTheme.success.opacity(0.4)
                                  : TelegramTheme.success)
                    )
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("发送回复")
        }
        .padding(.top, 4)
    }

    private var currentUserAvatar: some View {
        Group {
            if let avatarData = SocketManager.shared.myAvatar,
               let image = DynamicAvatarView.image(from: avatarData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(TelegramTheme.success.gradient)
                    Text("我")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .clipShape(Circle())
    }

    private func submitReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmitReply(trimmed)
        replyText = ""
        isReplying = false
        isReplyFocused = false
    }
}

// MARK: - 头像

struct DynamicAvatarView: View {
    let author: DynamicAuthor
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.image(from: author.avatar) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(TelegramTheme.success.gradient)
                    Text(String((DynamicText.nonBlank(author.nickname) ?? DynamicText.nonBlank(author.username) ?? "动").prefix(1)))
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    static func image(from rawValue: String?) -> NSImage? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else { return nil }
        let payload: String
        if let separator = rawValue.range(of: "base64,", options: .caseInsensitive) {
            payload = String(rawValue[separator.upperBound...])
        } else {
            payload = rawValue
        }
        guard let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]) else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - 媒体网格（统一九宫格）

struct DynamicMediaGrid: View {
    let media: [DynamicMedia]
    let onOpen: (DynamicMedia) -> Void

    private var items: [DynamicMedia] { Array(media.prefix(9)) }

    var body: some View {
        let count = items.count
        switch count {
        case 0:
            EmptyView()
        case 1:
            // 单图：按原始比例显示
            DynamicSingleMediaView(media: items[0], onOpen: { onOpen(items[0]) })
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case 2:
            // 2图：2列等大
            HStack(spacing: 4) {
                DynamicMediaCell(media: items[0], onOpen: { onOpen(items[0]) })
                    .frame(maxWidth: .infinity)
                DynamicMediaCell(media: items[1], onOpen: { onOpen(items[1]) })
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case 3:
            // 3图：3列等大
            HStack(spacing: 4) {
                ForEach(items) { item in
                    DynamicMediaCell(media: item, onOpen: { onOpen(item) })
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case 4:
            // 4图：2x2等大
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    DynamicMediaCell(media: items[0], onOpen: { onOpen(items[0]) })
                        .frame(maxWidth: .infinity)
                    DynamicMediaCell(media: items[1], onOpen: { onOpen(items[1]) })
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 4) {
                    DynamicMediaCell(media: items[2], onOpen: { onOpen(items[2]) })
                        .frame(maxWidth: .infinity)
                    DynamicMediaCell(media: items[3], onOpen: { onOpen(items[3]) })
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 324) // 160*2 + 4
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        default:
            // 5-9图：3列等大
            let rows = (count + 2) / 3
            VStack(spacing: 4) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { col in
                            let idx = row * 3 + col
                            if idx < count {
                                DynamicMediaCell(media: items[idx], onOpen: { onOpen(items[idx]) })
                                    .frame(maxWidth: .infinity)
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(height: 120)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - 媒体格子

struct DynamicMediaCell: View {
    let media: DynamicMedia
    let onOpen: () -> Void
    @State private var thumbnail: NSImage?
    @State private var isLoading = false
    /// 缩略图的实际宽高比（宽/高），用于单图时按比例显示
    @State private var aspectRatio: CGFloat?

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                // 背景填充（图片按比例显示后留白区域）
                Color.black

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    placeholderBackground
                }

                if media.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.5), in: Circle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { loadThumbnail() }
    }

    /// 单图时使用：根据缩略图实际尺寸计算显示大小
    func aspectRatioContent() -> some View {
        DynamicSingleMediaView(media: media, onOpen: onOpen)
    }

    private var placeholderBackground: some View {
        let color: Color = media.kind == .video ? Color.orange : Color.blue
        return ZStack {
            LinearGradient(
                colors: [color.opacity(0.2), color.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: media.kind == .video ? "film" : "photo")
                    .font(.system(size: 22, weight: .semibold))
                Text(media.fileName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .foregroundColor(color.opacity(0.6))
        }
    }

    private func loadThumbnail() {
        guard media.kind != .file else { return }
        guard !isLoading else { return }
        isLoading = true
        let item = DirectoryItem(
            id: media.fileId, pId: 0, fileName: media.fileName,
            childFileList: nil, hasChild: false, fileSize: media.fileSize,
            isFile: true, uploadTime: nil, directoryName: nil,
            filePath: "", fileType: media.mimeType
        )
        Task {
            // 优先用预览图（更高清），失败则降级到缩略图
            var img = await FileThumbnailService.shared.previewImage(for: item)
            if img == nil {
                img = await FileThumbnailService.shared.thumbnail(for: item)
            }
            await MainActor.run {
                self.thumbnail = img
                self.isLoading = false
                // 计算缩略图的宽高比，用于单图时按比例显示
                if let size = img?.size, size.height > 0 {
                    self.aspectRatio = size.width / size.height
                }
            }
        }
    }
}

// MARK: - 单图/单视频视图（按原始比例显示）

struct DynamicSingleMediaView: View {
    let media: DynamicMedia
    let onOpen: () -> Void
    @State private var thumbnail: NSImage?
    @State private var isLoading = false

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholderBackground
                }
                if media.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.black.opacity(0.6), in: Circle())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { loadThumbnail() }
    }

    private var placeholderBackground: some View {
        let color: Color = media.kind == .video ? Color.orange : Color.blue
        return ZStack {
            LinearGradient(
                colors: [color.opacity(0.2), color.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: media.kind == .video ? "film" : "photo")
                    .font(.system(size: 22, weight: .semibold))
                Text(media.fileName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .foregroundColor(color.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadThumbnail() {
        guard media.kind != .file else { return }
        guard !isLoading else { return }
        isLoading = true
        let item = DirectoryItem(
            id: media.fileId, pId: 0, fileName: media.fileName,
            childFileList: nil, hasChild: false, fileSize: media.fileSize,
            isFile: true, uploadTime: nil, directoryName: nil,
            filePath: "", fileType: media.mimeType
        )
        Task {
            var img = await FileThumbnailService.shared.previewImage(for: item)
            if img == nil {
                img = await FileThumbnailService.shared.thumbnail(for: item)
            }
            await MainActor.run {
                self.thumbnail = img
                self.isLoading = false
            }
        }
    }
}

// MARK: - 引用卡片

struct DynamicReferenceCard: View {
    let reference: DynamicReference

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(reference.sourceType == .chatMessage ? "来自聊天" : "来自网盘",
                  systemImage: reference.sourceType == .chatMessage ? "bubble.left.and.text.bubble.right" : "externaldrive.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TelegramTheme.success)
            Text(reference.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TelegramTheme.textPrimary)
                .lineLimit(1)
            if !reference.subtitle.isEmpty {
                Text(reference.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(TelegramTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TelegramTheme.textSecondary.opacity(0.15), lineWidth: 0.7)
        )
    }
}

// MARK: - 转发嵌入卡片

struct DynamicEmbeddedPostCard: View {
    let post: DynamicPost
    let onOpenMedia: (DynamicMedia) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                DynamicAvatarView(author: post.author, size: 22)
                Text(DynamicText.nonBlank(post.author.nickname) ?? DynamicText.nonBlank(post.author.username) ?? "用户")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TelegramTheme.textPrimary)
                Text("@\(DynamicText.nonBlank(post.author.username) ?? "user")")
                    .font(.system(size: 11))
                    .foregroundColor(TelegramTheme.textSecondary)
            }
            if !post.content.isEmpty {
                Text(post.content)
                    .font(.system(size: 13))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !post.media.isEmpty {
                DynamicMediaGrid(media: post.media, onOpen: onOpenMedia)
                    .frame(height: 100)
            }
        }
        .padding(10)
        .background(TelegramTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TelegramTheme.textSecondary.opacity(0.15), lineWidth: 0.7)
        )
    }
}

// MARK: - 互动栏

struct DynamicInteractionBar: View {
    let post: DynamicPost
    let onReply: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            interactionButton(
                title: "回复",
                count: post.replyCount,
                symbol: "bubble.left",
                color: TelegramTheme.accent,
                action: onReply
            )
            interactionButton(
                title: post.reposted ? "已转发" : "转发",
                count: post.repostCount,
                symbol: "arrow.2.squarepath",
                color: post.reposted ? TelegramTheme.success : TelegramTheme.textSecondary,
                action: onRepost
            )
            interactionButton(
                title: post.liked ? "已赞" : "点赞",
                count: post.likeCount,
                symbol: post.liked ? "heart.fill" : "heart",
                color: post.liked ? Color.red : TelegramTheme.textSecondary,
                action: onLike
            )
        }
        .font(.system(size: 13))
        .padding(.top, 4)
    }

    private func interactionButton(
        title: String,
        count: Int,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                } else {
                    Text(title)
                        .font(.system(size: 12))
                }
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 评论列表

struct DynamicCommentList: View {
    let comments: [DynamicPost]
    let totalCount: Int
    let dynamicId: Int64
    let onReply: (String, Int64) -> Void
    let onExpand: (Bool) -> Void
    @State private var expanded = false

    /// 过滤后只显示属于当前动态的评论
    private var validComments: [DynamicPost] {
        comments.filter { comment in
            // 如果评论有 dynamicId，必须与当前动态 ID 匹配
            if let cid = comment.dynamicId, cid > 0 {
                return cid == dynamicId
            }
            // 没有 dynamicId 的评论（旧数据）暂时保留，避免丢失
            return true
        }
    }

    /// 判断是否是回复型评论
    private func isReplyComment(_ comment: DynamicPost) -> Bool {
        // 优先通过内容前缀判断，服务端返回的回复型评论都包含 "回复 @用户名：" 前缀
        comment.content.hasPrefix("回复 @") || comment.originalPost?.value != nil || (comment.replyToCommentID != nil && comment.replyToCommentID! > 0)
    }

    /// 判断回复型评论是否是回复目标评论
    /// 注意：只支持两级评论，target 必须是顶级评论
    private func isReplyTo(_ reply: DynamicPost, target: DynamicPost) -> Bool {
        // target 必须是顶级评论（不是回复型评论）
        guard !isReplyComment(target) else { return false }
        // 如果有 replyToCommentID，只使用 ID 精确匹配，不降级到内容匹配
        // 避免同名用户时内容匹配错误关联到其他评论
        if let replyToID = reply.replyToCommentID, replyToID > 0 {
            return replyToID == target.id
        }
        // 使用 originalPost 匹配
        if let original = reply.originalPost?.value, original.id == target.id {
            return true
        }
        // 降级：通过内容中的 @用户名 判断（仅当没有 replyToCommentID 时）
        let targetName = DynamicText.nonBlank(target.author.nickname) ?? DynamicText.nonBlank(target.author.username) ?? ""
        return !targetName.isEmpty && reply.content.contains("@\(targetName)")
    }

    /// 顶级评论（按时间倒序，最新的在前面）
    private var topLevelComments: [DynamicPost] {
        validComments.filter { !isReplyComment($0) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// 获取某条顶级评论的所有回复（按时间正序）
    private func replies(for topComment: DynamicPost, usedIds: inout Set<Int64>) -> [DynamicPost] {
        validComments.filter { comment in
            guard isReplyComment(comment), !usedIds.contains(comment.id) else { return false }
            return isReplyTo(comment, target: topComment)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// 排序后的评论：顶级评论按时间倒序，回复跟在被回复评论后面
    private var sortedComments: [DynamicPost] {
        var result: [DynamicPost] = []
        var usedReplyIds = Set<Int64>()
        for top in topLevelComments {
            result.append(top)
            let replies = replies(for: top, usedIds: &usedReplyIds)
            for reply in replies {
                result.append(reply)
                usedReplyIds.insert(reply.id)
            }
        }
        // 未匹配到目标的回复型评论，追加到末尾
        let unmatched = validComments.filter { isReplyComment($0) && !usedReplyIds.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        result.append(contentsOf: unmatched)
        return result
    }

    /// 默认可见的评论：前5条顶级评论及其回复
    private var visibleComments: [DynamicPost] {
        if expanded {
            return sortedComments
        }
        // 只取前5条顶级评论，但包含它们的回复
        let visibleTop = Array(topLevelComments.prefix(5))
        var result: [DynamicPost] = []
        var usedReplyIds = Set<Int64>()
        for top in visibleTop {
            result.append(top)
            let replies = replies(for: top, usedIds: &usedReplyIds)
            for reply in replies {
                result.append(reply)
                usedReplyIds.insert(reply.id)
            }
        }
        return result
    }

    var body: some View {
        if !validComments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleComments) { comment in
                        DynamicCommentRow(
                            comment: comment,
                            onReply: { content, replyToId in onReply(content, replyToId) }
                        )
                    }
                }

                if topLevelComments.count > 5 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expanded.toggle()
                        }
                        onExpand(expanded)
                    }) {
                        Text(expanded ? "收起评论" : "查看全部 \(totalCount) 条评论")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TelegramTheme.success)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - 单条评论

struct DynamicCommentRow: View {
    let comment: DynamicPost
    let onReply: (String, Int64) -> Void
    @State private var isReplying = false
    @State private var replyText = ""
    @FocusState private var isFocused: Bool

    /// 从评论内容或 originalPost 中提取回复目标用户名
    private var replyTargetName: String? {
        if let original = comment.originalPost?.value {
            return DynamicText.nonBlank(original.author.nickname) ?? DynamicText.nonBlank(original.author.username)
        }
        // 从内容中提取 "回复 @用户名：" 或 "回复 @用户名:" 前缀
        let content = comment.content
        guard content.hasPrefix("回复 @") else { return nil }
        // 同时支持全角冒号和半角冒号
        let colonRange = content.range(of: "：") ?? content.range(of: ":")
        guard let colon = colonRange else { return nil }
        // "回复 @" 是4个字符：回、复、空格、@
        let namePart = content[content.index(content.startIndex, offsetBy: 4)..<colon.lowerBound]
        let name = String(namePart).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private var isReply: Bool { replyTargetName != nil }

    /// 去掉 "回复 @用户名：" 前缀后的实际内容
    private var displayContent: String {
        guard let name = replyTargetName else { return comment.content }
        // 同时支持全角冒号和半角冒号
        let fullPrefix = "回复 @\(name)："
        let halfPrefix = "回复 @\(name):"
        if comment.content.hasPrefix(fullPrefix) {
            return String(comment.content.dropFirst(fullPrefix.count))
        }
        if comment.content.hasPrefix(halfPrefix) {
            return String(comment.content.dropFirst(halfPrefix.count))
        }
        return comment.content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicAvatarView(author: comment.author, size: isReply ? 28 : 32)

            VStack(alignment: .leading, spacing: 4) {
                // 头部：用户名 + 回复目标 + 时间 + 回复按钮
                HStack(spacing: 6) {
                    Text(DynamicText.nonBlank(comment.author.nickname) ?? DynamicText.nonBlank(comment.author.username) ?? "用户")
                        .font(.system(size: isReply ? 12 : 13, weight: .semibold))
                        .foregroundColor(TelegramTheme.textPrimary)

                    if let targetName = replyTargetName {
                        Text("回复")
                            .font(.system(size: 11))
                            .foregroundColor(TelegramTheme.textSecondary)
                        Text("@\(targetName)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TelegramTheme.accent)
                    }

                    Spacer(minLength: 8)

                    Text(DynamicDateText.relative(comment.createdAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TelegramTheme.textSecondary)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isReplying.toggle()
                        }
                        if isReplying { isFocused = true }
                    }) {
                        Text("回复")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TelegramTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                // 评论内容（去掉回复前缀）
                Text(displayContent)
                    .font(.system(size: isReply ? 12 : 13))
                    .foregroundColor(TelegramTheme.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                // 内联回复输入框
                if isReplying {
                    replyInputArea
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 4)
                }
            }
        }
        .padding(.leading, isReply ? 42 : 0)
        .padding(.vertical, isReply ? 2 : 0)
    }

    private var replyInputArea: some View {
        HStack(spacing: 8) {
            TextField("回复...", text: $replyText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(TelegramTheme.panelBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isFocused ? TelegramTheme.success.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit { submit() }

            Button(action: submit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? TelegramTheme.success.opacity(0.4)
                                  : TelegramTheme.success)
                    )
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submit() {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 回复评论时，内容前缀添加回复关系
        let content: String
        if let original = comment.originalPost?.value {
            let targetName = DynamicText.nonBlank(original.author.nickname) ?? DynamicText.nonBlank(original.author.username) ?? ""
            content = "回复 @\(targetName)：\(trimmed)"
        } else {
            let targetName = DynamicText.nonBlank(comment.author.nickname) ?? DynamicText.nonBlank(comment.author.username) ?? ""
            content = "回复 @\(targetName)：\(trimmed)"
        }
        onReply(content, comment.id)
        replyText = ""
        isReplying = false
        isFocused = false
    }
}
