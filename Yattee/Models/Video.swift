//
//  Video.swift
//  Yattee
//
//  Core video model representing a video from any source.
//

@preconcurrency import Foundation

/// Represents a video from any content source.
struct Video: Identifiable, Codable, Sendable {
    /// Unique identifier combining source and video ID.
    let id: VideoID

    /// The video title.
    let title: String

    /// The video description (may be truncated in list views).
    let description: String?

    /// The channel/author information.
    let author: Author

    /// Duration in seconds.
    let duration: TimeInterval

    /// When the video was published.
    let publishedAt: Date?

    /// Human-readable published date from the API.
    let publishedText: String?

    /// View count if available.
    let viewCount: Int?

    /// Like count if available.
    let likeCount: Int?

    /// Available thumbnails.
    let thumbnails: [Thumbnail]

    /// Whether this is a live stream.
    let isLive: Bool

    /// Whether this is an upcoming premiere/stream.
    let isUpcoming: Bool

    /// Scheduled start time for upcoming content.
    let scheduledStartTime: Date?

    /// Related/recommended videos (populated from video details API).
    let relatedVideos: [Video]?

    // MARK: - Explicit Initializer

    init(
        id: VideoID,
        title: String,
        description: String?,
        author: Author,
        duration: TimeInterval,
        publishedAt: Date?,
        publishedText: String?,
        viewCount: Int?,
        likeCount: Int?,
        thumbnails: [Thumbnail],
        isLive: Bool,
        isUpcoming: Bool,
        scheduledStartTime: Date?,
        relatedVideos: [Video]? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.author = author
        self.duration = duration
        self.publishedAt = publishedAt
        self.publishedText = publishedText
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.thumbnails = thumbnails
        self.isLive = isLive
        self.isUpcoming = isUpcoming
        self.scheduledStartTime = scheduledStartTime
        self.relatedVideos = relatedVideos
    }

    // MARK: - Computed Properties

    var bestThumbnail: Thumbnail? {
        thumbnails.sorted { $0.quality > $1.quality }.first
    }

    var formattedDuration: String {
        guard !isLive else { return "LIVE" }
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

    /// URL for sharing this video.
    var shareURL: URL {
        switch id.source {
        case .global(let provider):
            if provider == ContentSource.youtubeProvider {
                return URL(string: "https://www.youtube.com/watch?v=\(id.videoID)")!
            }
            // Future: handle other global providers
            return URL(string: "https://www.youtube.com/watch?v=\(id.videoID)")!
        case .federated(let provider, let instance):
            if provider == ContentSource.peertubeProvider {
                return URL(string: "\(instance.absoluteString)/w/\(id.videoID)")!
            }
            // Future: handle other federated providers
            return instance.appendingPathComponent("videos/\(id.videoID)")
        case .extracted(_, let originalURL):
            return originalURL
        }
    }

    /// The ContentSource for the author's channel.
    /// For federated content, the author may be on a different instance than the video.
    var authorSource: ContentSource {
        switch id.source {
        case .global:
            return id.source
        case .federated(let provider, let videoInstance):
            // For PeerTube, the author might be on a different federated instance
            if let authorInstance = author.instance, authorInstance.host != videoInstance.host {
                return .federated(provider: provider, instance: authorInstance)
            }
            return id.source
        case .extracted:
            return id.source
        }
    }

    /// Whether this video supports comments via the API.
    /// Currently only YouTube videos support comments through Invidious.
    var supportsComments: Bool {
        if case .global(let provider) = id.source {
            return provider == ContentSource.youtubeProvider
        }
        return false
    }

    /// Whether this video supports detailed statistics (views, likes, date) via API.
    /// Extracted videos (yt-dlp sources) don't have API stats available.
    var supportsAPIStats: Bool {
        switch id.source {
        case .global, .federated:
            return true
        case .extracted:
            return false
        }
    }

}

// MARK: - Video ID

/// Unique identifier for a video, combining source and video ID.
struct VideoID: Codable, Hashable, Sendable {
    /// The content source.
    let source: ContentSource

    /// The video ID within that source.
    let videoID: String

    /// For PeerTube, videos can be identified by UUID as well.
    let uuid: String?

    init(source: ContentSource, videoID: String, uuid: String? = nil) {
        self.source = source
        self.videoID = videoID
        self.uuid = uuid
    }

    /// Creates a global video ID (e.g., YouTube).
    static func global(_ videoID: String, provider: String = ContentSource.youtubeProvider) -> VideoID {
        VideoID(source: .global(provider: provider), videoID: videoID)
    }

    /// Creates a federated video ID (e.g., PeerTube).
    static func federated(_ videoID: String, provider: String = ContentSource.peertubeProvider, instance: URL, uuid: String? = nil) -> VideoID {
        VideoID(source: .federated(provider: provider, instance: instance), videoID: videoID, uuid: uuid)
    }

    /// Creates an extracted video ID for sites supported by yt-dlp.
    static func extracted(_ videoID: String, extractor: String, originalURL: URL) -> VideoID {
        VideoID(source: .extracted(extractor: extractor, originalURL: originalURL), videoID: videoID)
    }
}

extension VideoID: Identifiable {
    var id: String {
        switch source {
        case .global(let provider):
            return "global:\(provider):\(videoID)"
        case .federated(let provider, let instance):
            return "federated:\(provider):\(instance.host ?? ""):\(videoID)"
        case .extracted(let extractor, _):
            return "extracted:\(extractor):\(videoID)"
        }
    }

    /// Whether this video is from an SMB media source.
    var isSMBSource: Bool {
        if case .extracted(let extractor, _) = source {
            return extractor == MediaFile.smbProvider
        }
        return false
    }
}

// MARK: - Author

/// Represents a video author/channel.
struct Author: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let thumbnailURL: URL?
    let subscriberCount: Int?

    /// For PeerTube, the instance where this author is hosted.
    let instance: URL?

    /// For external sources, the channel/author URL for navigation.
    let url: URL?

    /// Whether real channel info was returned from the server (vs fallback to extractor name).
    let hasRealChannelInfo: Bool

    init(id: String, name: String, thumbnailURL: URL? = nil, subscriberCount: Int? = nil, instance: URL? = nil, url: URL? = nil, hasRealChannelInfo: Bool = true) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.subscriberCount = subscriberCount
        self.instance = instance
        self.url = url
        self.hasRealChannelInfo = hasRealChannelInfo
    }

    var formattedSubscriberCount: String? {
        guard let subscriberCount else { return nil }
        return CountFormatter.compact(subscriberCount) + " " + String(localized: "channel.subscribers")
    }
}

// MARK: - Thumbnail

/// Represents a video thumbnail.
struct Thumbnail: Codable, Hashable, Sendable {
    let url: URL
    let quality: Quality
    let width: Int?
    let height: Int?

    enum Quality: String, Codable, Comparable, Sendable {
        case `default`
        case medium
        case high
        case standard
        case maxres

        static func < (lhs: Quality, rhs: Quality) -> Bool {
            let order: [Quality] = [.default, .medium, .high, .standard, .maxres]
            guard let lIndex = order.firstIndex(of: lhs),
                  let rIndex = order.firstIndex(of: rhs) else {
                return false
            }
            return lIndex < rIndex
        }
    }

    init(url: URL, quality: Quality = .default, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.quality = quality
        self.width = width
        self.height = height
    }
}

// MARK: - Preview Support

extension Video {
    /// A sample video for SwiftUI previews.
    static var preview: Video {
        Video(
            id: .global("dQw4w9WgXcQ"),
            title: "Sample Video Title",
            description: "This is a sample video description for preview purposes.",
            author: Author(id: "UC123", name: "Sample Channel"),
            duration: 212,
            publishedAt: Date().addingTimeInterval(-86400 * 3),
            publishedText: "3 days ago",
            viewCount: 1_234_567,
            likeCount: 50_000,
            thumbnails: [
                Thumbnail(
                    url: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg")!,
                    quality: .maxres,
                    width: 1280,
                    height: 720
                )
            ],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    /// A sample live video for SwiftUI previews.
    static var livePreview: Video {
        Video(
            id: .global("live123"),
            title: "Live Stream Example",
            description: "This is a live stream.",
            author: Author(id: "UC456", name: "Live Channel"),
            duration: 0,
            publishedAt: Date(),
            publishedText: "Started streaming",
            viewCount: 5_432,
            likeCount: nil,
            thumbnails: [
                Thumbnail(
                    url: URL(string: "https://i.ytimg.com/vi/live123/maxresdefault.jpg")!,
                    quality: .maxres
                )
            ],
            isLive: true,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

// MARK: - Equatable & Hashable

extension Video: Equatable {
    /// Custom Equatable implementation that only compares by ID for performance.
    /// Two videos with the same ID are considered equal during SwiftUI diffing.
    /// This avoids expensive comparisons of all properties (including nested Author and [Thumbnail]).
    static func == (lhs: Video, rhs: Video) -> Bool {
        lhs.id == rhs.id
    }
}

extension Video: Hashable {
    /// Custom Hashable implementation consistent with Equatable.
    /// Only hashes the ID since equality is determined by ID alone.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
