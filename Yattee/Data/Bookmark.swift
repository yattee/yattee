//
//  Bookmark.swift
//  Yattee
//
//  SwiftData model for bookmarked/favorited videos.
//

import Foundation
import SwiftData

/// Represents a bookmarked video for later viewing.
@Model
final class Bookmark {
    // MARK: - Video Identity

    /// The video ID string (YouTube ID or PeerTube UUID).
    var videoID: String = ""

    /// The content source raw value for encoding ("global", "federated", "extracted").
    var sourceRawValue: String = "global"

    /// For global sources: the provider name (e.g., "youtube", "dailymotion").
    var globalProvider: String?

    /// For PeerTube: the instance URL string.
    var instanceURLString: String?

    /// For PeerTube: the UUID.
    var peertubeUUID: String?

    /// For external sources: the extractor name (e.g., "vimeo", "twitter").
    var externalExtractor: String?

    /// For external sources: the original URL for re-extraction.
    var externalURLString: String?

    // MARK: - Video Metadata (cached for offline display)

    /// The video title.
    var title: String = ""

    /// The channel/author name.
    var authorName: String = ""

    /// The channel/author ID.
    var authorID: String = ""

    /// Video duration in seconds.
    var duration: TimeInterval = 0

    /// Thumbnail URL string.
    var thumbnailURLString: String?

    /// Whether this is a live stream.
    var isLive: Bool = false

    /// View count if available.
    var viewCount: Int?

    /// When the video was published.
    var publishedAt: Date?

    /// Human-readable published date from the API.
    var publishedText: String?

    // MARK: - Bookmark Metadata

    /// When this bookmark was created.
    var createdAt: Date = Date()

    /// Optional user note/comment.
    var note: String?

    /// When the note was last modified.
    var noteModifiedAt: Date?

    /// User-defined tags for categorizing the bookmark.
    var tags: [String] = []

    /// When the tags were last modified.
    var tagsModifiedAt: Date?

    /// Sort order for manual ordering.
    var sortOrder: Int = 0

    // MARK: - Initialization

    init(
        videoID: String,
        sourceRawValue: String,
        globalProvider: String? = nil,
        instanceURLString: String? = nil,
        peertubeUUID: String? = nil,
        externalExtractor: String? = nil,
        externalURLString: String? = nil,
        title: String,
        authorName: String,
        authorID: String,
        duration: TimeInterval,
        thumbnailURLString: String? = nil,
        isLive: Bool = false,
        viewCount: Int? = nil,
        publishedAt: Date? = nil,
        publishedText: String? = nil,
        note: String? = nil,
        noteModifiedAt: Date? = nil,
        tags: [String] = [],
        tagsModifiedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.videoID = videoID
        self.sourceRawValue = sourceRawValue
        self.globalProvider = globalProvider
        self.instanceURLString = instanceURLString
        self.peertubeUUID = peertubeUUID
        self.externalExtractor = externalExtractor
        self.externalURLString = externalURLString
        self.title = title
        self.authorName = authorName
        self.authorID = authorID
        self.duration = duration
        self.thumbnailURLString = thumbnailURLString
        self.isLive = isLive
        self.viewCount = viewCount
        self.publishedAt = publishedAt
        self.publishedText = publishedText
        self.note = note
        self.noteModifiedAt = noteModifiedAt
        self.tags = tags
        self.tagsModifiedAt = tagsModifiedAt
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    // MARK: - Computed Properties

    /// The content source for this bookmark.
    var contentSource: ContentSource {
        if sourceRawValue == "global" {
            return .global(provider: globalProvider ?? ContentSource.youtubeProvider)
        } else if sourceRawValue == "federated",
                  let urlString = instanceURLString,
                  let url = URL(string: urlString) {
            return .federated(provider: ContentSource.peertubeProvider, instance: url)
        } else if sourceRawValue == "extracted",
                  let extractor = externalExtractor,
                  let urlString = externalURLString,
                  let url = URL(string: urlString) {
            return .extracted(extractor: extractor, originalURL: url)
        }
        return .global(provider: globalProvider ?? ContentSource.youtubeProvider)
    }

    /// The thumbnail URL if available.
    var thumbnailURL: URL? {
        thumbnailURLString.flatMap { URL(string: $0) }
    }

    /// Formatted duration string.
    var formattedDuration: String {
        guard !isLive else { return String(localized: "video.badge.live") }
        guard duration > 0 else { return "" }

        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Formatted view count string.
    var formattedViewCount: String? {
        guard let viewCount else { return nil }
        return CountFormatter.compact(viewCount)
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

    /// Converts this bookmark to a Video model for playback.
    func toVideo() -> Video {
        let videoIDObj: VideoID
        switch contentSource {
        case .global(let provider):
            videoIDObj = VideoID(source: .global(provider: provider), videoID: videoID)
        case .federated(let provider, let instance):
            videoIDObj = VideoID(source: .federated(provider: provider, instance: instance), videoID: videoID, uuid: peertubeUUID)
        case .extracted(let extractor, let originalURL):
            videoIDObj = VideoID(source: .extracted(extractor: extractor, originalURL: originalURL), videoID: videoID)
        }

        let author = Author(
            id: authorID,
            name: authorName,
            thumbnailURL: nil,
            subscriberCount: nil
        )

        return Video(
            id: videoIDObj,
            title: title,
            description: nil,
            author: author,
            duration: duration,
            publishedAt: publishedAt,
            publishedText: publishedText,
            viewCount: viewCount,
            likeCount: nil,
            thumbnails: thumbnailURL.map { [Thumbnail(url: $0, width: nil, height: nil)] } ?? [],
            isLive: isLive,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

// MARK: - Factory Methods

extension Bookmark {
    /// Creates a Bookmark from a Video model.
    static func from(video: Video, tags: [String] = [], tagsModifiedAt: Date? = nil, sortOrder: Int = 0) -> Bookmark {
        let sourceRaw: String
        var provider: String?
        var instanceURL: String?
        var uuid: String?
        var extractor: String?
        var externalURL: String?

        switch video.id.source {
        case .global(let prov):
            sourceRaw = "global"
            provider = prov
        case .federated(_, let instance):
            sourceRaw = "federated"
            instanceURL = instance.absoluteString
            uuid = video.id.uuid
        case .extracted(let ext, let originalURL):
            sourceRaw = "extracted"
            extractor = ext
            externalURL = originalURL.absoluteString
        }

        return Bookmark(
            videoID: video.id.videoID,
            sourceRawValue: sourceRaw,
            globalProvider: provider,
            instanceURLString: instanceURL,
            peertubeUUID: uuid,
            externalExtractor: extractor,
            externalURLString: externalURL,
            title: video.title,
            authorName: video.author.name,
            authorID: video.author.id,
            duration: video.duration,
            thumbnailURLString: video.bestThumbnail?.url.absoluteString,
            isLive: video.isLive,
            viewCount: video.viewCount,
            publishedAt: video.publishedAt,
            publishedText: video.publishedText,
            tags: tags,
            tagsModifiedAt: tagsModifiedAt,
            sortOrder: sortOrder
        )
    }
}

// MARK: - Preview Support

extension Bookmark {
    /// A sample bookmark for SwiftUI previews.
    static var preview: Bookmark {
        Bookmark(
            videoID: "dQw4w9WgXcQ",
            sourceRawValue: "global",
            globalProvider: "youtube",
            title: "Sample Video Title",
            authorName: "Sample Channel",
            authorID: "UC123",
            duration: 212,
            thumbnailURLString: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
            isLive: false,
            viewCount: 1_234_567,
            publishedAt: Date().addingTimeInterval(-86400 * 3),
            publishedText: "3 days ago",
            note: "Great video about SwiftUI patterns and best practices",
            tags: ["Swift", "iOS", "Tutorial", "SwiftUI", "Xcode"]
        )
    }
}
