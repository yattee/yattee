import Defaults
import SwiftUI

@main
struct YatteeApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
        @StateObject private var updater = UpdaterModel()
    #endif

    @StateObject private var accounts = AccountsModel()
    @StateObject private var comments = CommentsModel()
    @StateObject private var instances = InstancesModel()
    @StateObject private var menu = MenuModel()
    @StateObject private var navigation = NavigationModel()
    @StateObject private var player = PlayerModel()
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
                .environmentObject(playlists)
                .environmentObject(recents)
                .environmentObject(subscriptions)
                .environmentObject(thumbnails)
                .environmentObject(menu)
                .environmentObject(search)
            #if !os(macOS)
                .onReceive(
                    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                ) { _ in
                    player.handleEnterForeground()
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

            #if os(macOS)
                CommandGroup(after: .appInfo) {
                    CheckForUpdatesView()
                        .environmentObject(updater)
                }
            #endif

            MenuCommands(model: Binding<MenuModel>(get: { menu }, set: { _ in }))
        }
        #endif

        #if os(macOS)
            WindowGroup(player.windowTitle) {
                VideoPlayerView()
                    .onAppear { player.presentingPlayer = true }
                    .onDisappear { player.presentingPlayer = false }
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environment(\.navigationStyle, .sidebar)
                    .environmentObject(accounts)
                    .environmentObject(comments)
                    .environmentObject(instances)
                    .environmentObject(navigation)
                    .environmentObject(player)
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
                    .environmentObject(updater)
            }
        #endif
    }
}
