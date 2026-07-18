//
//  QueueSource.swift
//  Yattee
//
//  Tracks the origin of queued videos for continuation loading.
//

import Foundation

/// Tracks the origin of queued videos for continuation loading.
enum QueueSource: Codable, Equatable, Hashable, Sendable {
    /// Videos from a channel's video list.
    case channel(channelID: String, source: ContentSource, continuation: String?)

    /// Videos from a playlist.
    case playlist(playlistID: String, continuation: String?)

    /// Videos from search results.
    case search(query: String, continuation: String?)

    /// Videos from subscriptions feed.
    case subscriptions(continuation: String?)

    /// Manually added individual videos (no continuation).
    case manual

    /// Videos from a media browser folder (WebDAV/SMB/local folder).
    /// Folder contents are loaded upfront, so no continuation is needed.
    case mediaBrowser(sourceID: UUID, folderPath: String)

    /// Whether this source supports loading more items.
    var supportsContinuation: Bool {
        switch self {
        case .channel(_, _, let continuation),
             .playlist(_, let continuation),
             .search(_, let continuation),
             .subscriptions(let continuation):
            return continuation != nil
        case .manual, .mediaBrowser:
            return false
        }
    }

    /// The continuation token, if available.
    var continuation: String? {
        switch self {
        case .channel(_, _, let continuation),
             .playlist(_, let continuation),
             .search(_, let continuation),
             .subscriptions(let continuation):
            return continuation
        case .manual, .mediaBrowser:
            return nil
        }
    }

    /// Returns a new QueueSource with an updated continuation token.
    func withContinuation(_ newContinuation: String?) -> QueueSource {
        switch self {
        case .channel(let channelID, let source, _):
            return .channel(channelID: channelID, source: source, continuation: newContinuation)
        case .playlist(let playlistID, _):
            return .playlist(playlistID: playlistID, continuation: newContinuation)
        case .search(let query, _):
            return .search(query: query, continuation: newContinuation)
        case .subscriptions:
            return .subscriptions(continuation: newContinuation)
        case .manual:
            return .manual
        case .mediaBrowser:
            return self // No continuation for media browser
        }
    }

    /// The content source for this queue source, used for instance selection.
    /// Returns nil for sources that don't use API-based continuation (manual, mediaBrowser).
    var contentSource: ContentSource? {
        switch self {
        case .channel(_, let source, _):
            return source
        case .playlist, .search, .subscriptions:
            // Playlists, search, and subscriptions are YouTube content
            return .global(provider: ContentSource.youtubeProvider)
        case .manual, .mediaBrowser:
            return nil
        }
    }
}
