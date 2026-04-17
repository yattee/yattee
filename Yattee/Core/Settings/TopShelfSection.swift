import Foundation

/// Sections that can appear in the tvOS Top Shelf.
/// Stored ordered in `SettingsKey.topShelfSections` — inclusion = visible.
enum TopShelfSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case continueWatching
    case recentFeed
    case recentBookmarks

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .continueWatching: return String(localized: "home.section.continueWatching")
        case .recentFeed: return String(localized: "home.section.feed")
        case .recentBookmarks: return String(localized: "home.section.bookmarks")
        }
    }

    /// UserDefaults key (under the app-group suite) holding the JSON snapshot for this section.
    var snapshotKey: String {
        switch self {
        case .continueWatching: return "topShelf.continueWatching"
        case .recentFeed: return "topShelf.recentFeed"
        case .recentBookmarks: return "topShelf.recentBookmarks"
        }
    }

    static let defaultOrder: [TopShelfSection] = [.continueWatching, .recentFeed, .recentBookmarks]
}
