//
//  DynamicModels.swift
//  chat-storage
//
//  动态功能数据模型（移植自 iOS 端，适配 macOS）
//

import Foundation

// MARK: - 媒体类型

enum DynamicMediaKind: String, Codable, Equatable, Sendable {
    case image
    case video
    case file
}

struct DynamicMedia: Codable, Equatable, Identifiable, Sendable {
    let kind: DynamicMediaKind
    let fileId: Int64
    let fileName: String
    let fileSize: Int64
    let mimeType: String

    var id: Int64 { fileId }

    init(kind: DynamicMediaKind, fileId: Int64, fileName: String, fileSize: Int64, mimeType: String) {
        self.kind = kind
        self.fileId = fileId
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DynamicCodingKey.self)
        kind = try values.first(DynamicMediaKind.self, ["kind"]) ?? .file
        fileId = try values.firstLossyInt64(["fileId", "id"]) ?? 0
        fileName = try values.first(String.self, ["fileName", "name"]) ?? ""
        fileSize = try values.firstLossyInt64(["fileSize", "size"]) ?? 0
        mimeType = try values.first(String.self, ["mimeType", "contentType"]) ?? "application/octet-stream"
    }
}

// MARK: - 引用来源

enum DynamicReferenceSourceType: String, Codable, Equatable, Sendable {
    case chatMessage
    case driveFile
}

struct DynamicReference: Codable, Equatable, Sendable {
    let sourceType: DynamicReferenceSourceType
    let sourceId: String
    let title: String
    let subtitle: String
    let media: [DynamicMedia]
}

// MARK: - 作者

struct DynamicAuthor: Codable, Equatable, Sendable {
    let id: Int64
    let username: String
    let nickname: String
    let avatar: String?

    init(id: Int64, username: String, nickname: String, avatar: String?) {
        self.id = id
        self.username = username
        self.nickname = nickname
        self.avatar = avatar
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try values.firstLossyInt64(["id", "userId"]) ?? 0
        username = try values.first(String.self, ["username", "userName"]) ?? ""
        nickname = try values.first(String.self, ["nickname", "nickName"]) ?? username
        avatar = try values.first(String.self, ["avatar", "avatarUrl"])
    }
}

// MARK: - 动态帖子

struct DynamicPost: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let author: DynamicAuthor
    let content: String
    let media: [DynamicMedia]
    let reference: DynamicReference?
    let likeCount: Int
    let replyCount: Int
    let repostCount: Int
    let liked: Bool
    let reposted: Bool
    let originalPost: IndirectDynamicPost?
    let replyToCommentID: Int64?
    let dynamicId: Int64?
    let createdAt: Int64
    let isMine: Bool
    /// 该动态的评论列表（时间线接口返回，包含5条顶级评论+所有回复）
    let replies: [IndirectDynamicPost]

    init(
        id: Int64,
        author: DynamicAuthor,
        content: String,
        media: [DynamicMedia],
        reference: DynamicReference?,
        likeCount: Int,
        replyCount: Int,
        repostCount: Int,
        liked: Bool,
        reposted: Bool,
        originalPost: DynamicPost?,
        replyToCommentID: Int64? = nil,
        dynamicId: Int64? = nil,
        createdAt: Int64,
        isMine: Bool,
        replies: [DynamicPost] = []
    ) {
        self.id = id
        self.author = author
        self.content = content
        self.media = media
        self.reference = reference
        self.likeCount = likeCount
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.liked = liked
        self.reposted = reposted
        self.originalPost = originalPost.map(IndirectDynamicPost.init)
        self.replyToCommentID = replyToCommentID
        self.dynamicId = dynamicId
        self.createdAt = createdAt
        self.isMine = isMine
        self.replies = replies.map(IndirectDynamicPost.init)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DynamicCodingKey.self)
        // id 优先从 id 字段解码，向后兼容 dynamicId（旧版本动态卡片可能用 dynamicId 作为主键）
        id = try values.firstLossyInt64(["id"]) ?? values.firstLossyInt64(["dynamicId"]) ?? 0
        if let nestedAuthor = try values.first(DynamicAuthor.self, ["author"]) {
            author = nestedAuthor
        } else {
            author = DynamicAuthor(
                id: try values.firstLossyInt64(["userId", "authorId"]) ?? 0,
                username: try values.first(String.self, ["username", "userName"]) ?? "",
                nickname: try values.first(String.self, ["nickname", "nickName"]) ?? "",
                avatar: try values.first(String.self, ["avatar", "avatarUrl"])
            )
        }
        content = try values.first(String.self, ["content", "text"]) ?? ""
        media = try values.first([DynamicMedia].self, ["media", "images", "attachments"]) ?? []
        reference = try values.first(DynamicReference.self, ["reference"])
        likeCount = try values.firstLossyInt(["likeCount", "likes"]) ?? 0
        replyCount = try values.firstLossyInt(["replyCount", "replies"]) ?? 0
        repostCount = try values.firstLossyInt(["repostCount", "reposts"]) ?? 0
        liked = try values.firstLossyBool(["liked", "isLiked"]) ?? false
        reposted = try values.firstLossyBool(["reposted", "isReposted"]) ?? false
        originalPost = try values.first(IndirectDynamicPost.self, ["originalPost", "repost"])
        replyToCommentID = try values.firstLossyInt64(["replyToCommentId", "replyToCommentID", "parentId", "parentID", "replyToId", "replyToID"])
        // dynamicId 只用于评论，表示评论所属的动态 ID
        dynamicId = try values.firstLossyInt64(["dynamicId", "dynamic_id"])
        createdAt = try values.firstLossyInt64(["createdAt", "gmtCreated", "createTime", "time", "timestamp", "date", "created_at", "create_time"]) ?? 0
        isMine = try values.firstLossyBool(["isMine", "mine"]) ?? false
        replies = try values.decodeIfPresent([IndirectDynamicPost].self, forKey: DynamicCodingKey("replies")) ?? []
    }
}

/// 转发动态用引用盒打断值类型递归
final class IndirectDynamicPost: Codable, Equatable, @unchecked Sendable {
    let value: DynamicPost

    init(_ value: DynamicPost) {
        self.value = value
    }

    static func == (left: IndirectDynamicPost, right: IndirectDynamicPost) -> Bool {
        left.value == right.value
    }

    required init(from decoder: Decoder) throws {
        value = try DynamicPost(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

// MARK: - 时间线范围

enum DynamicTimelineScope: String, Codable, Equatable, Sendable {
    case following = "FOLLOWING"
    case mine = "MINE"
    case liked = "LIKED"
    case bookmarked = "BOOKMARKED"
}

// MARK: - 创建动态

struct DynamicCreateRequest: Codable, Equatable, Sendable {
    let content: String
    let media: [DynamicMedia]
    let reference: DynamicReference?

    init(content: String, media: [DynamicMedia] = [], reference: DynamicReference? = nil) {
        self.content = content
        self.media = media
        self.reference = reference
    }
}

struct DynamicCreateResult: Codable, Equatable, Sendable {
    let dynamicId: Int64
    let post: DynamicPost?

    init(dynamicId: Int64, post: DynamicPost?) {
        self.dynamicId = dynamicId
        self.post = post
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DynamicCodingKey.self)
        dynamicId = try values.firstLossyInt64(["dynamicId", "id"]) ?? 0
        post = try values.first(DynamicPost.self, ["post", "dynamic"])
    }
}

// MARK: - 时间线分页

struct DynamicTimelinePage: Codable, Equatable, Sendable {
    let posts: [DynamicPost]
    let nextBeforeId: Int64?
    let hasMore: Bool

    init(posts: [DynamicPost], nextBeforeId: Int64?, hasMore: Bool) {
        self.posts = posts
        self.nextBeforeId = nextBeforeId
        self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DynamicCodingKey.self)
        posts = try values.first([DynamicPost].self, ["posts", "records", "items"]) ?? []
        nextBeforeId = try values.firstLossyInt64(["nextBeforeId", "nextCursor", "beforeId"])
        hasMore = try values.firstLossyBool(["hasMore"]) ?? (nextBeforeId != nil)
    }
}

// MARK: - 动态动作

enum DynamicAction: Equatable, Sendable {
    case like
    case unlike
    case reply(content: String, parentId: Int64? = nil)
    case repost
    case unrepost

    var wireValue: String {
        switch self {
        case .like: return "LIKE"
        case .unlike: return "UNLIKE"
        case .reply: return "REPLY"
        case .repost: return "REPOST"
        case .unrepost: return "UNREPOST"
        }
    }

    var content: String? {
        guard case .reply(let content, _) = self else { return nil }
        return content
    }

    var parentId: Int64? {
        guard case .reply(_, let parentId) = self else { return nil }
        return parentId
    }

    init?(wireValue: String, content: String? = nil) {
        switch wireValue.uppercased() {
        case "LIKE": self = .like
        case "UNLIKE": self = .unlike
        case "REPLY": self = .reply(content: content ?? "", parentId: nil)
        case "REPOST": self = .repost
        case "UNREPOST": self = .unrepost
        default: return nil
        }
    }
}

struct DynamicActionResult: Equatable, Sendable {
    let dynamicId: Int64
    let action: DynamicAction
    let likeCount: Int
    let replyCount: Int
    let repostCount: Int
    let liked: Bool
    let reposted: Bool
}

extension DynamicActionResult: Decodable {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DynamicCodingKey.self)
        dynamicId = try values.firstLossyInt64(["dynamicId", "id"]) ?? 0
        let actionValue = try values.first(String.self, ["action"]) ?? ""
        action = DynamicAction(wireValue: actionValue, content: try values.first(String.self, ["content"])) ?? .like
        likeCount = try values.firstLossyInt(["likeCount", "likes"]) ?? 0
        replyCount = try values.firstLossyInt(["replyCount", "replies"]) ?? 0
        repostCount = try values.firstLossyInt(["repostCount", "reposts"]) ?? 0
        liked = try values.firstLossyBool(["liked", "isLiked"]) ?? false
        reposted = try values.firstLossyBool(["reposted", "isReposted"]) ?? false
    }
}

// MARK: - 动态详情

struct DynamicPostDetail: Codable, Equatable, Sendable {
    let post: DynamicPost
    let replies: [DynamicPost]
    let nextBeforeReplyId: Int64?
    let hasMore: Bool

    init(
        post: DynamicPost,
        replies: [DynamicPost],
        nextBeforeReplyId: Int64? = nil,
        hasMore: Bool = false
    ) {
        self.post = post
        self.replies = replies
        self.nextBeforeReplyId = nextBeforeReplyId
        self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let post = try values.first(DynamicPost.self, ["post", "dynamic"]) else {
            throw DecodingError.keyNotFound(
                DynamicCodingKey("post"),
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing dynamic post")
            )
        }
        self.post = post
        replies = try values.first([DynamicPost].self, ["replies", "records", "items"]) ?? []
        nextBeforeReplyId = try values.firstLossyInt64(["nextBeforeReplyId", "nextCursor"])
        hasMore = try values.firstLossyBool(["hasMore"]) ?? (nextBeforeReplyId != nil)
    }
}

// MARK: - 拷贝工具

enum DynamicPostCopying {
    static func updating(
        _ post: DynamicPost,
        likeCount: Int? = nil,
        replyCount: Int? = nil,
        repostCount: Int? = nil,
        liked: Bool? = nil,
        reposted: Bool? = nil,
        replyToCommentID: Int64? = nil,
        dynamicId: Int64? = nil,
        replies: [DynamicPost]? = nil
    ) -> DynamicPost {
        DynamicPost(
            id: post.id,
            author: post.author,
            content: post.content,
            media: post.media,
            reference: post.reference,
            likeCount: likeCount ?? post.likeCount,
            replyCount: replyCount ?? post.replyCount,
            repostCount: repostCount ?? post.repostCount,
            liked: liked ?? post.liked,
            reposted: reposted ?? post.reposted,
            originalPost: post.originalPost?.value,
            replyToCommentID: replyToCommentID ?? post.replyToCommentID,
            dynamicId: dynamicId ?? post.dynamicId,
            createdAt: post.createdAt,
            isMine: post.isMine,
            replies: replies ?? post.replies.map { $0.value }
        )
    }
}

// MARK: - 展示辅助

enum DynamicText {
    static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum DynamicDateText {
    static func relative(_ timestamp: Int64) -> String {
        guard timestamp > 0 else { return "刚刚" }
        let secondsValue = timestamp > 10_000_000_000 ? Double(timestamp) / 1_000 : Double(timestamp)
        let date = Date(timeIntervalSince1970: secondsValue)
        let elapsed = max(0, Date().timeIntervalSince(date))
        switch elapsed {
        case ..<60: return "刚刚"
        case ..<3_600: return "\(Int(elapsed / 60))分钟前"
        case ..<86_400: return "\(Int(elapsed / 3_600))小时前"
        case ..<(7 * 86_400): return "\(Int(elapsed / 86_400))天前"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: date)
        }
    }
}

// MARK: - 容错解码键

private struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func first<T: Decodable>(_ type: T.Type, _ names: [String]) throws -> T? {
        for name in names {
            let key = DynamicCodingKey(name)
            if contains(key), let value = try decodeIfPresent(type, forKey: key) { return value }
        }
        return nil
    }

    func firstLossyInt64(_ names: [String]) throws -> Int64? {
        for name in names {
            let key = DynamicCodingKey(name)
            guard contains(key) else { continue }
            if let value = try? decodeIfPresent(Int64.self, forKey: key) { return value }
            if let value = try? decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
            if let value = try? decodeIfPresent(String.self, forKey: key), let parsed = Int64(value) { return parsed }
        }
        return nil
    }

    func firstLossyInt(_ names: [String]) throws -> Int? {
        guard let value = try firstLossyInt64(names) else { return nil }
        return Int(exactly: value)
    }

    func firstLossyBool(_ names: [String]) throws -> Bool? {
        for name in names {
            let key = DynamicCodingKey(name)
            guard contains(key) else { continue }
            if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
            if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "1": return true
                case "false", "no", "0": return false
                default: continue
                }
            }
        }
        return nil
    }
}
