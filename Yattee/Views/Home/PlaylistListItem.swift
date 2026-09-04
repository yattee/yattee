//
//  PlaylistListItem.swift
//  Yattee
//
//  One row of the playlists list, whichever context filled it.
//

import Foundation

/// What identifies a row of the playlists list.
///
/// A server-side playlist id is only unique within the account that holds it,
/// which is all this has to be: the list shows one context's playlists, and a
/// context is the device's own data or a single account — never both, and never
/// two accounts at once.
enum PlaylistListItemID: Hashable {
    case local(UUID)
    case remote(PlaylistID)
}

/// A playlist as the list shows it, from either kind of context.
///
/// The two sides stay apart rather than being flattened into a common shape: a
/// local playlist is a SwiftData model with a duration to show, a server-side
/// one is a fetched value with an author, and each keeps rendering through the
/// row view built for it.
enum PlaylistListItem {
    case local(LocalPlaylist)
    case remote(Playlist)

    var id: PlaylistListItemID {
        switch self {
        case let .local(playlist): .local(playlist.id)
        case let .remote(playlist): .remote(playlist.id)
        }
    }

    var title: String {
        switch self {
        case let .local(playlist): playlist.title
        case let .remote(playlist): playlist.title
        }
    }

    /// The description a search matches against — named differently on each
    /// side, which is the whole reason this exists.
    var playlistDescription: String? {
        switch self {
        case let .local(playlist): playlist.playlistDescription
        case let .remote(playlist): playlist.description
        }
    }

    /// The zoom transition source, which is deliberately *not* the row
    /// identity: it has to be the value ``PlaylistSource/transitionID`` produces
    /// for the destination, or the transition has nothing to land on.
    var transitionID: AnyHashable {
        switch self {
        case let .local(playlist): playlist.id
        case let .remote(playlist): playlist.id
        }
    }

    /// Whether a search query matches this playlist.
    func matches(_ query: String) -> Bool {
        let query = query.lowercased()
        return title.lowercased().contains(query)
            || (playlistDescription?.lowercased().contains(query) ?? false)
    }

    /// The rows a search leaves, in the order they were given in.
    static func filtered(_ items: [PlaylistListItem], searchText: String) -> [PlaylistListItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.matches(searchText) }
    }
}
