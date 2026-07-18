//
//  SearchFilters.swift
//  Yattee
//
//  Search filter definitions for Invidious API.
//

import Foundation

/// Sort options for search results.
enum SearchSortOption: String, CaseIterable, Identifiable, Codable {
    case relevance
    case rating
    case date
    case views

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: return String(localized: "search.sort.relevance")
        case .rating: return String(localized: "search.sort.rating")
        case .date: return String(localized: "search.sort.date")
        case .views: return String(localized: "search.sort.views")
        }
    }
}

/// Upload date filter for search results.
enum SearchDateFilter: String, CaseIterable, Identifiable, Codable {
    case any = ""
    case hour
    case today
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return String(localized: "search.date.any")
        case .hour: return String(localized: "search.date.hour")
        case .today: return String(localized: "search.date.today")
        case .week: return String(localized: "search.date.week")
        case .month: return String(localized: "search.date.month")
        case .year: return String(localized: "search.date.year")
        }
    }
}

/// Duration filter for search results.
enum SearchDurationFilter: String, CaseIterable, Identifiable, Codable {
    case any = ""
    case short
    case medium
    case long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return String(localized: "search.duration.any")
        case .short: return String(localized: "search.duration.short")
        case .medium: return String(localized: "search.duration.medium")
        case .long: return String(localized: "search.duration.long")
        }
    }
}

/// Content type filter for search results.
enum SearchContentType: String, CaseIterable, Identifiable, Codable {
    case all
    case video
    case playlist
    case channel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "search.type.all")
        case .video: return String(localized: "search.type.video")
        case .playlist: return String(localized: "search.type.playlist")
        case .channel: return String(localized: "search.type.channel")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "magnifyingglass"
        case .video: return "play.rectangle"
        case .playlist: return "list.bullet.rectangle"
        case .channel: return "person.circle"
        }
    }
}

/// Search filters for Invidious API.
struct SearchFilters: Codable, Equatable {
    var sort: SearchSortOption = .relevance
    var date: SearchDateFilter = .any
    var duration: SearchDurationFilter = .any
    var type: SearchContentType = .video

    static let defaults = SearchFilters()

    /// Check if non-type filters are default (type is controlled separately by chips)
    var isDefault: Bool {
        sort == .relevance && date == .any && duration == .any
    }
}
