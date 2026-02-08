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

    // MARK: - Dynamic Channel Items
    case channel(channelID: String, name: String, source: ContentSource)

    // MARK: - Dynamic Playlist Items
    case playlist(id: UUID, title: String)

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
        case .channel(let channelID, _, let source):
            return "channel-\(source.provider)-\(channelID)"
        case .playlist(let id, _):
            return "playlist-\(id.uuidString)"
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
        case .channel(_, let name, _):
            return name
        case .playlist(_, let title):
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
        case .channel:
            return "person.circle"
        case .playlist:
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
        }
    }

    // MARK: - Navigation

    /// Converts this sidebar item to a NavigationDestination for pushing onto the navigation stack.
    /// Returns nil for items that are root views (home, search) which don't push.
    func navigationDestination() -> NavigationDestination? {
        switch self {
        case .home, .search, .sources, .settings, .nowPlaying:
            // These are root tabs, not push destinations
            return nil
        case .channel(let channelID, _, let source):
            return .channel(channelID, source)
        case .playlist(let id, let title):
            return .playlist(.local(id, title: title))
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
        }
    }

    // MARK: - Item Categories

    /// Whether this is a fixed navigation item (always visible).
    var isFixedNavigation: Bool {
        switch self {
        case .home, .search, .sources, .settings, .nowPlaying:
            return true
        default:
            return false
        }
    }

    /// Whether this is a dynamic channel item.
    var isChannel: Bool {
        if case .channel = self { return true }
        return false
    }

    /// Whether this is a dynamic playlist item.
    var isPlaylist: Bool {
        if case .playlist = self { return true }
        return false
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

    /// Creates a SidebarItem from a MediaSource.
    static func from(mediaSource: MediaSource) -> SidebarItem {
        .mediaSource(id: mediaSource.id, name: mediaSource.name, type: mediaSource.type)
    }

    /// Creates a SidebarItem from an Instance.
    static func from(instance: Instance) -> SidebarItem {
        .instance(id: instance.id, name: instance.displayName, type: instance.type)
    }
}
