//
//  DynamicTimelineViewModel.swift
//  chat-storage
//
//  动态时间线 ViewModel
//

import Foundation
import Combine

final class DynamicTimelineViewModel: ObservableObject {
    @Published private(set) var posts: [DynamicPost] = []
    @Published private(set) var nextBeforeId: Int64?
    @Published private(set) var hasMore = true
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?
    @Published private(set) var comments: [Int64: [DynamicPost]] = [:]
    @Published private(set) var loadingComments: Set<Int64> = []

    private(set) var scope: DynamicTimelineScope
    private let repository: any DynamicRepository
    private let pageSize: Int

    init(repository: any DynamicRepository, scope: DynamicTimelineScope, pageSize: Int = 5) {
        self.repository = repository
        self.scope = scope
        self.pageSize = pageSize
    }

    func loadInitial() {
        guard posts.isEmpty else { return }
        load(replacing: true, beforeId: nil)
    }

    func refresh() {
        load(replacing: true, beforeId: nil)
    }

    func loadNextPage() {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        load(replacing: false, beforeId: nextBeforeId)
    }

    func toggleLike(postID: Int64) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let original = posts[index]
        let action: DynamicAction = original.liked ? .unlike : .like
        posts[index] = DynamicPostCopying.updating(original,
            likeCount: max(0, original.likeCount + (original.liked ? -1 : 1)),
            liked: !original.liked
        )
        errorMessage = nil
        Task {
            do {
                let result = try await repository.action(dynamicId: postID, action: action)
                await MainActor.run { apply(result) }
            } catch {
                await MainActor.run {
                    if let currentIndex = self.posts.firstIndex(where: { $0.id == postID }) {
                        self.posts[currentIndex] = original
                    }
                    self.errorMessage = Self.message(for: error)
                }
            }
        }
    }

    func toggleRepost(postID: Int64) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let original = posts[index]
        let action: DynamicAction = original.reposted ? .unrepost : .repost
        posts[index] = DynamicPostCopying.updating(original,
            repostCount: max(0, original.repostCount + (original.reposted ? -1 : 1)),
            reposted: !original.reposted
        )
        errorMessage = nil
        Task {
            do {
                let result = try await repository.action(dynamicId: postID, action: action)
                await MainActor.run { apply(result) }
            } catch {
                await MainActor.run {
                    if let currentIndex = self.posts.firstIndex(where: { $0.id == postID }) {
                        self.posts[currentIndex] = original
                    }
                    self.errorMessage = Self.message(for: error)
                }
            }
        }
    }

    func delete(postID: Int64) {
        guard let post = posts.first(where: { $0.id == postID }), post.isMine else { return }
        errorMessage = nil
        Task {
            do {
                try await repository.delete(dynamicId: postID)
                await MainActor.run {
                    self.posts.removeAll { $0.id == postID }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = Self.message(for: error)
                }
            }
        }
    }

    func reply(postID: Int64, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let original = posts[index]
        // 乐观更新：回复数 +1
        posts[index] = DynamicPostCopying.updating(original, replyCount: original.replyCount + 1)
        errorMessage = nil
        Task {
            do {
                let result = try await repository.action(dynamicId: postID, action: .reply(content: trimmed))
                await MainActor.run {
                    if let idx = self.posts.firstIndex(where: { $0.id == postID }) {
                        self.posts[idx] = DynamicPostCopying.updating(self.posts[idx],
                            likeCount: result.likeCount,
                            replyCount: result.replyCount,
                            repostCount: result.repostCount
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    // 回滚乐观更新
                    if let idx = self.posts.firstIndex(where: { $0.id == postID }) {
                        self.posts[idx] = DynamicPostCopying.updating(self.posts[idx],
                            replyCount: max(0, self.posts[idx].replyCount - 1)
                        )
                    }
                    self.errorMessage = Self.message(for: error)
                }
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - 评论

    func loadComments(postID: Int64, limit: Int = 5) {
        guard !loadingComments.contains(postID) else { return }
        // 如果评论已存在且是默认加载（limit=5），不再重复请求
        // 查看更多评论时 limit > 5，需要强制请求
        if limit <= 5, let existing = comments[postID], !existing.isEmpty {
            return
        }
        loadingComments.insert(postID)
        Task {
            do {
                let detail = try await repository.detail(dynamicId: postID, beforeReplyId: nil, limit: limit)
                await MainActor.run {
                    self.comments[postID] = detail.replies
                    self.loadingComments.remove(postID)
                }
            } catch {
                await MainActor.run {
                    self.comments[postID] = []
                    self.loadingComments.remove(postID)
                }
            }
        }
    }

    func replyToComment(postID: Int64, replyToCommentID: Int64, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let original = posts[index]
        // 乐观更新：回复数 +1
        posts[index] = DynamicPostCopying.updating(original, replyCount: original.replyCount + 1)

        let currentComments = comments[postID] ?? []

        // 找到被回复的评论
        guard let targetComment = currentComments.first(where: { $0.id == replyToCommentID }) else { return }

        // 确定顶级评论 ID：如果被回复的是回复型评论，找到它的父评论（顶级评论）
        // 只展示两级：顶级评论 + 回复，回复任何评论都归到顶级评论下面
        var topLevelCommentID: Int64 = replyToCommentID
        if let parentID = targetComment.replyToCommentID, parentID > 0 {
            // 被回复的是二级评论，找到它的顶级评论
            if let topLevel = currentComments.first(where: { $0.id == parentID }) {
                topLevelCommentID = topLevel.id
            }
        }

        // 被回复用户的名称（用于显示"回复 @用户名"）
        let targetName = DynamicText.nonBlank(targetComment.author.nickname) ?? DynamicText.nonBlank(targetComment.author.username) ?? "用户"
        var finalContent = trimmed
        if !trimmed.hasPrefix("回复 @") {
            finalContent = "回复 @\(targetName)：\(trimmed)"
        }

        // 乐观插入评论：parentId 指向顶级评论
        let tempComment = DynamicPost(
            id: Int64(Date().timeIntervalSince1970 * -1000),
            author: DynamicAuthor(id: 0, username: "我", nickname: "我", avatar: nil),
            content: finalContent,
            media: [],
            reference: nil,
            likeCount: 0,
            replyCount: 0,
            repostCount: 0,
            liked: false,
            reposted: false,
            originalPost: nil,
            replyToCommentID: topLevelCommentID,
            dynamicId: postID,
            createdAt: Int64(Date().timeIntervalSince1970),
            isMine: true
        )
        var updatedComments = currentComments
        // 插入到顶级评论下面
        if let topIndex = updatedComments.firstIndex(where: { $0.id == topLevelCommentID }) {
            updatedComments.insert(tempComment, at: topIndex + 1)
        } else {
            updatedComments.insert(tempComment, at: 0)
        }
        comments[postID] = updatedComments

        Task {
            do {
                // 提交时 parentId 指向顶级评论，确保只有两级
                let result = try await repository.action(dynamicId: postID, action: .reply(content: finalContent, parentId: topLevelCommentID))
                await MainActor.run {
                    if let idx = self.posts.firstIndex(where: { $0.id == postID }) {
                        self.posts[idx] = DynamicPostCopying.updating(self.posts[idx],
                            likeCount: result.likeCount,
                            replyCount: result.replyCount,
                            repostCount: result.repostCount
                        )
                    }
                    // 从服务器刷新最新评论列表
                    self.loadingComments.remove(postID)
                    self.loadComments(postID: postID)
                }
            } catch {
                await MainActor.run {
                    if let idx = self.posts.firstIndex(where: { $0.id == postID }) {
                        self.posts[idx] = DynamicPostCopying.updating(self.posts[idx],
                            replyCount: max(0, self.posts[idx].replyCount - 1)
                        )
                    }
                    // 移除乐观插入的评论
                    self.comments[postID]?.removeAll { $0.id < 0 }
                    self.errorMessage = Self.message(for: error)
                }
            }
        }
    }

    func switchScope(_ newScope: DynamicTimelineScope) {
        guard scope != newScope else { return }
        scope = newScope
        posts = []
        nextBeforeId = nil
        hasMore = true
        load(replacing: true, beforeId: nil)
    }

    // MARK: - Private

    private func load(replacing: Bool, beforeId: Int64?) {
        guard !isLoading else { return }
        isLoading = true
        if replacing { isLoadingMore = false } else { isLoadingMore = true }
        errorMessage = nil
        Task {
            do {
                let page = try await repository.timeline(scope: scope, beforeId: beforeId, limit: pageSize)
                await MainActor.run {
                    self.posts = replacing ? Self.unique(page.posts) : Self.merging(self.posts, page.posts)
                    self.nextBeforeId = page.nextBeforeId
                    self.hasMore = page.hasMore
                    // 直接使用时间线接口返回的评论数据，不再单独请求
                    for post in page.posts {
                        let postReplies = post.replies.map { $0.value }
                        if !postReplies.isEmpty {
                            self.comments[post.id] = postReplies
                        }
                        self.loadingComments.remove(post.id)
                    }
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = Self.message(for: error)
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            }
        }
    }

    private func apply(_ result: DynamicActionResult) {
        guard let index = posts.firstIndex(where: { $0.id == result.dynamicId }) else { return }
        posts[index] = DynamicPostCopying.updating(posts[index],
            likeCount: result.likeCount,
            replyCount: result.replyCount,
            repostCount: result.repostCount,
            liked: result.liked,
            reposted: result.reposted
        )
    }

    private static func unique(_ values: [DynamicPost]) -> [DynamicPost] {
        var identifiers = Set<Int64>()
        return values.filter { identifiers.insert($0.id).inserted }
    }

    private static func merging(_ existing: [DynamicPost], _ additional: [DynamicPost]) -> [DynamicPost] {
        var identifiers = Set(existing.map(\.id))
        return existing + additional.filter { identifiers.insert($0.id).inserted }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "动态操作失败"
    }
}

// MARK: - 动态详情 ViewModel

final class DynamicDetailViewModel: ObservableObject {
    @Published private(set) var post: DynamicPost
    @Published private(set) var replies: [DynamicPost] = []
    @Published private(set) var nextBeforeReplyId: Int64?
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repository: any DynamicRepository
    private let pageSize: Int

    init(post: DynamicPost, repository: any DynamicRepository, pageSize: Int = 5) {
        self.post = post
        self.repository = repository
        self.pageSize = pageSize
    }

    func loadInitial() {
        guard replies.isEmpty else { return }
        load(replacing: true, beforeReplyId: nil)
    }

    func refresh() {
        load(replacing: true, beforeReplyId: nil)
    }

    func loadNextPage() {
        guard hasMore, !isLoading else { return }
        load(replacing: false, beforeReplyId: nextBeforeReplyId)
    }

    func reply(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                _ = try await repository.action(dynamicId: post.id, action: .reply(content: trimmed))
                await MainActor.run { self.refresh() }
            } catch {
                await MainActor.run { self.errorMessage = Self.message(for: error) }
            }
        }
    }

    func toggleLike() {
        let original = post
        let action: DynamicAction = original.liked ? .unlike : .like
        post = DynamicPostCopying.updating(original,
            likeCount: max(0, original.likeCount + (original.liked ? -1 : 1)),
            liked: !original.liked
        )
        Task {
            do {
                let result = try await repository.action(dynamicId: post.id, action: action)
                await MainActor.run {
                    self.post = DynamicPostCopying.updating(self.post,
                        likeCount: result.likeCount,
                        replyCount: result.replyCount,
                        repostCount: result.repostCount,
                        liked: result.liked,
                        reposted: result.reposted
                    )
                }
            } catch {
                await MainActor.run { self.post = original }
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func load(replacing: Bool, beforeReplyId: Int64?) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let detail = try await repository.detail(dynamicId: post.id, beforeReplyId: beforeReplyId, limit: pageSize)
                await MainActor.run {
                    self.post = detail.post
                    self.replies = replacing ? Self.unique(detail.replies) : Self.merging(self.replies, detail.replies)
                    self.nextBeforeReplyId = detail.nextBeforeReplyId
                    self.hasMore = detail.hasMore
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = Self.message(for: error)
                    self.isLoading = false
                }
            }
        }
    }

    private static func unique(_ values: [DynamicPost]) -> [DynamicPost] {
        var identifiers = Set<Int64>()
        return values.filter { identifiers.insert($0.id).inserted }
    }

    private static func merging(_ existing: [DynamicPost], _ additional: [DynamicPost]) -> [DynamicPost] {
        var identifiers = Set(existing.map(\.id))
        return existing + additional.filter { identifiers.insert($0.id).inserted }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "加载失败"
    }
}
