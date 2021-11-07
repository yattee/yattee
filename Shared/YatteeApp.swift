import Defaults
import SwiftUI

@main
struct YatteeApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if !os(tvOS)
            .handlesExternalEvents(matching: Set(["*"]))
            .commands {
                SidebarCommands()
                CommandGroup(replacing: .newItem, addition: {})
            }
        #endif

        #if os(macOS)
            Settings {
                SettingsView()
                    .environmentObject(InstancesModel())
            }
        #endif
    }
}
