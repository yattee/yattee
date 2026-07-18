//
//  Comment.swift
//  Yattee
//
//  Represents a video comment.
//

@preconcurrency import Foundation

/// Represents a comment on a video.
struct Comment: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this comment.
    let id: String

    /// The comment author.
    let author: Author

    /// The comment text content.
    let content: String

    /// When the comment was posted.
    let publishedAt: Date?

    /// Human-readable published date.
    let publishedText: String?

    /// Like count if available.
    let likeCount: Int?

    /// Whether this comment is pinned.
    let isPinned: Bool

    /// Whether the author is the video creator.
    let isCreatorComment: Bool

    /// Whether the channel owner hearted this comment.
    let hasCreatorHeart: Bool

    /// Number of replies.
    let replyCount: Int

    /// Continuation token for loading replies.
    let repliesContinuation: String?

    // MARK: - Initialization

    init(
        id: String,
        author: Author,
        content: String,
        publishedAt: Date? = nil,
        publishedText: String? = nil,
        likeCount: Int? = nil,
        isPinned: Bool = false,
        isCreatorComment: Bool = false,
        hasCreatorHeart: Bool = false,
        replyCount: Int = 0,
        repliesContinuation: String? = nil
    ) {
        self.id = id
        self.author = author
        self.content = content
        self.publishedAt = publishedAt
        self.publishedText = publishedText
        self.likeCount = likeCount
        self.isPinned = isPinned
        self.isCreatorComment = isCreatorComment
        self.hasCreatorHeart = hasCreatorHeart
        self.replyCount = replyCount
        self.repliesContinuation = repliesContinuation
    }

    var formattedLikeCount: String? {
        guard let likeCount, likeCount > 0 else { return nil }
        return CountFormatter.compact(likeCount)
    }

    /// Formatted published date, preferring parsed Date over API-provided text.
    var formattedPublishedDate: String? {
        if let publishedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: publishedAt, relativeTo: Date())
        }
        return publishedText
    }
}

/// Represents a page of comments with continuation token for pagination.
struct CommentsPage: Sendable {
    /// The comments on this page.
    let comments: [Comment]

    /// Continuation token for loading more comments. Nil if no more pages.
    let continuation: String?

    /// Whether there are more comments to load.
    var hasMore: Bool { continuation != nil }
}
