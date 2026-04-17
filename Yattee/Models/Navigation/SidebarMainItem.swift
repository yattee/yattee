//
//  SidebarMainItem.swift
//  Yattee
//
//  Configurable sidebar main navigation item definitions.
//

import Foundation

/// Represents a configurable main navigation item in the sidebar.
enum SidebarMainItem: String, CaseIterable, Codable, Identifiable, Sendable {
    case search
    case home
    case subscriptions
    case bookmarks
    case history
    case downloads
    case channels
    case playlists
    case sources
    case settings
    case openURL
    case remoteControl

    var id: String { rawValue }

    /// Default order for sidebar main items.
    static var defaultOrder: [SidebarMainItem] {
        [.search, .home, .subscriptions, .bookmarks, .history, .channels, .playlists, .sources, .openURL, .remoteControl, .downloads, .settings]
    }

    /// Default visibility (all visible except subscriptions and channels).
    static var defaultVisibility: [SidebarMainItem: Bool] {
        #if os(tvOS)
        [
            .search: true,
            .home: true,
            .subscriptions: false,
            .bookmarks: false,
            .history: false,
            .downloads: true,
            .channels: false,
            .playlists: false,
            .sources: true,
            .settings: true,
            .openURL: false,
            .remoteControl: true
        ]
        #else
        [
            .search: true,
            .home: true,
            .subscriptions: false,
            .bookmarks: false,
            .history: false,
            .downloads: true,
            .channels: false,
            .playlists: false,
            .sources: true,
            .settings: true,
            .openURL: false,
            .remoteControl: false
        ]
        #endif
    }

    /// SF Symbol icon name.
    var icon: String {
        switch self {
        case .search: "magnifyingglass"
        case .home: "house.fill"
        case .subscriptions: "play.square.stack.fill"
        case .bookmarks: "bookmark.fill"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .channels: "person.2"
        case .playlists: "list.bullet.rectangle"
        case .sources: "server.rack"
        case .settings: "gear"
        case .openURL: "link"
        case .remoteControl: "antenna.radiowaves.left.and.right"
        }
    }

    /// Localized display title.
    var localizedTitle: String {
        switch self {
        case .search: String(localized: "sidebar.mainItem.search")
        case .home: String(localized: "sidebar.mainItem.home")
        case .subscriptions: String(localized: "sidebar.mainItem.subscriptions")
        case .bookmarks: String(localized: "sidebar.mainItem.bookmarks")
        case .history: String(localized: "sidebar.mainItem.history")
        case .downloads: String(localized: "sidebar.mainItem.downloads")
        case .channels: String(localized: "sidebar.mainItem.channels")
        case .playlists: String(localized: "sidebar.mainItem.playlists")
        case .sources: String(localized: "sidebar.mainItem.sources")
        case .settings: String(localized: "sidebar.mainItem.settings")
        case .openURL: String(localized: "sidebar.mainItem.openURL")
        case .remoteControl: String(localized: "sidebar.mainItem.remoteControl")
        }
    }

    /// Whether this item is required and cannot be hidden.
    var isRequired: Bool {
        switch self {
        case .search, .home:
            return true
        default:
            return false
        }
    }

    /// Whether this item is available on the current platform.
    var isAvailableOnCurrentPlatform: Bool {
        switch self {
        case .downloads:
            #if os(tvOS)
            return false
            #else
            return true
            #endif
        default:
            return true
        }
    }

    // MARK: - Tab Value Mappings

    /// Tab value for CompactTabView (String-based).
    /// Fixed tabs use "home" and "search", configurable tabs use TabBarItem.rawValue.
    var compactTabValue: String {
        switch self {
        case .search: return "search"
        case .home: return "home"
        case .subscriptions: return TabBarItem.subscriptions.rawValue
        case .bookmarks: return TabBarItem.bookmarks.rawValue
        case .history: return TabBarItem.history.rawValue
        case .downloads: return TabBarItem.downloads.rawValue
        case .channels: return TabBarItem.channels.rawValue
        case .playlists: return TabBarItem.playlists.rawValue
        case .sources: return TabBarItem.sources.rawValue
        case .settings: return TabBarItem.settings.rawValue
        case .openURL: return "open-url"
        case .remoteControl: return "remote-control"
        }
    }

    /// SidebarItem value for UnifiedTabView.
    var sidebarItem: SidebarItem {
        switch self {
        case .search: return .search
        case .home: return .home
        case .subscriptions: return .subscriptionsFeed
        case .bookmarks: return .bookmarks
        case .history: return .history
        case .downloads: return .downloads
        case .channels: return .manageChannels
        case .playlists: return .playlistsList
        case .sources: return .sources
        case .settings: return .settings
        case .openURL: return .openURL
        case .remoteControl: return .remoteControl
        }
    }

    /// Initialize from TabBarItem (for reverse mapping).
    init?(tabBarItem: TabBarItem) {
        switch tabBarItem {
        case .subscriptions: self = .subscriptions
        case .channels: self = .channels
        case .bookmarks: self = .bookmarks
        case .playlists: self = .playlists
        case .history: self = .history
        case .downloads: self = .downloads
        case .sources: self = .sources
        case .settings: self = .settings
        }
    }
}
