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

    static var logsDirectory: URL {
        temporaryDirectory
    }

    static var settingsExportDirectory: URL {
        temporaryDirectory
    }

    private static var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var configured = false

    @StateObject private var accounts = AccountsModel.shared
    @StateObject private var comments = CommentsModel.shared
    @StateObject private var instances = InstancesModel.shared
    @StateObject private var menu = MenuModel.shared
    @StateObject private var navigation = NavigationModel.shared
    @StateObject private var networkState = NetworkStateModel.shared
    @StateObject private var player = PlayerModel.shared
    @StateObject private var playlists = PlaylistsModel.shared
    @StateObject private var recents = RecentsModel.shared
    @StateObject private var settings = SettingsModel.shared
    @StateObject private var subscriptions = SubscribedChannelsModel.shared
    @StateObject private var thumbnails = ThumbnailsModel.shared

    let persistenceController = PersistenceController.shared

    var favorites: FavoritesModel { .shared }
    var playerControls: PlayerControlsModel { .shared }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: configure)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.navigationStyle, navigationStyle)
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
            #if !os(tvOS)
            .onOpenURL { url in
                URLBookmarkModel.shared.saveBookmark(url)
                OpenURLHandler(navigationStyle: navigationStyle).handle(url)
            }
            #endif
        }
        #if os(iOS)
        .handlesExternalEvents(matching: Set(["*"]))
        #endif
        #if !os(tvOS)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {}

            MenuCommands(model: Binding<MenuModel>(get: { MenuModel.shared }, set: { _ in }))
        }
        #endif

        #if os(macOS)
            WindowGroup(player.windowTitle) {
                VideoPlayerView()
                    .onAppear(perform: configure)
                    .background(
                        HostingWindowFinder { window in
                            Windows.playerWindow = window

                            NotificationCenter.default.addObserver( // swiftlint:disable:this discarded_notification_center_observer
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
                    .handlesExternalEvents(preferring: Set(["player", "*"]), allowing: Set(["player", "*"]))
                    .onOpenURL { url in
                        URLBookmarkModel.shared.saveBookmark(url)
                        OpenURLHandler(navigationStyle: navigationStyle).handle(url)
                    }
            }
            .handlesExternalEvents(matching: Set(["player", "*"]))

            Settings {
                SettingsView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
            }
        #endif
    }

    func configure() {
        guard !Self.isForPreviews, !configured else {
            return
        }
        configured = true

        DispatchQueue.main.async {
            #if DEBUG
                SiestaLog.Category.enabled = .common
            #endif
            #if os(tvOS)
                SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
            #else
                SDImageCodersManager.shared.addCoder(SDImageAWebPCoder.shared)
            #endif

            SDWebImageManager.defaultImageCache = PINCache(name: "stream.yattee.app")

            if !Defaults[.lastAccountIsPublic] {
                AccountsModel.shared.configureAccount()
            }

            if let countryOfPublicInstances = Defaults[.countryOfPublicInstances] {
                InstancesManifest.shared.setPublicAccount(countryOfPublicInstances, asCurrent: AccountsModel.shared.current.isNil)
            }

            if !AccountsModel.shared.current.isNil {
                player.restoreQueue()
            }

            DispatchQueue.global(qos: .userInitiated).async {
                if !Defaults[.saveRecents] {
                    recents.clear()
                }
            }

            let startupSection = Defaults[.startupSection]
            var section: TabSelection? = startupSection.tabSelection

            #if os(macOS)
                if section == .playlists {
                    section = .search
                }
            #endif

            NavigationModel.shared.tabSelection = section ?? .search

            DispatchQueue.main.async {
                playlists.load()
            }

            #if !os(macOS)
                player.updateRemoteCommandCenter()
            #endif

            if player.presentingPlayer {
                player.presentingPlayer = false
            }

            #if os(iOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if Defaults[.lockPortraitWhenBrowsing] {
                        Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                    } else {
                        let rotationOrientation =
                            OrientationTracker.shared.currentDeviceOrientation.rawValue == 4 ? UIInterfaceOrientation.landscapeRight :
                            (OrientationTracker.shared.currentDeviceOrientation.rawValue == 3 ? UIInterfaceOrientation.landscapeLeft : UIInterfaceOrientation.portrait)
                        Orientation.lockOrientation(.all, andRotateTo: rotationOrientation)
                    }
                }
            #endif

            // Initialize UserAgentManager
            _ = UserAgentManager.shared

            DispatchQueue.global(qos: .userInitiated).async {
                URLBookmarkModel.shared.refreshAll()
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.migrateHomeHistoryItems()
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.migrateQualityProfiles()
            }

            #if os(iOS)
                DispatchQueue.global(qos: .userInitiated).async {
                    self.migrateRotateToLandscapeOnEnterFullScreen()
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    self.migrateLockPortraitWhenBrowsing()
                }

            #endif
        }
    }

    func migrateHomeHistoryItems() {
        guard Defaults[.homeHistoryItems] > 0 else { return }

        if favorites.addableItems().contains(where: { $0.section == .history }) {
            let historyItem = FavoriteItem(section: .history)
            favorites.add(historyItem)
            favorites.setListingStyle(.list, historyItem)
            favorites.setLimit(Defaults[.homeHistoryItems], historyItem)

            print("migrated home history items: \(favorites.limit(historyItem))")
        }

        Defaults[.homeHistoryItems] = -1
    }

    @Default(.qualityProfiles) private var qualityProfilesData

    func migrateQualityProfiles() {
        for profile in qualityProfilesData where profile.order.isEmpty {
            var updatedProfile = profile
            updatedProfile.order = Array(QualityProfile.Format.allCases.indices)
            QualityProfilesModel.shared.update(profile, updatedProfile)
        }
    }

    #if os(iOS)
        func migrateRotateToLandscapeOnEnterFullScreen() {
            if Defaults[.rotateToLandscapeOnEnterFullScreen] != .landscapeRight || Defaults[.rotateToLandscapeOnEnterFullScreen] != .landscapeLeft {
                Defaults[.rotateToLandscapeOnEnterFullScreen] = .landscapeRight
            }
        }

        func migrateLockPortraitWhenBrowsing() {
            if Constants.isIPhone {
                Defaults[.lockPortraitWhenBrowsing] = true
            } else if Constants.isIPad, Defaults[.lockPortraitWhenBrowsing] {
                Defaults[.enterFullscreenInLandscape] = true
            }
        }
    #endif

    var navigationStyle: NavigationStyle {
        #if os(iOS)
            return horizontalSizeClass == .compact ? .tab : .sidebar
        #elseif os(tvOS)
            return .tab
        #else
            return .sidebar
        #endif
    }
}
