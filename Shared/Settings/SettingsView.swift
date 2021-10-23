import Defaults
import Foundation
import SwiftUI

struct SettingsView: View {
    #if os(macOS)
        private enum Tabs: Hashable {
            case playback, instances
        }
    #endif

    #if os(iOS)
        @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(macOS)
            TabView {
                Form {
                    InstancesSettings()
                }
                .tabItem {
                    Label("Instances", systemImage: "server.rack")
                }
                .tag(Tabs.instances)

                Form {
                    PlaybackSettings()
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
                    #if os(tvOS)
                        AccountSelectionView()
                    #endif
                    InstancesSettings()
                    PlaybackSettings()
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        #if !os(tvOS)
                            Button("Done") {
                                dismiss()
                            }
                            .keyboardShortcut(.cancelAction)
                        #endif
                    }
                }
                .frame(maxWidth: 1000)
                #if os(iOS)
                    .listStyle(.insetGrouped)
                #endif
            }
            #if os(tvOS)
                .background(.thickMaterial)
            #endif
        #endif
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .injectFixtureEnvironmentObjects()
        #if os(macOS)
            .frame(width: 600, height: 300)
        #endif
    }
}
