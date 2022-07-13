import Foundation

enum VideosApp: String, CaseIterable {
    case invidious, piped

    var name: String {
        rawValue.capitalized
    }

    var supportsAccounts: Bool {
        true
    }

    var accountsUsePassword: Bool {
        self == .piped
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
        true
    }

    var userPlaylistsEndpointIncludesVideos: Bool {
        self == .invidious
    }

    var userPlaylistsHaveVisibility: Bool {
        self == .invidious
    }

    var userPlaylistsAreEditable: Bool {
        self == .invidious
    }

    var hasFrontendURL: Bool {
        self == .piped
    }

    var searchUsesIndexedPages: Bool {
        self == .invidious
    }

    var supportsOpeningChannelsByName: Bool {
        self == .piped
    }
}
