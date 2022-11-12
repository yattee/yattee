import CoreMedia
import Foundation
import Siesta

struct OpenURLHandler {
    static var firstHandle = true
    static var shared = OpenURLHandler()
    static let yatteeProtocol = "yattee://"

    var accounts: AccountsModel!
    var navigation: NavigationModel!
    var recents: RecentsModel!
    var player: PlayerModel!
    var search: SearchModel!
    var navigationStyle = NavigationStyle.sidebar

    func handle(_ url: URL) {
        if Self.firstHandle {
            Self.firstHandle = false

            Delay.by(1) { Self.shared.handle(url) }
            return
        }

        if accounts.current.isNil {
            accounts.setCurrent(accounts.any)
        }

        guard !accounts.current.isNil else {
            return
        }

        #if os(macOS)
            guard url.host != Windows.player.location else {
                return
            }
        #endif

        guard let url = urlByReplacingYatteeProtocol(url) else { return }

        let parser = URLParser(url: url)

        switch parser.destination {
        case .fileURL:
            handleFileURLOpen(parser)
        case .video:
            handleVideoUrlOpen(parser)
        case .playlist:
            handlePlaylistUrlOpen(parser)
        case .channel:
            handleChannelUrlOpen(parser)
        case .search:
            handleSearchUrlOpen(parser)
        case .favorites:
            hideViewsAboveBrowser()
            navigation.tabSelection = .home
            #if os(macOS)
                focusMainWindow()
            #endif
        case .subscriptions:
            guard accounts.app.supportsSubscriptions, accounts.signedIn else { return }
            hideViewsAboveBrowser()
            navigation.tabSelection = .subscriptions
            #if os(macOS)
                focusMainWindow()
            #endif
        case .popular:
            guard accounts.app.supportsPopular else { return }
            hideViewsAboveBrowser()
            navigation.tabSelection = .popular
            #if os(macOS)
                focusMainWindow()
            #endif
        case .trending:
            hideViewsAboveBrowser()
            navigation.tabSelection = .trending
            #if os(macOS)
                focusMainWindow()
            #endif
        default:
            navigation.presentAlert(title: "Error", message: "This URL could not be opened")
            #if os(macOS)
                guard !Windows.main.isOpen else { return }
                navigation.presentingAlertInVideoPlayer = true
            #endif
        }
    }

    private func hideViewsAboveBrowser() {
        player.hide()
        navigation.presentingChannel = false
        navigation.presentingPlaylist = false
        navigation.presentingOpenVideos = false
    }

    private func urlByReplacingYatteeProtocol(_ url: URL, with urlProtocol: String = "https") -> URL! {
        var urlAbsoluteString = url.absoluteString

        guard urlAbsoluteString.hasPrefix(Self.yatteeProtocol) else {
            return url
        }

        urlAbsoluteString = String(urlAbsoluteString.dropFirst(Self.yatteeProtocol.count))
        if url.absoluteString.contains("://") {
            return URL(string: urlAbsoluteString)
        }

        return URL(string: "\(urlProtocol)://\(urlAbsoluteString)")
    }

    private func handleFileURLOpen(_ parser: URLParser) {
        guard let url = parser.fileURL else { return }

        OpenVideosModel.shared.openURLs([url], removeQueueItems: false, playbackMode: .playNow)
    }

    private func handleVideoUrlOpen(_ parser: URLParser) {
        guard let id = parser.videoID else {
            navigation.presentAlert(title: "Could not open video", message: "Could not extract video ID")
            return
        }

        guard id != player.currentVideo?.id else {
            return
        }

        #if os(macOS)
            Windows.main.open()
        #endif

        player.videoBeingOpened = Video(videoID: id)

        player.playerAPI.video(id)
            .load()
            .onSuccess { response in
                if let video: Video = response.typedContent() {
                    let time = parser.time.isNil ? nil : CMTime.secondsInDefaultTimescale(TimeInterval(parser.time!))
                    self.player.playNow(video, at: time)
                    self.player.show()
                } else {
                    navigation.presentAlert(title: "Error", message: "This video could not be opened")
                }
            }
            .onFailure { responseError in
                navigation.presentAlert(title: "Could not open video", message: responseError.userMessage)
            }
    }

    private func handlePlaylistUrlOpen(_ parser: URLParser) {
        #if os(macOS)
            if alertIfNoMainWindowOpen() { return }
        #endif

        guard let playlistID = parser.playlistID else {
            navigation.presentAlert(title: "Could not open playlist", message: "Could not extract playlist ID")
            return
        }

        accounts.api.channelPlaylist(playlistID)?
            .load()
            .onSuccess { response in
                if var playlist: ChannelPlaylist = response.typedContent() {
                    playlist.id = playlistID
                    DispatchQueue.main.async {
                        NavigationModel.openChannelPlaylist(
                            playlist,
                            player: player,
                            recents: recents,
                            navigation: navigation,
                            navigationStyle: navigationStyle
                        )
                    }
                } else {
                    navigation.presentAlert(title: "Could not open playlist", message: "Playlist could not be found")
                }
            }
            .onFailure { responseError in
                navigation.presentAlert(title: "Could not open playlist", message: responseError.userMessage)
            }
    }

    private func handleChannelUrlOpen(_ parser: URLParser) {
        #if os(macOS)
            if alertIfNoMainWindowOpen() { return }
        #endif

        guard let resource = resourceForChannelUrl(parser) else {
            navigation.presentAlert(title: "Could not open channel", message: "Could not extract channel information")
            return
        }

        resource
            .load()
            .onSuccess { response in
                if let channel: Channel = response.typedContent() {
                    DispatchQueue.main.async {
                        NavigationModel.openChannel(
                            channel,
                            player: player,
                            recents: recents,
                            navigation: navigation,
                            navigationStyle: navigationStyle
                        )
                    }
                } else {
                    navigation.presentAlert(title: "Could not open channel", message: "Channel could not be found")
                }
            }
            .onFailure { responseError in
                navigation.presentAlert(title: "Could not open channel", message: responseError.userMessage)
            }
    }

    private func resourceForChannelUrl(_ parser: URLParser) -> Resource? {
        if let id = parser.channelID {
            return accounts.api.channel(id)
        }

        if let resource = resourceForUsernameUrl(parser) {
            return resource
        }

        guard let name = parser.channelName else {
            return nil
        }

        if accounts.app.supportsOpeningChannelsByName {
            return accounts.api.channelByName(name)
        }

        if let instance = InstancesModel.all.first(where: { $0.app.supportsOpeningChannelsByName }) {
            return instance.anonymous.channelByName(name)
        }

        return nil
    }

    private func resourceForUsernameUrl(_ parser: URLParser) -> Resource? {
        guard let username = parser.username else { return nil }

        if accounts.app.supportsOpeningChannelsByName {
            return accounts.api.channelByUsername(username)
        }

        if let instance = InstancesModel.all.first(where: { $0.app.supportsOpeningChannelsByName }) {
            return instance.anonymous.channelByUsername(username)
        }

        return nil
    }

    private func handleSearchUrlOpen(_ parser: URLParser) {
        #if os(macOS)
            if alertIfNoMainWindowOpen() { return }
        #endif

        NavigationModel.openSearchQuery(
            parser.searchQuery,
            player: player,
            recents: recents,
            navigation: navigation,
            search: search
        )

        #if os(macOS)
            focusMainWindow()
        #endif
    }

    #if os(macOS)
        private func focusMainWindow() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Windows.main.focus()
            }
        }

        private func alertIfNoMainWindowOpen() -> Bool {
            guard !Windows.main.isOpen else {
                return false
            }

            navigation.presentAlert(
                title: "Restart the app to open this link",
                message:
                "To open this link in the app you need to close and open it manually to have browser window, " +
                    "then you can try opening links again.\n\nThis is a limitation of SwiftUI on macOS versions earlier than Ventura."
            )

            navigation.presentingAlertInVideoPlayer = true

            return true
        }
    #endif
}
