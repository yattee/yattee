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
/// - ``piped(playlistID:position:)`` is **snapshot-scoped only**, and the
///   position is the server's own index over every row it sent — not the row
///   number the app draws. Piped
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

    /// Zero-based position within the playlist **as the server counts it** —
    /// over every row it sent, including the ones the app could not parse and
    /// does not display. This is the number a removal is addressed by, so it
    /// must never be renumbered over the filtered display list.
    let position: Int

    /// Index of this entry in ``RemotePlaylistSnapshot/playlist``'s `videos`.
    ///
    /// Separate from ``position`` on purpose: rows the app cannot display are
    /// dropped from `playlist.videos` but still occupy a server position, so the
    /// two numbers diverge the moment a playlist holds one. Carried explicitly
    /// rather than recovered by matching video ids, which cannot tell two rows
    /// of the same video apart.
    let displayRow: Int

    init(id: RemotePlaylistEntryID, video: Video, position: Int, displayRow: Int) {
        self.id = id
        self.video = video
        self.position = position
        self.displayRow = displayRow
    }
}

/// A playlist as fetched at one moment, together with its addressable entries.
///
/// `entries` may be shorter than `playlist.videos`: a video the server did not
/// hand an identity to is still displayed, it just cannot be a mutation target.
/// It can also be shorter than what the server sent: a row that failed to parse
/// is neither displayed nor addressable, but it still holds a server position,
/// which is why ``RemotePlaylistEntry/position`` and
/// ``RemotePlaylistEntry/displayRow`` are two different numbers.
struct RemotePlaylistSnapshot: Hashable, Sendable {
    /// The playlist for display.
    let playlist: Playlist

    /// The rows that can be addressed for removal, in playlist order.
    let entries: [RemotePlaylistEntry]

    /// Whether the server lists this playlist publicly, where it says so.
    ///
    /// Deliberately not a ``PlaylistPrivacy``, because it is not one: Invidious
    /// serialises visibility as `isListed`, which is literally `privacy.public?`
    /// — `true` is public, and `false` is unlisted *or* private with no way to
    /// tell the two apart over the API. `nil` where the backend has no
    /// visibility concept at all, or did not answer with one.
    let isListed: Bool?

    init(playlist: Playlist, entries: [RemotePlaylistEntry], isListed: Bool? = nil) {
        self.playlist = playlist
        self.entries = entries
        self.isListed = isListed
    }
}

/// Who may see a server-side playlist.
///
/// The raw values are the words Invidious accepts. Piped has no visibility
/// concept at all — its capability row says so, and the write layer drops the
/// value rather than inventing one.
enum PlaylistPrivacy: String, Codable, Hashable, Sendable, CaseIterable {
    case `public`
    case unlisted
    case `private`
}
