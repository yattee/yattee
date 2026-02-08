//
//  HomeTab.swift
//  Yattee
//
//  Home tab selection definitions.
//

import Foundation

/// Home tab selection.
enum HomeTab: String, CaseIterable, Identifiable {
    case playlists
    case history
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playlists: return String(localized: "home.playlists.title")
        case .history: return String(localized: "home.history.title")
        case .downloads: return String(localized: "home.downloads.title")
        }
    }

    var icon: String {
        switch self {
        case .playlists: return "list.bullet.rectangle"
        case .history: return "clock"
        case .downloads: return "arrow.down.circle"
        }
    }
}
