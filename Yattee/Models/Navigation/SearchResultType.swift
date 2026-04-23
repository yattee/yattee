//
//  SearchResultType.swift
//  Yattee
//
//  Search result type filter definitions.
//

import Foundation

/// Search result type filter.
enum SearchResultType: String, CaseIterable, Identifiable {
    case all
    case videos
    case channels
    case playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "search.filter.all")
        case .videos: return String(localized: "search.filter.videos")
        case .channels: return String(localized: "search.filter.channels")
        case .playlists: return String(localized: "search.filter.playlists")
        }
    }
}
