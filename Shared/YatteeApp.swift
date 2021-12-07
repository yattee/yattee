import Defaults
import SwiftUI

@main
struct YatteeApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
        @StateObject private var updater = UpdaterModel()
    #endif

    @StateObject private var menu = MenuModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(menu)
        }
        #if !os(tvOS)
        .handlesExternalEvents(matching: Set(["*"]))
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
            Settings {
                SettingsView()
                    .environmentObject(AccountsModel())
                    .environmentObject(InstancesModel())
                    .environmentObject(updater)
            }
        #endif
    }
}
