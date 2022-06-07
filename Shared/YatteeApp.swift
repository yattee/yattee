import Defaults
import SwiftUI

@main
struct YatteeApp: App {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var accounts = AccountsModel()
    @StateObject private var comments = CommentsModel()
    @StateObject private var instances = InstancesModel()
    @StateObject private var menu = MenuModel()
    @StateObject private var navigation = NavigationModel()
    @StateObject private var player = PlayerModel()
    @StateObject private var playerControls = PlayerControlsModel()
    @StateObject private var playlists = PlaylistsModel()
    @StateObject private var recents = RecentsModel()
    @StateObject private var search = SearchModel()
    @StateObject private var subscriptions = SubscriptionsModel()
    @StateObject private var thumbnails = ThumbnailsModel()

    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(accounts)
                .environmentObject(comments)
                .environmentObject(instances)
                .environmentObject(navigation)
                .environmentObject(player)
                .environmentObject(playerControls)
                .environmentObject(playlists)
                .environmentObject(recents)
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
                    .background(
                        HostingWindowFinder { window in
                            Windows.playerWindow = window

                            NotificationCenter.default.addObserver(
                                forName: NSWindow.willExitFullScreenNotification,
                                object: window,
                                queue: OperationQueue.main
                            ) { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.player.controls.playingFullscreen = false
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
                    .environmentObject(player)
                    .environmentObject(playerControls)
                    .environmentObject(playlists)
                    .environmentObject(recents)
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
                    .environmentObject(player)
                    .environmentObject(playerControls)
            }
        #endif
    }
}
