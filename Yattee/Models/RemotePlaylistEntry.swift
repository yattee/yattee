//
//  RemotePlaylistEntry.swift
//  Yattee
//
//  Per-entry identity for playlists that live on an instance, so a later
//  mutation can name exactly which row it removes.
//

import Foundation

/// Identifies one row of a server-side playlist.
///
/// The playlist ID is part of every case on purpose: entry identifiers are
/// compared and stored across playlists (caches, selections, pending
/// mutations), and position 3 of one playlist must never collide with
/// position 3 of another.
///
/// The two backends offer very different guarantees, and the case you get
/// tells you which one you are holding:
///
/// - ``invidious(playlistID:indexID:)`` wraps the server's `indexId` token,
///   which names the same row across refetches even as videos above it are
///   removed.
/// - ``piped(playlistID:position:)`` is **snapshot-scoped only**. Piped
///   removes by position, so an id minted from one fetch is meaningless once
///   the playlist changes. This is safe because the caching layer refetches
///   the whole playlist after every mutation — never persist these, and never
///   compare one against an id from an earlier snapshot.
enum RemotePlaylistEntryID: Hashable, Sendable {
    /// Stable across snapshots — Invidious hands out a per-entry `indexId`.
    case invidious(playlistID: String, indexID: String)

    /// Snapshot-scoped only — Piped addresses entries by their position.
    case piped(playlistID: String, position: Int)
}

/// One video in a server-side playlist, paired with the identity needed to
/// remove it.
///
/// Two entries holding the same video are still distinct values: ``Video``
/// hashes by id alone, but ``id`` carries the per-entry token, so a playlist
/// containing the same video twice yields two entries that never collapse.
struct RemotePlaylistEntry: Identifiable, Hashable, Sendable {
    /// The backend-specific handle for this row.
    let id: RemotePlaylistEntryID

    /// The video shown for this row.
    let video: Video

    /// Zero-based position within the playlist as the snapshot saw it.
    let position: Int

    init(id: RemotePlaylistEntryID, video: Video, position: Int) {
        self.id = id
        self.video = video
        self.position = position
    }
}

/// A playlist as fetched at one moment, together with its addressable entries.
///
/// `entries` may be shorter than `playlist.videos`: a video the server did not
/// hand an identity to is still displayed, it just cannot be a mutation target.
struct RemotePlaylistSnapshot: Hashable, Sendable {
    /// The playlist for display.
    let playlist: Playlist

    /// The rows that can be addressed for removal, in playlist order.
    let entries: [RemotePlaylistEntry]

    init(playlist: Playlist, entries: [RemotePlaylistEntry]) {
        self.playlist = playlist
        self.entries = entries
    }
}
