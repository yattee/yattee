//
//  SidebarItem.swift
//  Yattee
//
//  Represents items that can appear in the sidebar navigation.
//

import Foundation

/// Represents all possible sidebar items for navigation.
enum SidebarItem: Hashable, Identifiable {
    // MARK: - Fixed Navigation Items
    case home
    case search
    case sources
    case settings
    case nowPlaying
    case openURL
    case remoteControl

    // MARK: - Dynamic Channel Items
    case channel(channelID: String, name: String, source: ContentSource)

    // MARK: - Dynamic Playlist Items
    case playlist(id: UUID, title: String)

    /// A server-side playlist of the account the data context is on.
    /// `accountID` names the account it was listed for, which is what makes
    /// the detail view treat it as owned (editable).
    case remotePlaylist(id: PlaylistID, title: String, accountID: UUID)

    // MARK: - Dynamic Media Source Items
    case mediaSource(id: UUID, name: String, type: MediaSourceType)

    // MARK: - Dynamic Instance Items
    case instance(id: UUID, name: String, type: InstanceType)

    // MARK: - Collection Items
    case bookmarks
    case history
    case downloads
    case subscriptionsFeed
    case manageChannels
    case playlistsList
    case continueWatching

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .home:
            return "home"
        case .search:
            return "search"
        case .sources:
            return "sources"
        case .settings:
            return "settings"
        case .nowPlaying:
            return "now-playing"
        case .openURL:
            return "open-url"
        case .remoteControl:
            return "remote-control"
        case .channel(let channelID, _, let source):
            return "channel-\(source.provider)-\(channelID)"
        case .playlist(let id, _):
            return "playlist-\(id.uuidString)"
        case .remotePlaylist(let id, _, let accountID):
            return "remote-playlist-\(accountID.uuidString)-\(id.id)"
        case .mediaSource(let id, _, _):
            return "mediasource-\(id.uuidString)"
        case .instance(let id, _, _):
            return "instance-\(id.uuidString)"
        case .bookmarks:
            return "bookmarks"
        case .history:
            return "history"
        case .downloads:
            return "downloads"
        case .subscriptionsFeed:
            return "subscriptions-feed"
        case .manageChannels:
            return "manage-channels"
        case .playlistsList:
            return "playlists-list"
        case .continueWatching:
            return "continue-watching"
        }
    }

    // MARK: - Display Properties

    var title: String {
        switch self {
        case .home:
            return String(localized: "tabs.home")
        case .search:
            return String(localized: "tabs.search")
        case .sources:
            return String(localized: "tabs.sources")
        case .settings:
            return String(localized: "tabs.settings")
        case .nowPlaying:
            return String(localized: "sidebar.nowPlaying")
        case .openURL:
            return String(localized: "sidebar.mainItem.openURL")
        case .remoteControl:
            return String(localized: "sidebar.mainItem.remoteControl")
        case .channel(_, let name, _):
            return name
        case .playlist(_, let title):
            return title
        case .remotePlaylist(_, let title, _):
            return title
        case .mediaSource(_, let name, _):
            return name
        case .instance(_, let name, _):
            return name
        case .bookmarks:
            return String(localized: "home.bookmarks.title")
        case .history:
            return String(localized: "home.history.title")
        case .downloads:
            return String(localized: "home.downloads.title")
        case .subscriptionsFeed:
            return String(localized: "home.subscriptions.title")
        case .manageChannels:
            return String(localized: "sidebar.manageChannels")
        case .playlistsList:
            return String(localized: "home.playlists.title")
        case .continueWatching:
            return String(localized: "home.continueWatching.title")
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .search:
            return "magnifyingglass"
        case .sources:
            return "server.rack"
        case .settings:
            return "gear"
        case .nowPlaying:
            return "play.circle.fill"
        case .openURL:
            return "link"
        case .remoteControl:
            return "antenna.radiowaves.left.and.right"
        case .channel:
            return "person.circle"
        case .playlist, .remotePlaylist:
            return "list.bullet.rectangle"
        case .mediaSource(_, _, let type):
            return type.systemImage
        case .instance(_, _, let type):
            return type.systemImage
        case .bookmarks:
            return "bookmark.fill"
        case .history:
            return "clock"
        case .downloads:
            return "arrow.down.circle"
        case .subscriptionsFeed:
            return "play.square.stack.fill"
        case .manageChannels:
            return "person.2"
        case .playlistsList:
            return "list.bullet.rectangle"
        case .continueWatching:
            return "play.circle"
        }
    }

    // MARK: - Navigation

    /// Converts this sidebar item to a NavigationDestination for pushing onto the navigation stack.
    /// Returns nil for items that are root views (home, search) which don't push.
    func navigationDestination() -> NavigationDestination? {
        switch self {
        case .home, .search, .sources, .settings, .nowPlaying, .openURL, .remoteControl:
            // These are root tabs, not push destinations
            return nil
        case .channel(let channelID, _, let source):
            return .channel(channelID, source)
        case .playlist(let id, let title):
            return .playlist(.local(id, title: title))
        case .remotePlaylist(let id, let title, let accountID):
            // No instance here: the detail view resolves it from the account.
            return .playlist(.remote(id, instance: nil, title: title, accountID: accountID))
        case .mediaSource(let id, _, _):
            return .mediaSource(id)
        case .instance:
            // Instances are root views in the sidebar, not push destinations
            return nil
        case .bookmarks:
            return .bookmarks
        case .history:
            return .history
        case .downloads:
            return .downloads
        case .subscriptionsFeed:
            return .subscriptionsFeed
        case .manageChannels:
            return .manageChannels
        case .playlistsList:
            return .playlists
        case .continueWatching:
            return .continueWatching
        }
    }

    // MARK: - Item Categories

    /// Whether this is a dynamic playlist item.
    var isPlaylist: Bool {
        switch self {
        case .playlist, .remotePlaylist: return true
        default: return false
        }
    }

    /// Whether this is a dynamic media source item.
    var isMediaSource: Bool {
        if case .mediaSource = self { return true }
        return false
    }

    /// Whether this is a dynamic instance item.
    var isInstance: Bool {
        if case .instance = self { return true }
        return false
    }
}

// MARK: - Factory Methods

extension SidebarItem {
    /// Creates a SidebarItem from a Subscription.
    static func from(subscription: Subscription) -> SidebarItem {
        .channel(
            channelID: subscription.channelID,
            name: subscription.name,
            source: subscription.contentSource
        )
    }

    /// Creates a SidebarItem from a LocalPlaylist.
    static func from(playlist: LocalPlaylist) -> SidebarItem {
        .playlist(id: playlist.id, title: playlist.title)
    }

    /// Creates a SidebarItem from a server account's Channel.
    static func from(channel: Channel) -> SidebarItem {
        .channel(
            channelID: channel.id.channelID,
            name: channel.name,
            source: channel.id.source
        )
    }

    /// Creates a SidebarItem from a server account's Playlist.
    static func from(remotePlaylist playlist: Playlist, accountID: UUID) -> SidebarItem {
        .remotePlaylist(id: playlist.id, title: playlist.title, accountID: accountID)
    }

    /// Creates a SidebarItem from a MediaSource.
    static func from(mediaSource: MediaSource) -> SidebarItem {
        .mediaSource(id: mediaSource.id, name: mediaSource.name, type: mediaSource.type)
    }

    /// Creates a SidebarItem from an Instance.
    static func from(instance: Instance) -> SidebarItem {
        .instance(id: instance.id, name: instance.displayName, type: instance.type)
    }
}
