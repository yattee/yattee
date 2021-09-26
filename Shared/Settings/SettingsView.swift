import Defaults
import Foundation
import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case playback, instances
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
            TabView {
                Form {
                    InstancesSettingsView()
                }
                .tabItem {
                    Label("Instances", systemImage: "server.rack")
                }
                .tag(Tabs.instances)

                Form {
                    PlaybackSettingsView()
                }
                .tabItem {
                    Label("Playback", systemImage: "play.rectangle.on.rectangle.fill")
                }
                .tag(Tabs.playback)
            }
            .padding(20)
            .frame(width: 400, height: 310)
        #else
            NavigationView {
                List {
                    InstancesSettingsView()
                    PlaybackSettingsView()
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        #if !os(tvOS)
                            .keyboardShortcut(.cancelAction)
                        #endif
                    }
                }
                #if os(iOS)
                    .listStyle(.insetGrouped)
                #endif
            }
        #endif
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
        #if os(macOS)
            .frame(width: 600, height: 300)
        #endif
    }
}
