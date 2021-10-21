import Foundation

enum VideosApp: String, CaseIterable {
    case invidious, piped

    var name: String {
        rawValue.capitalized
    }

    var supportsAccounts: Bool {
        self == .invidious
    }

    var supportsPopular: Bool {
        self == .invidious
    }

    var supportsSearchFilters: Bool {
        self == .invidious
    }

    var supportsSubscriptions: Bool {
        supportsAccounts
    }

    var supportsTrendingCategories: Bool {
        self == .invidious
    }

    var supportsUserPlaylists: Bool {
        self == .invidious
    }
}
