//
//  TabBarItem.swift
//  Yattee
//
//  Configurable tab bar item definitions for compact size class navigation.
//

import Foundation

/// Represents a configurable tab bar item for compact width (iPhone, iPad small window).
enum TabBarItem: String, CaseIterable, Codable, Identifiable, Sendable {
    case subscriptions
    case channels
    case bookmarks
    case playlists
    case history
    case downloads
    case sources
    case settings

    var id: String { rawValue }

    /// Default order for tab bar items.
    static var defaultOrder: [TabBarItem] {
        [.subscriptions, .channels, .bookmarks, .playlists, .history, .sources, .downloads, .settings]
    }

    /// Default visibility (only subscriptions visible by default).
    static var defaultVisibility: [TabBarItem: Bool] {
        [.subscriptions: false, .channels: false, .bookmarks: false, .playlists: false, .history: false, .downloads: true, .sources: true, .settings: false]
    }

    /// SF Symbol icon name.
    var icon: String {
        switch self {
        case .subscriptions: "play.square.stack.fill"
        case .channels: "person.crop.rectangle.stack.fill"
        case .bookmarks: "bookmark.fill"
        case .playlists: "list.bullet.rectangle"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .sources: "server.rack"
        case .settings: "gear"
        }
    }

    /// Localized display title.
    var localizedTitle: String {
        switch self {
        case .subscriptions: String(localized: "tabBar.item.subscriptions")
        case .channels: String(localized: "tabBar.item.channels")
        case .bookmarks: String(localized: "tabBar.item.bookmarks")
        case .playlists: String(localized: "tabBar.item.playlists")
        case .history: String(localized: "tabBar.item.history")
        case .downloads: String(localized: "tabBar.item.downloads")
        case .sources: String(localized: "tabBar.item.sources")
        case .settings: String(localized: "tabBar.item.settings")
        }
    }
}
