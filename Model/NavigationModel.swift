import Foundation
import Siesta
import SwiftUI

final class NavigationModel: ObservableObject {
    static var shared = NavigationModel()

    var player = PlayerModel.shared
    var recents = RecentsModel.shared
    var search = SearchModel.shared

    enum TabSelection: Hashable {
        case home
        case documents
        case subscriptions
        case popular
        case trending
        case playlists
        case channel(String)
        case playlist(String)
        case recentlyOpened(String)
        case nowPlaying
        case search
        #if os(tvOS)
            case settings
        #endif

        var stringValue: String {
            switch self {
            case .home:
                return "favorites"
            case .subscriptions:
                return "subscriptions"
            case .popular:
                return "popular"
            case .trending:
                return "trending"
            case .playlists:
                return "playlists"
            case let .channel(string):
                return "channel\(string)"
            case let .playlist(string):
                return "playlist\(string)"
            case .recentlyOpened:
                return "recentlyOpened"
            case .search:
                return "search"
            #if os(tvOS)
                case .settings: // swiftlint:disable:this switch_case_alignment
                    return "settings"
            #endif
            default:
                return ""
            }
        }

        var playlistID: Playlist.ID? {
            if case let .playlist(id) = self {
                return id
            }

            return nil
        }
    }

    @Published var tabSelection: TabSelection!

    @Published var presentingAddToPlaylist = false
    @Published var videoToAddToPlaylist: Video!

    @Published var presentingPlaylistForm = false
    @Published var editedPlaylist: Playlist!

    @Published var presentingUnsubscribeAlert = false
    @Published var channelToUnsubscribe: Channel!

    @Published var presentingChannel = false
    @Published var presentingPlaylist = false
    @Published var sidebarSectionChanged = false

    @Published var presentingPlaybackSettings = false
    @Published var presentingOpenVideos = false
    @Published var presentingSettings = false
    @Published var presentingAccounts = false
    @Published var presentingWelcomeScreen = false

    @Published var presentingShareSheet = false
    @Published var shareURL: URL?

    @Published var alert = Alert(title: Text("Error"))
    @Published var presentingAlert = false
    @Published var presentingAlertInOpenVideos = false
    #if os(macOS)
        @Published var presentingAlertInVideoPlayer = false
    #endif

    @Published var presentingFileImporter = false

    func openChannel(_ channel: Channel, navigationStyle: NavigationStyle) {
        guard channel.id != Video.fixtureChannelID else {
            return
        }

        hideKeyboard()
        let presentingPlayer = player.presentingPlayer
        player.hide()
        presentingChannel = false

        #if os(macOS)
            Windows.main.open()
        #endif

        let recent = RecentItem(from: channel)
        recents.add(RecentItem(from: channel))

        if navigationStyle == .sidebar {
            sidebarSectionChanged.toggle()
            tabSelection = .recentlyOpened(recent.tag)
        } else {
            var delay = 0.0
            #if os(iOS)
                if presentingPlayer { delay = 1.0 }
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(Constants.overlayAnimation) {
                    self.presentingChannel = true
                }
            }
        }
    }

    func openChannelPlaylist(_ playlist: ChannelPlaylist, navigationStyle: NavigationStyle) {
        presentingChannel = false
        presentingPlaylist = false

        let recent = RecentItem(from: playlist)
        #if os(macOS)
            Windows.main.open()
        #else
            player.hide()
        #endif

        hideKeyboard()
        presentingChannel = false
        let presentingPlayer = player.presentingPlayer
        player.hide()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.recents.add(recent)

            if navigationStyle == .sidebar {
                self.sidebarSectionChanged.toggle()
                self.tabSelection = .recentlyOpened(recent.tag)
            } else {
                var delay = 0.0
                #if os(iOS)
                    if presentingPlayer { delay = 1.0 }
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Constants.overlayAnimation) {
                        self.presentingPlaylist = true
                    }
                }
            }
        }
    }

    func openSearchQuery(_ searchQuery: String?) {
        presentingChannel = false
        presentingPlaylist = false
        tabSelection = .search

        hideKeyboard()

        let presentingPlayer = player.presentingPlayer
        player.hide()

        if let searchQuery {
            let recent = RecentItem(from: searchQuery)
            recents.add(recent)

            var delay = 0.0
            #if os(iOS)
                if presentingPlayer { delay = 1.0 }
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.search.queryText = searchQuery
                self.search.changeQuery { query in query.query = searchQuery }
            }
        }

        #if os(macOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Windows.main.focus()
            }
        #endif
    }

    var tabSelectionBinding: Binding<TabSelection> {
        Binding<TabSelection>(
            get: {
                self.tabSelection ?? .search
            },
            set: { newValue in
                self.tabSelection = newValue
            }
        )
    }

    func presentAddToPlaylist(_ video: Video) {
        videoToAddToPlaylist = video
        presentingAddToPlaylist = true
    }

    func presentEditPlaylistForm(_ playlist: Playlist?) {
        editedPlaylist = playlist
        presentingPlaylistForm = editedPlaylist != nil
    }

    func presentNewPlaylistForm() {
        editedPlaylist = nil
        presentingPlaylistForm = true
    }

    func presentUnsubscribeAlert(_ channel: Channel, subscriptions: SubscribedChannelsModel) {
        channelToUnsubscribe = channel
        alert = Alert(
            title: Text(
                "Are you sure you want to unsubscribe from \(channelToUnsubscribe.name)?"
            ),
            primaryButton: .destructive(Text("Unsubscribe")) { [weak self] in
                if let id = self?.channelToUnsubscribe.id {
                    subscriptions.unsubscribe(id)
                }
            },
            secondaryButton: .cancel()
        )
        presentingAlert = true
    }

    func hideViewsAboveBrowser() {
        player.hide()
        presentingChannel = false
        presentingPlaylist = false
        presentingOpenVideos = false
    }

    func hideKeyboard() {
        #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    func presentAlert(title: String, message: String? = nil) {
        let message = message.isNil ? nil : Text(message!)
        alert = Alert(title: Text(title), message: message)
        presentingAlert = true
    }

    func presentRequestErrorAlert(_ error: RequestError) {
        let errorDescription = String(format: "Verify you have stable connection with the server you are using (%@)", AccountsModel.shared.current.instance.longDescription)
        presentAlert(title: "Connection Error", message: "\(error.userMessage)\n\n\(errorDescription)")
    }

    func presentAlert(_ alert: Alert) {
        self.alert = alert
        presentingAlert = true
    }

    func presentShareSheet(_ url: URL) {
        shareURL = url
        presentingShareSheet = true
    }
}

typealias TabSelection = NavigationModel.TabSelection
