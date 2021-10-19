import Defaults
import SwiftUI

@main
struct PearvidiousApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if !os(tvOS)
            .commands {
                SidebarCommands()
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
