//
//  DynamicDetailView.swift
//  chat-storage
//
//  动态详情页：原帖 + 回复列表 + 回复输入
//

import SwiftUI

struct DynamicDetailView: View {
    @StateObject private var viewModel: DynamicDetailViewModel
    let repository: any DynamicRepository
    let onBack: () -> Void
    let onOpenMedia: (DynamicMedia, [DynamicMedia], DynamicAuthor) -> Void

    @State private var replyText = ""
    @FocusState private var isReplyFocused: Bool

    init(
        post: DynamicPost,
        repository: any DynamicRepository,
        onBack: @escaping () -> Void,
        onOpenMedia: @escaping (DynamicMedia, [DynamicMedia], DynamicAuthor) -> Void
    ) {
        self.repository = repository
        self.onBack = onBack
        self.onOpenMedia = onOpenMedia
        _viewModel = StateObject(wrappedValue: DynamicDetailViewModel(
            post: post,
            repository: repository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 导航栏
            navigationBar

            ScrollView {
                LazyVStack(spacing: 0) {
                    // 原帖
                    detailPostCard
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    // 回复标题
                    HStack {
                        Text("全部回复")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TelegramTheme.textPrimary)
                        Text("\(viewModel.post.replyCount)")
                            .font(.system(size: 13))
                            .foregroundColor(TelegramTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                    // 回复列表
                    if viewModel.isLoading && viewModel.replies.isEmpty {
                        ProgressView()
                            .padding(30)
                    } else if viewModel.replies.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 32))
                                .foregroundColor(TelegramTheme.textSecondary.opacity(0.4))
                            Text("还没有回复，来抢沙发吧")
                                .font(.system(size: 13))
                                .foregroundColor(TelegramTheme.textSecondary)
                        }
                        .padding(30)
                    } else {
                        ForEach(viewModel.replies) { reply in
                            replyRow(reply)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                        }

                        if viewModel.hasMore {
                            ProgressView()
                                .padding(20)
                                .onAppear { viewModel.loadNextPage() }
                        }
                    }
                }
                .padding(.bottom, 20)
            }

            // 回复输入栏
            replyInputBar
        }
        .background(TelegramTheme.appBackground)
        .onAppear { viewModel.loadInitial() }
    }

    // MARK: - 导航栏

    private var navigationBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 14))
                }
                .foregroundColor(TelegramTheme.success)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("动态详情")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TelegramTheme.textPrimary)

            Spacer()

            Color.clear.frame(width: 60)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(TelegramTheme.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TelegramTheme.textSecondary.opacity(0.1))
                .frame(height: 0.5)
        }
    }

    // MARK: - 原帖详情

    private var detailPostCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 作者信息
            HStack(alignment: .top, spacing: 10) {
                DynamicAvatarView(author: viewModel.post.author, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DynamicText.nonBlank(viewModel.post.author.nickname) ?? DynamicText.nonBlank(viewModel.post.author.username) ?? "用户")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TelegramTheme.textPrimary)
                    Text("@\(DynamicText.nonBlank(viewModel.post.author.username) ?? "user") · \(DynamicDateText.relative(viewModel.post.createdAt))")
                        .font(.system(size: 12))
                        .foregroundColor(TelegramTheme.textSecondary)
                }
                Spacer()
            }

            // 正文
            if !viewModel.post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(viewModel.post.content)
                    .font(.system(size: 15))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 媒体
            if !viewModel.post.media.isEmpty {
                DynamicMediaGrid(
                    media: viewModel.post.media,
                    onOpen: { media in onOpenMedia(media, viewModel.post.media, viewModel.post.author) }
                )
            }

            // 引用
            if let reference = viewModel.post.reference {
                DynamicReferenceCard(reference: reference)
            }

            // 转发嵌入
            if let original = viewModel.post.originalPost?.value {
                DynamicEmbeddedPostCard(
                    post: original,
                    onOpenMedia: { media in onOpenMedia(media, original.media, original.author) }
                )
            }

            // 互动栏
            DynamicInteractionBar(
                post: viewModel.post,
                onReply: { isReplyFocused = true },
                onRepost: { /* 详情页转发暂不实现 */ },
                onLike: { viewModel.toggleLike() }
            )
        }
        .padding(16)
        .background(TelegramTheme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 回复行

    private func replyRow(_ reply: DynamicPost) -> some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicAvatarView(author: reply.author, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(DynamicText.nonBlank(reply.author.nickname) ?? DynamicText.nonBlank(reply.author.username) ?? "用户")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TelegramTheme.textPrimary)
                    Text(DynamicDateText.relative(reply.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(TelegramTheme.textSecondary)
                }

                if !reply.content.isEmpty {
                    Text(reply.content)
                        .font(.system(size: 13))
                        .foregroundColor(TelegramTheme.textPrimary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !reply.media.isEmpty {
                    DynamicMediaGrid(
                        media: reply.media,
                        onOpen: { media in onOpenMedia(media, reply.media, reply.author) }
                    )
                    .frame(height: 80)
                }

                // 回复的互动
                HStack(spacing: 16) {
                    Button(action: { /* 回复的回复暂不实现 */ }) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left")
                            if reply.replyCount > 0 { Text("\(reply.replyCount)") }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(TelegramTheme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { /* 回复点赞暂不实现 */ }) {
                        HStack(spacing: 4) {
                            Image(systemName: reply.liked ? "heart.fill" : "heart")
                            if reply.likeCount > 0 { Text("\(reply.likeCount)") }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(reply.liked ? .red : TelegramTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(10)
        .background(TelegramTheme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 回复输入栏

    private var replyInputBar: some View {
        HStack(spacing: 10) {
            TextField("写下你的回复...", text: $replyText, axis: .vertical)
                .font(.system(size: 14))
                .foregroundColor(TelegramTheme.textPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(TelegramTheme.panelBackground)
                .clipShape(Capsule())
                .focused($isReplyFocused)
                .onSubmit { sendReply() }

            Button(action: sendReply) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? TelegramTheme.textSecondary.opacity(0.4) : TelegramTheme.success)
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TelegramTheme.panelBackground)
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.reply(content: text)
        replyText = ""
        isReplyFocused = false
    }
}
