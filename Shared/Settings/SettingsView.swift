import Defaults
import Foundation
import SwiftUI

struct SettingsView: View {
    static let matrixURL = URL(string: "https://tinyurl.com/matrix-yattee")!
    static let discordURL = URL(string: "https://yattee.stream/discord")!

    #if os(macOS)
        private enum Tabs: Hashable {
            case locations, browsing, player, history, sponsorBlock, advanced, help
        }

        @State private var selection = Tabs.locations
    #endif

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.presentationMode) private var presentationMode
    #endif

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<SettingsModel> private var model

    @Default(.instances) private var instances

    var body: some View {
        settings
            .environmentObject(model)
            .alert(isPresented: $model.presentingAlert) { model.alert }
    }

    var settings: some View {
        #if os(macOS)
            TabView(selection: $selection) {
                Form {
                    LocationsSettings()
                }
                .tabItem {
                    Label("Locations", systemImage: "globe")
                }
                .tag(Tabs.locations)

                Form {
                    BrowsingSettings()
                }
                .tabItem {
                    Label("Browsing", systemImage: "list.and.film")
                }
                .tag(Tabs.browsing)

                Form {
                    PlayerSettings()
                }
                .tabItem {
                    Label("Player", systemImage: "play.rectangle")
                }
                .tag(Tabs.player)

                Form {
                    HistorySettings()
                }
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tabs.history)

                Form {
                    SponsorBlockSettings()
                }
                .tabItem {
                    Label("SponsorBlock", systemImage: "dollarsign.circle")
                }
                .tag(Tabs.sponsorBlock)

                Group {
                    AdvancedSettings()
                }
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
                .tag(Tabs.advanced)

                Form {
                    Help()
                }
                .tabItem {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .tag(Tabs.help)
            }
            .padding(20)
            .frame(width: 480, height: windowHeight)
        #else
            Group {
                #if os(tvOS)
                    settingsList
                #else
                    NavigationView {
                        settingsList
                    }
                #endif
            }

        #endif
    }

    #if !os(macOS)
        var settingsList: some View {
            List {
                #if os(tvOS)
                    AccountSelectionView()
                    Divider()
                #endif

                Section {
                    #if os(tvOS)
                        NavigationLink {
                            EditFavorites()
                        } label: {
                            Label("Favorites", systemImage: "heart.fill")
                        }
                    #endif

                    NavigationLink {
                        LocationsSettings()
                    } label: {
                        Label("Locations", systemImage: "globe")
                    }

                    NavigationLink {
                        BrowsingSettings()
                    } label: {
                        Label("Browsing", systemImage: "list.and.film")
                    }

                    NavigationLink {
                        PlayerSettings()
                    } label: {
                        Label("Player", systemImage: "play.rectangle")
                    }

                    NavigationLink {
                        HistorySettings()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }

                    NavigationLink {
                        SponsorBlockSettings()
                    } label: {
                        Label("SponsorBlock", systemImage: "dollarsign.circle")
                    }

                    NavigationLink {
                        AdvancedSettings()
                    } label: {
                        Label("Advanced", systemImage: "wrench.and.screwdriver")
                    }
                }

                Section(footer: helpFooter) {
                    NavigationLink {
                        Help()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }

                #if !os(tvOS)
                    Section(header: Text("Contact"), footer: versionString) {
                        Link(destination: Self.discordURL) {
                            HStack {
                                Image("Discord")
                                    .resizable()
                                    .renderingMode(.template)
                                    .frame(maxWidth: 30, maxHeight: 30)

                                Text("Discord Server")
                            }
                        }

                        Link(destination: Self.matrixURL) {
                            HStack {
                                Image("Matrix")
                                    .resizable()
                                    .renderingMode(.template)
                                    .frame(maxWidth: 30, maxHeight: 30)
                                Text("Matrix Chat")
                            }
                        }
                    }
                #endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
    #endif

    #if os(macOS)
        private var windowHeight: Double {
            switch selection {
            case .browsing:
                return 390
            case .player:
                return 390
            case .history:
                return 480
            case .sponsorBlock:
                return 660
            case .locations:
                return 480
            case .advanced:
                return 320
            case .help:
                return 600
            }
        }
    #endif

    var helpFooter: some View {
        #if os(tvOS)
            versionString
        #else
            EmptyView()
        #endif
    }

    private var versionString: some View {
        Text("Yattee \(YatteeApp.version) (build \(YatteeApp.build))")
        #if os(tvOS)
            .foregroundColor(.secondary)
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
