import Defaults
import Foundation
import SwiftUI

struct SettingsView: View {
    #if os(macOS)
        private enum Tabs: Hashable {
            case instances, browsing, playback, services
        }
    #endif

    #if os(iOS)
        @Environment(\.dismiss) private var dismiss
    #endif

    @EnvironmentObject<AccountsModel> private var accounts

    var body: some View {
        #if os(macOS)
            TabView {
                Form {
                    InstancesSettings()
                        .environmentObject(accounts)
                }
                .tabItem {
                    Label("Instances", systemImage: "server.rack")
                }
                .tag(Tabs.instances)

                Form {
                    BrowsingSettings()
                }
                .tabItem {
                    Label("Browsing", systemImage: "list.and.film")
                }
                .tag(Tabs.browsing)

                Form {
                    PlaybackSettings()
                }
                .tabItem {
                    Label("Playback", systemImage: "play.rectangle.on.rectangle.fill")
                }
                .tag(Tabs.playback)

                Form {
                    ServicesSettings()
                }
                .tabItem {
                    Label("Services", systemImage: "puzzlepiece.extension")
                }
                .tag(Tabs.services)
            }
            .padding(20)
            .frame(width: 400, height: 380)
        #else
            NavigationView {
                List {
                    #if os(tvOS)
                        AccountSelectionView()

                        Section(header: SettingsHeader(text: "Favorites")) {
                            NavigationLink("Edit favorites...") {
                                EditFavorites()
                            }
                        }
                    #endif
                    InstancesSettings()
                        .environmentObject(accounts)
                    BrowsingSettings()
                    PlaybackSettings()
                    ServicesSettings()
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
            .background(.black)
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
