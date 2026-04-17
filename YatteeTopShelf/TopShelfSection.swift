import Foundation

// Must stay in sync with Yattee/Core/Settings/TopShelfSection.swift.
enum TopShelfSection: String, Codable, CaseIterable, Sendable {
    case continueWatching
    case recentFeed
    case recentBookmarks

    var localizedTitle: String {
        // The extension doesn't share the main app's string catalog, so we
        // ship English fallbacks here. Keep in sync with
        // Localizable.xcstrings entries of the same keys.
        switch self {
        case .continueWatching:
            return String(localized: "home.section.continueWatching", defaultValue: "Continue Watching")
        case .recentFeed:
            return String(localized: "home.section.feed", defaultValue: "Feed")
        case .recentBookmarks:
            return String(localized: "home.section.bookmarks", defaultValue: "Bookmarks")
        }
    }

    var snapshotKey: String {
        switch self {
        case .continueWatching: return "topShelf.continueWatching"
        case .recentFeed: return "topShelf.recentFeed"
        case .recentBookmarks: return "topShelf.recentBookmarks"
        }
    }

    static let defaultOrder: [TopShelfSection] = [.continueWatching, .recentFeed, .recentBookmarks]
}
