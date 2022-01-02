import Defaults
import Foundation
import SwiftUI

struct SettingsView: View {
    #if os(macOS)
        private enum Tabs: Hashable {
            case instances, browsing, history, playback, services, updates
        }
    #endif

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.presentationMode) private var presentationMode
    #endif

    @EnvironmentObject<AccountsModel> private var accounts

    @State private var presentingInstanceForm = false
    @State private var savedFormInstanceID: Instance.ID?

    @Default(.instances) private var instances

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
                    HistorySettings()
                }
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tabs.history)

                Form {
                    PlaybackSettings()
                }
                .tabItem {
                    Label("Playback", systemImage: "play.rectangle")
                }
                .tag(Tabs.playback)

                Form {
                    ServicesSettings()
                }
                .tabItem {
                    Label("Services", systemImage: "puzzlepiece")
                }
                .tag(Tabs.services)

                Form {
                    UpdatesSettings()
                }
                .tabItem {
                    Label("Updates", systemImage: "gearshape.2")
                }
                .tag(Tabs.updates)
            }
            .padding(20)
            .frame(width: 400, height: 400)
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

                    Section(header: Text("Instances")) {
                        ForEach(instances) { instance in
                            AccountsNavigationLink(instance: instance)
                        }
                        addInstanceButton
                    }

                    BrowsingSettings()
                    HistorySettings()
                    PlaybackSettings()
                    ServicesSettings()
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        #if !os(tvOS)
                            Button("Done") {
                                presentationMode.wrappedValue.dismiss()
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
            .sheet(isPresented: $presentingInstanceForm) {
                InstanceForm(savedInstanceID: $savedFormInstanceID)
            }
            #if os(tvOS)
            .background(Color.background(scheme: colorScheme))
            #endif
        #endif
    }

    private var addInstanceButton: some View {
        Button("Add Instance...") {
            presentingInstanceForm = true
        }
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
