//
//  LocalPlaylist.swift
//  Yattee
//
//  SwiftData model for user-created local playlists.
//

import Foundation
import SwiftData

/// Represents a user-created local playlist.
@Model
final class LocalPlaylist {
    /// Unique identifier for the playlist.
    var id: UUID = UUID()

    /// The playlist title.
    var title: String = ""

    /// Optional description.
    var playlistDescription: String?

    /// When the playlist was created.
    var createdAt: Date = Date()

    /// When the playlist was last modified.
    var updatedAt: Date = Date()

    /// Whether this playlist is a placeholder awaiting sync.
    /// Placeholder playlists are created when playlist items arrive before their parent playlist.
    var isPlaceholder: Bool = false

    /// The videos in this playlist (ordered). Optional for CloudKit compatibility.
    @Relationship(deleteRule: .cascade, inverse: \LocalPlaylistItem.playlist)
    var items: [LocalPlaylistItem]? = []

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.playlistDescription = description
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = []
    }

    // MARK: - Computed Properties

    /// Number of videos in the playlist.
    var videoCount: Int {
        (items ?? []).count
    }

    /// Total duration of all videos.
    var totalDuration: TimeInterval {
        (items ?? []).reduce(0) { $0 + $1.duration }
    }

    /// Formatted total duration.
    var formattedTotalDuration: String {
        let total = Int(totalDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }

    /// The first video's thumbnail URL for display.
    var thumbnailURL: URL? {
        (items ?? []).sorted { $0.sortOrder < $1.sortOrder }
            .first?
            .thumbnailURL
    }

    /// Sorted items by order.
    var sortedItems: [LocalPlaylistItem] {
        (items ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Methods

    /// Adds a video to the playlist.
    func addVideo(_ video: Video) {
        let maxOrder = (items ?? []).map(\.sortOrder).max() ?? -1
        let item = LocalPlaylistItem.from(video: video, sortOrder: maxOrder + 1)
        item.playlist = self
        if items == nil {
            items = []
        }
        items?.append(item)
        updatedAt = Date()
    }

    /// Removes a video from the playlist.
    func removeVideo(at index: Int) {
        guard index < sortedItems.count else { return }
        let item = sortedItems[index]
        items?.removeAll { $0.id == item.id }
        updatedAt = Date()
    }

    /// Checks if a video is already in the playlist.
    func contains(videoID: String) -> Bool {
        (items ?? []).contains { $0.videoID == videoID }
    }
}

/// Represents a video item within a local playlist.
@Model
final class LocalPlaylistItem {
    /// Unique identifier.
    var id: UUID = UUID()

    /// The parent playlist.
    var playlist: LocalPlaylist?

    /// Sort order within the playlist.
    var sortOrder: Int = 0

    // MARK: - Video Identity

    /// The video ID string.
    var videoID: String = ""

    /// The content source raw value ("global", "federated", "extracted").
    var sourceRawValue: String = "global"

    /// For global sources: the provider name (e.g., "youtube", "dailymotion").
    var globalProvider: String?

    /// For PeerTube: the instance URL string.
    var instanceURLString: String?

    /// For PeerTube: the UUID.
    var peertubeUUID: String?

    /// For external sources: the extractor name (e.g., "vimeo", "twitter").
    var externalExtractor: String?

    /// For external sources: the original URL string.
    var externalURLString: String?

    // MARK: - Video Metadata

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

    /// When this item was added.
    var addedAt: Date = Date()

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        sortOrder: Int,
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
        isLive: Bool = false
    ) {
        self.id = id
        self.sortOrder = sortOrder
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
        self.addedAt = Date()
    }

    // MARK: - Computed Properties

    /// The thumbnail URL if available.
    var thumbnailURL: URL? {
        thumbnailURLString.flatMap { URL(string: $0) }
    }

    /// The content source for this item.
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
}

// MARK: - Conversion Methods

extension LocalPlaylistItem {
    /// Converts this LocalPlaylistItem back to a Video model for playback or display.
    func toVideo() -> Video {
        Video(
            id: VideoID(source: contentSource, videoID: videoID),
            title: title,
            description: nil,
            author: Author(id: authorID, name: authorName),
            duration: duration,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: thumbnailURL.map { [Thumbnail(url: $0, quality: .medium)] } ?? [],
            isLive: isLive,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    /// Creates a LocalPlaylistItem from a Video model.
    static func from(video: Video, sortOrder: Int) -> LocalPlaylistItem {
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

        return LocalPlaylistItem(
            sortOrder: sortOrder,
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
            isLive: video.isLive
        )
    }
}
