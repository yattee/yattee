import Foundation

enum VideosApp: String, CaseIterable {
    enum AppType: String {
        case local
        case youTube
        case peerTube
    }

    case local
    case invidious
    case piped
    case peerTube

    var name: String {
        switch self {
        case .peerTube:
            return "PeerTube"
        default:
            return rawValue.capitalized
        }
    }

    var appType: AppType {
        switch self {
        case .local:
            return .local
        case .invidious:
            return .youTube
        case .piped:
            return .youTube
        case .peerTube:
            return .peerTube
        }
    }

    var supportsAccounts: Bool {
        self != .local
    }

    var supportsPopular: Bool {
        self == .invidious
    }

    var supportsSearchFilters: Bool {
        self == .invidious
    }

    var supportsSearchSuggestions: Bool {
        self != .peerTube
    }

    var supportsSubscriptions: Bool {
        supportsAccounts
    }

    var paginatesSubscriptions: Bool {
        self == .invidious
    }

    var supportsTrendingCategories: Bool {
        self == .invidious
    }

    var supportsUserPlaylists: Bool {
        self != .local
    }

    var userPlaylistsEndpointIncludesVideos: Bool {
        self == .invidious
    }

    var userPlaylistsUseChannelPlaylistEndpoint: Bool {
        self == .piped
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

    var allowsDisablingVidoesProxying: Bool {
        self == .invidious || self == .piped
    }

    var supportsOpeningVideosByID: Bool {
        self != .local
    }
}
