//
//  Playlist.swift
//  Yattee
//
//  Represents a video playlist.
//

@preconcurrency import Foundation

/// Represents a playlist from any content source.
struct Playlist: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this playlist.
    let id: PlaylistID

    /// The playlist title.
    let title: String

    /// Playlist description.
    let description: String?

    /// The channel/author who created the playlist.
    let author: Author?

    /// Number of videos in the playlist.
    let videoCount: Int

    /// Thumbnail URL (usually from first video).
    let thumbnailURL: URL?

    /// Videos in this playlist (may be partial for large playlists).
    let videos: [Video]

    /// Whether this is a local/Yattee playlist vs instance playlist.
    let isLocal: Bool

    // MARK: - Computed Properties

    /// The author name as a string for display.
    var authorName: String {
        author?.name ?? ""
    }

    // MARK: - Initialization

    init(
        id: PlaylistID,
        title: String,
        description: String? = nil,
        author: Author? = nil,
        videoCount: Int = 0,
        thumbnailURL: URL? = nil,
        videos: [Video] = [],
        isLocal: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.author = author
        self.videoCount = videoCount
        self.thumbnailURL = thumbnailURL
        self.videos = videos
        self.isLocal = isLocal
    }
}

// MARK: - Playlist ID

/// Unique identifier for a playlist.
struct PlaylistID: Codable, Hashable, Sendable {
    /// The content source (nil for local playlists).
    let source: ContentSource?

    /// The playlist ID.
    let playlistID: String

    init(source: ContentSource?, playlistID: String) {
        self.source = source
        self.playlistID = playlistID
    }

    /// Creates a global playlist ID (e.g., YouTube).
    static func global(_ playlistID: String, provider: String = ContentSource.youtubeProvider) -> PlaylistID {
        PlaylistID(source: .global(provider: provider), playlistID: playlistID)
    }

    /// Creates a federated playlist ID (e.g., PeerTube).
    static func federated(_ playlistID: String, provider: String = ContentSource.peertubeProvider, instance: URL) -> PlaylistID {
        PlaylistID(source: .federated(provider: provider, instance: instance), playlistID: playlistID)
    }

    /// Creates a local Yattee playlist ID.
    static func local(_ playlistID: String) -> PlaylistID {
        PlaylistID(source: nil, playlistID: playlistID)
    }

    var isLocal: Bool {
        source == nil
    }
}

extension PlaylistID: Identifiable {
    var id: String {
        guard let source else {
            return "local:\(playlistID)"
        }
        switch source {
        case .global(let provider):
            return "global:\(provider):\(playlistID)"
        case .federated(let provider, let instance):
            return "federated:\(provider):\(instance.host ?? ""):\(playlistID)"
        case .extracted(let extractor, _):
            return "extracted:\(extractor):\(playlistID)"
        }
    }
}
