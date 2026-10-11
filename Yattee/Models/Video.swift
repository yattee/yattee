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

    /// Whether this is a YouTube Short: `nil` when the source can't tell.
    let isShort: Bool?

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
        relatedVideos: [Video]? = nil,
        isShort: Bool? = nil
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
        self.isShort = isShort
    }

    // MARK: - Standing in for metadata

    /// A video that is nothing but its own ID, for a list that knows a video was
    /// watched before it knows anything else about it.
    ///
    /// An account's server-side history is a list of IDs; the rows have to be
    /// on screen while their metadata is still being fetched, and one whose
    /// fetch fails is still part of that history.
    static func metadataPlaceholder(for videoID: String) -> Video {
        Video(
            id: .global(videoID),
            title: videoID,
            description: nil,
            author: Author(id: "", name: ""),
            duration: 0,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    /// The same standing-in video under wording that says the metadata could
    /// not be fetched, for a row whose fetch has definitively failed.
    ///
    /// Only what is shown changes: the video handed to the player and the queue
    /// keeps its ID, which is the part that plays.
    static func metadataUnavailable(for videoID: String, title: String) -> Video {
        Video(
            id: .global(videoID),
            title: title,
            description: nil,
            author: Author(id: "", name: ""),
            duration: 0,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    /// Whether a "Hide Shorts" filter should drop this video: only when the
    /// source said it is a Short, never when it couldn't tell.
    var isKnownShort: Bool {
        isShort == true
    }

    /// Whether the title is only the video's own ID standing in for one.
    ///
    /// Anything showing this video beside details it fetched itself should
    /// prefer the fetched title: a bare ID is not a name anybody chose, and the
    /// screen would otherwise keep it under a real description and thumbnail.
    var hasPlaceholderTitle: Bool {
        title == id.videoID
    }

    // MARK: - Computed Properties

    var bestThumbnail: Thumbnail? {
        thumbnails.sorted { $0.quality > $1.quality }.first
    }

    /// Thumbnail URLs ordered best-quality-first.
    ///
    /// Used as a fallback chain: backends (and YouTube's CDN) often advertise
    /// `maxres`/`sddefault` variants that don't actually exist for a given video
    /// and 404. Consumers try these in order and drop to the next when one fails.
    var thumbnailURLsByQuality: [URL] {
        thumbnails.sorted { $0.quality > $1.quality }.map(\.url)
    }

    /// Best thumbnail URL rewritten to the always-available `hqdefault` variant.
    ///
    /// For consumers that render or fetch a single URL with no way to fall back
    /// through the quality chain (Now Playing artwork, Top Shelf, remote control,
    /// navigation covers): the best advertised variant is often `maxresdefault`,
    /// which 404s for many older videos.
    var reliableThumbnailURL: URL? {
        Thumbnail.reliableURL(for: bestThumbnail?.url)
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
    ///
    /// A date that would render as "in 0 seconds" is shown as nothing at all:
    /// it is what an instance sends in place of an upload date it does not
    /// have, and the metadata line is better one segment short than wrong.
    var formattedPublishedDate: String? {
        if let publishedAt {
            guard !RelativeDateFormatter.isEffectivelyNow(publishedAt) else { return nil }
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

    /// Expands a single stored YouTube-style thumbnail URL (`/vi/<id>/<variant>.jpg`)
    /// into a best-first fallback chain. Persistence models (playlists, watch history,
    /// bookmarks) store only the best advertised URL — usually `maxresdefault.jpg`,
    /// which doesn't exist for many older videos and 404s. Reconstructing the
    /// lower-quality variants lets thumbnail views fall back the same way they do
    /// for live API results. Non-matching URLs get a single-entry chain.
    /// Rewrites a YouTube-style thumbnail URL (`/vi/<id>/<variant>.jpg`) to the
    /// `hqdefault.jpg` variant, which exists for effectively every video (unlike
    /// `maxresdefault`/`sddefault`, which 404 for many older uploads). Use where a
    /// single URL is displayed without fallback, e.g. playlist covers. Non-matching
    /// URLs are returned unchanged.
    static func reliableURL(for url: URL?) -> URL? {
        guard let url else { return nil }
        let variants = ["maxresdefault.jpg", "sddefault.jpg", "hqdefault.jpg", "mqdefault.jpg", "default.jpg"]
        let path = url.path
        guard path.range(of: #"/vi/[^/]+/"#, options: .regularExpression) != nil,
              let match = variants.first(where: { path.hasSuffix($0) }),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path = String(path.dropLast(match.count)) + "hqdefault.jpg"
        return components.url ?? url
    }

    static func fallbackChain(for url: URL?) -> [Thumbnail] {
        guard let url else { return [] }
        let variants: [(suffix: String, quality: Quality)] = [
            ("maxresdefault.jpg", .maxres),
            ("sddefault.jpg", .standard),
            ("hqdefault.jpg", .high),
            ("mqdefault.jpg", .medium),
            ("default.jpg", .default),
        ]
        let path = url.path
        guard path.range(of: #"/vi/[^/]+/"#, options: .regularExpression) != nil,
              let current = variants.first(where: { path.hasSuffix($0.suffix) }),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [Thumbnail(url: url, quality: .medium)]
        }
        let basePath = String(path.dropLast(current.suffix.count))
        return variants.compactMap { variant in
            guard variant.quality <= current.quality else { return nil }
            var variantComponents = components
            variantComponents.path = basePath + variant.suffix
            guard let variantURL = variantComponents.url else { return nil }
            return Thumbnail(url: variantURL, quality: variant.quality)
        }
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
    /// Compares what the video *is*, not only which video it is.
    ///
    /// Being the same video is not the same as being the same *description* of
    /// it. One ID can arrive first as a placeholder standing in for metadata
    /// nobody has fetched yet and again as the real thing, and SwiftUI decides
    /// whether a view needs redrawing by comparing the values it was given — so
    /// equality by ID alone leaves a list showing the placeholder it was handed
    /// first, however many times it is given the answer.
    ///
    /// The ID is compared first, which is what nearly every comparison differs
    /// in and settles it in one step.
    static func == (lhs: Video, rhs: Video) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.author == rhs.author
            && lhs.duration == rhs.duration
            && lhs.viewCount == rhs.viewCount
            && lhs.likeCount == rhs.likeCount
            && lhs.publishedAt == rhs.publishedAt
            && lhs.publishedText == rhs.publishedText
            && lhs.isLive == rhs.isLive
            && lhs.isUpcoming == rhs.isUpcoming
            && lhs.scheduledStartTime == rhs.scheduledStartTime
            && lhs.thumbnails == rhs.thumbnails
            && lhs.description == rhs.description
            && lhs.relatedVideos == rhs.relatedVideos
            && lhs.isShort == rhs.isShort
    }
}

extension Video: Hashable {
    /// Hashed by ID alone, which stays coarser than equality on purpose: it is
    /// what every lookup is by, and hashing equal for values that turn out to
    /// differ is exactly what a hash is allowed to do.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
