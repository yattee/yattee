//
//  ChannelTab.swift
//  Yattee
//
//  Navigation tabs for channel content views.
//

import Foundation

/// Represents different content tabs available on a channel page.
enum ChannelTab: String, CaseIterable, Identifiable {
    case about
    case videos
    case playlists
    case shorts
    case streams

    var id: String { rawValue }

    /// Localized title for the tab.
    var title: String {
        switch self {
        case .about:
            return String(localized: "channel.tab.about")
        case .videos:
            return String(localized: "channel.tab.videos")
        case .playlists:
            return String(localized: "channel.tab.playlists")
        case .shorts:
            return String(localized: "channel.tab.shorts")
        case .streams:
            return String(localized: "channel.tab.streams")
        }
    }

    /// SF Symbol name for the tab icon.
    var systemImage: String {
        switch self {
        case .about:
            return "info.circle.fill"
        case .videos:
            return "play.rectangle.fill"
        case .playlists:
            return "list.bullet.rectangle.fill"
        case .shorts:
            return "bolt.fill"
        case .streams:
            return "video.fill"
        }
    }
}
