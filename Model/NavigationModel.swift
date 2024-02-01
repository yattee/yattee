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
                case .settings:
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

    @Published var tabSelection: TabSelection! { didSet {
        if oldValue == tabSelection { multipleTapHandler() }
        if tabSelection == nil, let item = recents.presentedItem {
            Delay.by(0.2) { [weak self] in
                self?.tabSelection = .recentlyOpened(item.tag)
            }
        }
    }}

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
    @Published var presentingHomeSettings = false

    @Published var presentingChannelSheet = false
    @Published var channelPresentedInSheet: Channel!

    @Published var presentingShareSheet = false
    @Published var shareURL: URL?

    @Published var alert = Alert(title: Text("Error"))
    @Published var presentingAlert = false
    @Published var presentingAlertInOpenVideos = false
    #if os(macOS)
        @Published var presentingAlertInVideoPlayer = false
    #endif

    @Published var presentingFileImporter = false

    @Published var presentingSettingsImportSheet = false
    @Published var presentingSettingsFileImporter = false
    @Published var settingsImportURL: URL?

    func openChannel(_ channel: Channel, navigationStyle: NavigationStyle) {
        guard channel.id != Video.fixtureChannelID else {
            return
        }

        hideKeyboard()
        let presentingPlayer = player.presentingPlayer
        presentingChannel = false

        #if os(macOS)
            Windows.main.open()
        #endif

        let recent = RecentItem(from: channel)
        recents.add(RecentItem(from: channel))

        let navigateToChannel = {
            #if os(iOS)
                self.player.hide()
            #endif

            if navigationStyle == .sidebar {
                self.sidebarSectionChanged.toggle()
                self.tabSelection = .recentlyOpened(recent.tag)
            } else {
                withAnimation(Constants.overlayAnimation) {
                    self.presentingChannel = true
                }
            }
        }

        #if os(iOS)
            if presentingPlayer {
                presentChannelInSheet(channel)
            } else {
                navigateToChannel()
            }
        #elseif os(tvOS)
            Delay.by(0.01) {
                navigateToChannel()
            }
        #else
            navigateToChannel()
        #endif
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
        presentingFileImporter = false
        presentingSettingsImportSheet = false
    }

    func hideKeyboard() {
        #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    func presentAlert(title: String, message: String? = nil) {
        let message = message.isNil ? nil : Text(message!)
        let alert = Alert(title: Text(title), message: message)

        presentAlert(alert)
    }

    func presentRequestErrorAlert(_ error: RequestError) {
        let errorDescription = String(format: "Verify you have stable connection with the server you are using (%@)", AccountsModel.shared.current.instance.longDescription)
        presentAlert(title: "Connection Error", message: "\(error.userMessage)\n\n\(errorDescription)")
    }

    func presentAlert(_ alert: Alert) {
        guard !presentingSettings else {
            SettingsModel.shared.presentAlert(alert)
            return
        }

        self.alert = alert
        presentingAlert = true
    }

    func presentShareSheet(_ url: URL) {
        shareURL = url
        presentingShareSheet = true
    }

    func presentChannelInSheet(_ channel: Channel) {
        channelPresentedInSheet = channel
        presentingChannelSheet = true
    }

    func multipleTapHandler() {
        switch tabSelection {
        case .search:
            self.search.focused = true
        default:
            print("not implemented")
        }
    }

    func presentSettingsImportSheet(_ url: URL, forceSettings: Bool = false) {
        guard !presentingSettings, !forceSettings else {
            ImportExportSettingsModel.shared.reset()
            SettingsModel.shared.presentSettingsImportSheet(url)
            return
        }
        settingsImportURL = url
        presentingSettingsImportSheet = true
    }
}

typealias TabSelection = NavigationModel.TabSelection
