import Defaults
import MediaPlayer
import PINCache
import SDWebImage
import SDWebImageWebPCoder
import Siesta
import SwiftUI

@main
struct YatteeApp: App {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    static var isForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @State private var configured = false

    @StateObject private var accounts = AccountsModel()
    @StateObject private var comments = CommentsModel()
    @StateObject private var instances = InstancesModel()
    @StateObject private var menu = MenuModel()
    @StateObject private var navigation = NavigationModel()
    @StateObject private var networkState = NetworkStateModel()
    @StateObject private var player = PlayerModel()
    @StateObject private var playerControls = PlayerControlsModel()
    @StateObject private var playerTime = PlayerTimeModel()
    @StateObject private var playlists = PlaylistsModel()
    @StateObject private var recents = RecentsModel()
    @StateObject private var search = SearchModel()
    @StateObject private var settings = SettingsModel()
    @StateObject private var subscriptions = SubscriptionsModel()
    @StateObject private var thumbnails = ThumbnailsModel()

    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: configure)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(accounts)
                .environmentObject(comments)
                .environmentObject(instances)
                .environmentObject(navigation)
                .environmentObject(networkState)
                .environmentObject(player)
                .environmentObject(playerControls)
                .environmentObject(playerTime)
                .environmentObject(playlists)
                .environmentObject(recents)
                .environmentObject(settings)
                .environmentObject(subscriptions)
                .environmentObject(thumbnails)
                .environmentObject(menu)
                .environmentObject(search)
            #if os(macOS)
                .background(
                    HostingWindowFinder { window in
                        Windows.mainWindow = window
                    }
                )
            #else
                    .onReceive(
                        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                    ) { _ in
                        player.handleEnterForeground()
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                    ) { _ in
                        player.handleEnterBackground()
                    }
            #endif
            #if os(iOS)
            .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
            #endif
        }
        #if os(iOS)
        .handlesExternalEvents(matching: Set(["*"]))
        #endif
        #if !os(tvOS)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem, addition: {})

            MenuCommands(model: Binding<MenuModel>(get: { menu }, set: { _ in }))
        }
        #endif

        #if os(macOS)
            WindowGroup(player.windowTitle) {
                VideoPlayerView()
                    .onAppear(perform: configure)
                    .background(
                        HostingWindowFinder { window in
                            Windows.playerWindow = window

                            NotificationCenter.default.addObserver(
                                forName: NSWindow.willExitFullScreenNotification,
                                object: window,
                                queue: OperationQueue.main
                            ) { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.player.playingFullScreen = false
                                }
                            }
                        }
                    )
                    .onAppear { player.presentingPlayer = true }
                    .onDisappear { player.presentingPlayer = false }
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environment(\.navigationStyle, .sidebar)
                    .environmentObject(accounts)
                    .environmentObject(comments)
                    .environmentObject(instances)
                    .environmentObject(navigation)
                    .environmentObject(networkState)
                    .environmentObject(player)
                    .environmentObject(playerControls)
                    .environmentObject(playerTime)
                    .environmentObject(playlists)
                    .environmentObject(recents)
                    .environmentObject(search)
                    .environmentObject(subscriptions)
                    .environmentObject(thumbnails)
                    .handlesExternalEvents(preferring: Set(["player", "*"]), allowing: Set(["player", "*"]))
            }
            .handlesExternalEvents(matching: Set(["player", "*"]))

            Settings {
                SettingsView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(accounts)
                    .environmentObject(instances)
                    .environmentObject(navigation)
                    .environmentObject(player)
                    .environmentObject(playerControls)
                    .environmentObject(settings)
            }
        #endif
    }

    func configure() {
        guard !Self.isForPreviews, !configured else {
            return
        }
        configured = true

        SiestaLog.Category.enabled = .common
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
        SDWebImageManager.defaultImageCache = PINCache(name: "stream.yattee.app")

        #if !os(macOS)
            configureNowPlayingInfoCenter()
        #endif

        #if os(iOS)
            if Defaults[.lockPortraitWhenBrowsing] {
                Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
            }
        #endif

        if Defaults[.lastAccountID] != "public",
           let account = accounts.lastUsed ??
           instances.lastUsed?.anonymousAccount ??
           InstancesModel.all.first?.anonymousAccount
        {
            accounts.setCurrent(account)
        }

        let countryOfPublicInstances = Defaults[.countryOfPublicInstances]
        if accounts.current.isNil, countryOfPublicInstances.isNil {
            navigation.presentingWelcomeScreen = true
        }

        if !countryOfPublicInstances.isNil {
            InstancesManifest.shared.setPublicAccount(countryOfPublicInstances!, accounts: accounts, asCurrent: accounts.current.isNil)
        }

        playlists.accounts = accounts
        search.accounts = accounts
        subscriptions.accounts = accounts

        comments.player = player

        menu.accounts = accounts
        menu.navigation = navigation
        menu.player = player

        playerControls.player = player

        player.accounts = accounts
        player.comments = comments
        player.controls = playerControls
        player.navigation = navigation
        player.networkState = networkState
        player.playerTime = playerTime

        if !accounts.current.isNil {
            player.restoreQueue()
        }

        if !Defaults[.saveRecents] {
            recents.clear()
        }

        var section = Defaults[.visibleSections].min()?.tabSelection

        #if os(macOS)
            if section == .playlists {
                section = .search
            }
        #endif

        navigation.tabSelection = section ?? .search

        subscriptions.load()
        playlists.load()

        #if os(macOS)
            Windows.player.open()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Windows.main.focus()
            }
        #endif
    }

    func configureNowPlayingInfoCenter() {
        #if !os(macOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

            UIApplication.shared.beginReceivingRemoteControlEvents()
        #endif

        MPRemoteCommandCenter.shared().playCommand.addTarget { _ in
            player.play()
            return .success
        }

        MPRemoteCommandCenter.shared().pauseCommand.addTarget { _ in
            player.pause()
            return .success
        }

        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false

        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.addTarget { remoteEvent in
            guard let event = remoteEvent as? MPChangePlaybackPositionCommandEvent
            else {
                return .commandFailed
            }

            player.backend.seek(to: event.positionTime)

            return .success
        }

        let skipForwardCommand = MPRemoteCommandCenter.shared().skipForwardCommand
        skipForwardCommand.isEnabled = true
        skipForwardCommand.preferredIntervals = [10]

        skipForwardCommand.addTarget { _ in
            player.backend.seek(relative: .secondsInDefaultTimescale(10))
            return .success
        }

        let skipBackwardCommand = MPRemoteCommandCenter.shared().skipBackwardCommand
        skipBackwardCommand.isEnabled = true
        skipBackwardCommand.preferredIntervals = [10]

        skipBackwardCommand.addTarget { _ in
            player.backend.seek(relative: .secondsInDefaultTimescale(-10))
            return .success
        }
    }
}
