//
//  HomeItem.swift
//  Yattee
//
//  Models for configurable Home view items.
//

import Foundation
import SwiftUI

// MARK: - Home Shortcut Layout

/// Layout mode for the shortcuts section in the Home view.
enum HomeShortcutLayout: String, CaseIterable, Sendable {
    case list
    case cards

    var displayName: LocalizedStringKey {
        switch self {
        case .list: return "home.shortcuts.layout.list"
        case .cards: return "home.shortcuts.layout.cards"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .cards: return "square.grid.2x2"
        }
    }
}

// MARK: - Home Section Layout

/// Layout mode for the configurable home sections (Continue Watching, Feed, etc.).
enum HomeSectionLayout: String, CaseIterable, Sendable {
    case list
    case grid

    var displayName: LocalizedStringKey {
        switch self {
        case .list: return "home.sections.layout.list"
        case .grid: return "home.sections.layout.grid"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }

    static var platformDefault: HomeSectionLayout {
        #if os(tvOS)
        return .grid
        #else
        return .list
        #endif
    }
}

// MARK: - Instance Content Type

/// Content type for instance home items.
enum InstanceContentType: String, Codable, Sendable {
    case feed
    case popular
    case trending

    var icon: String {
        switch self {
        case .feed: return "person.crop.rectangle.stack"
        case .popular: return "flame"
        case .trending: return "chart.line.uptrend.xyaxis"
        }
    }

    var localizedTitle: String {
        switch self {
        case .feed: return String(localized: "home.instanceContent.feed")
        case .popular: return String(localized: "home.instanceContent.popular")
        case .trending: return String(localized: "home.instanceContent.trending")
        }
    }

    /// Converts to InstanceBrowseView.BrowseTab for navigation
    func toBrowseTab() -> InstanceBrowseView.BrowseTab {
        switch self {
        case .feed: return .feed
        case .popular: return .popular
        case .trending: return .trending
        }
    }
}

// MARK: - Home Shortcut Item

/// Represents a shortcut item in the Home view dashboard.
enum HomeShortcutItem: Codable, Hashable, Identifiable, Sendable {
    case openURL
    case remoteControl
    case playlists
    case bookmarks
    case continueWatching
    case history
    case downloads
    case channels
    case subscriptions
    case mediaSources
    case instanceContent(instanceID: UUID, contentType: InstanceContentType)
    case mediaSource(sourceID: UUID)

    var id: String {
        switch self {
        case .openURL: return "openURL"
        case .remoteControl: return "remoteControl"
        case .playlists: return "playlists"
        case .bookmarks: return "bookmarks"
        case .continueWatching: return "continueWatching"
        case .history: return "history"
        case .downloads: return "downloads"
        case .channels: return "channels"
        case .subscriptions: return "subscriptions"
        case .mediaSources: return "mediaSources"
        case .instanceContent(let instanceID, let contentType):
            return "instance_\(instanceID.uuidString)_\(contentType.rawValue)"
        case .mediaSource(let sourceID):
            return "mediaSource_\(sourceID.uuidString)"
        }
    }

    /// Default order for shortcuts.
    static var defaultOrder: [HomeShortcutItem] {
        #if os(tvOS)
        [.openURL, .remoteControl, .playlists, .bookmarks, .continueWatching, .history, .channels, .subscriptions, .mediaSources]
        #else
        [.openURL, .remoteControl, .playlists, .bookmarks, .continueWatching, .history, .downloads, .channels, .subscriptions, .mediaSources]
        #endif
    }

    /// Default visibility for all shortcuts.
    static var defaultVisibility: [HomeShortcutItem: Bool] {
        #if os(tvOS)
        [.openURL: true, .remoteControl: true, .playlists: true, .bookmarks: true, .continueWatching: false, .history: true, .channels: true, .subscriptions: false, .mediaSources: false]
        #else
        [.openURL: true, .remoteControl: true, .playlists: false, .bookmarks: true, .continueWatching: false, .history: true, .downloads: false, .channels: false, .subscriptions: false, .mediaSources: false]
        #endif
    }

    /// SF Symbol icon name.
    /// Note: For .mediaSource, returns a placeholder. Views should look up the actual source icon.
    var icon: String {
        switch self {
        case .openURL: return "link"
        case .remoteControl: return "antenna.radiowaves.left.and.right"
        case .playlists: return "list.bullet.rectangle"
        case .bookmarks: return "bookmark.fill"
        case .continueWatching: return "play.circle"
        case .history: return "clock"
        case .downloads: return "arrow.down.circle"
        case .channels: return "person.2"
        case .subscriptions: return "play.rectangle.on.rectangle"
        case .mediaSources: return "externaldrive.connected.to.line.below"
        case .instanceContent(_, let contentType):
            return contentType.icon
        case .mediaSource:
            return "externaldrive.connected.to.line.below"
        }
    }

    /// Localized display title.
    /// Note: For .mediaSource, returns a placeholder. Views should look up the actual source name.
    var localizedTitle: String {
        switch self {
        case .openURL: return String(localized: "home.shortcut.openURL")
        case .remoteControl: return String(localized: "home.shortcut.remoteControl")
        case .playlists: return String(localized: "home.shortcut.playlists")
        case .bookmarks: return String(localized: "home.shortcut.bookmarks")
        case .continueWatching: return String(localized: "home.shortcut.continueWatching")
        case .history: return String(localized: "home.shortcut.history")
        case .downloads: return String(localized: "home.shortcut.downloads")
        case .channels: return String(localized: "home.shortcut.channels")
        case .subscriptions: return String(localized: "home.shortcut.subscriptions")
        case .mediaSources: return "Media Sources"
        case .instanceContent(_, let contentType):
            return contentType.localizedTitle
        case .mediaSource:
            return "Media Source"
        }
    }

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case type
        case instanceID
        case contentType
        case sourceID
    }

    private enum CardType: String, Codable {
        case openURL
        case remoteControl
        case playlists
        case bookmarks
        case continueWatching
        case history
        case downloads
        case channels
        case subscriptions
        case mediaSources
        case instanceContent
        case mediaSource
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .openURL:
            try container.encode(CardType.openURL, forKey: .type)
        case .remoteControl:
            try container.encode(CardType.remoteControl, forKey: .type)
        case .playlists:
            try container.encode(CardType.playlists, forKey: .type)
        case .bookmarks:
            try container.encode(CardType.bookmarks, forKey: .type)
        case .continueWatching:
            try container.encode(CardType.continueWatching, forKey: .type)
        case .history:
            try container.encode(CardType.history, forKey: .type)
        case .downloads:
            try container.encode(CardType.downloads, forKey: .type)
        case .channels:
            try container.encode(CardType.channels, forKey: .type)
        case .subscriptions:
            try container.encode(CardType.subscriptions, forKey: .type)
        case .mediaSources:
            try container.encode(CardType.mediaSources, forKey: .type)
        case .instanceContent(let instanceID, let contentType):
            try container.encode(CardType.instanceContent, forKey: .type)
            try container.encode(instanceID, forKey: .instanceID)
            try container.encode(contentType, forKey: .contentType)
        case .mediaSource(let sourceID):
            try container.encode(CardType.mediaSource, forKey: .type)
            try container.encode(sourceID, forKey: .sourceID)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CardType.self, forKey: .type)

        switch type {
        case .openURL:
            self = .openURL
        case .remoteControl:
            self = .remoteControl
        case .playlists:
            self = .playlists
        case .bookmarks:
            self = .bookmarks
        case .continueWatching:
            self = .continueWatching
        case .history:
            self = .history
        case .downloads:
            self = .downloads
        case .channels:
            self = .channels
        case .subscriptions:
            self = .subscriptions
        case .mediaSources:
            self = .mediaSources
        case .instanceContent:
            let instanceID = try container.decode(UUID.self, forKey: .instanceID)
            let contentType = try container.decode(InstanceContentType.self, forKey: .contentType)
            self = .instanceContent(instanceID: instanceID, contentType: contentType)
        case .mediaSource:
            let sourceID = try container.decode(UUID.self, forKey: .sourceID)
            self = .mediaSource(sourceID: sourceID)
        }
    }
}

// MARK: - Home Section Item

/// Represents a section item below the shortcuts in the Home view.
enum HomeSectionItem: Codable, Hashable, Identifiable, Sendable {
    case continueWatching
    case feed
    case bookmarks
    case history
    case downloads
    case instanceContent(instanceID: UUID, contentType: InstanceContentType)
    case mediaSource(sourceID: UUID)

    var id: String {
        switch self {
        case .continueWatching: return "continueWatching"
        case .feed: return "feed"
        case .bookmarks: return "bookmarks"
        case .history: return "history"
        case .downloads: return "downloads"
        case .instanceContent(let instanceID, let contentType):
            return "instance_\(instanceID.uuidString)_\(contentType.rawValue)"
        case .mediaSource(let sourceID):
            return "mediaSource_\(sourceID.uuidString)"
        }
    }

    /// Default order for sections.
    static var defaultOrder: [HomeSectionItem] {
        #if os(tvOS)
        [.continueWatching, .feed, .bookmarks, .history]
        #else
        [.continueWatching, .feed, .bookmarks, .history, .downloads]
        #endif
    }

    /// Default visibility for sections (only continue watching on by default).
    static var defaultVisibility: [HomeSectionItem: Bool] {
        #if os(tvOS)
        [.continueWatching: true, .feed: false, .bookmarks: false, .history: false]
        #else
        [.continueWatching: true, .feed: false, .bookmarks: false, .history: false, .downloads: false]
        #endif
    }

    /// SF Symbol icon name.
    /// Note: For .mediaSource, returns a placeholder. Views should look up the actual source icon.
    var icon: String {
        switch self {
        case .continueWatching: return "play.circle.fill"
        case .feed: return "play.rectangle.on.rectangle.fill"
        case .bookmarks: return "bookmark.fill"
        case .history: return "clock.arrow.circlepath"
        case .downloads: return "arrow.down.circle.fill"
        case .instanceContent(_, let contentType):
            return contentType.icon
        case .mediaSource:
            return "externaldrive.connected.to.line.below"
        }
    }

    /// Localized display title.
    /// Note: For .mediaSource, returns a placeholder. Views should look up the actual source name.
    var localizedTitle: String {
        switch self {
        case .continueWatching: return String(localized: "home.section.continueWatching")
        case .feed: return String(localized: "home.section.feed")
        case .bookmarks: return String(localized: "home.section.bookmarks")
        case .history: return String(localized: "home.section.history")
        case .downloads: return String(localized: "home.section.downloads")
        case .instanceContent(_, let contentType):
            return contentType.localizedTitle
        case .mediaSource:
            return "Media Source"
        }
    }

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case type
        case instanceID
        case contentType
        case sourceID
    }

    private enum SectionType: String, Codable {
        case continueWatching
        case feed
        case bookmarks
        case history
        case downloads
        case instanceContent
        case mediaSource
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .continueWatching:
            try container.encode(SectionType.continueWatching, forKey: .type)
        case .feed:
            try container.encode(SectionType.feed, forKey: .type)
        case .bookmarks:
            try container.encode(SectionType.bookmarks, forKey: .type)
        case .history:
            try container.encode(SectionType.history, forKey: .type)
        case .downloads:
            try container.encode(SectionType.downloads, forKey: .type)
        case .instanceContent(let instanceID, let contentType):
            try container.encode(SectionType.instanceContent, forKey: .type)
            try container.encode(instanceID, forKey: .instanceID)
            try container.encode(contentType, forKey: .contentType)
        case .mediaSource(let sourceID):
            try container.encode(SectionType.mediaSource, forKey: .type)
            try container.encode(sourceID, forKey: .sourceID)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SectionType.self, forKey: .type)

        switch type {
        case .continueWatching:
            self = .continueWatching
        case .feed:
            self = .feed
        case .bookmarks:
            self = .bookmarks
        case .history:
            self = .history
        case .downloads:
            self = .downloads
        case .instanceContent:
            let instanceID = try container.decode(UUID.self, forKey: .instanceID)
            let contentType = try container.decode(InstanceContentType.self, forKey: .contentType)
            self = .instanceContent(instanceID: instanceID, contentType: contentType)
        case .mediaSource:
            let sourceID = try container.decode(UUID.self, forKey: .sourceID)
            self = .mediaSource(sourceID: sourceID)
        }
    }
}
