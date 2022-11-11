import Defaults
import Foundation
import SwiftUI
struct SettingsView: View {
    static let matrixURL = URL(string: "https://tinyurl.com/matrix-yattee")!
    static let discordURL = URL(string: "https://yattee.stream/discord")!

    #if os(macOS)
        private enum Tabs: Hashable {
            case browsing, player, quality, history, sponsorBlock, advanced, help
        }

        @State private var selection: Tabs?
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
                if !accounts.isEmpty {
                    Form {
                        BrowsingSettings()
                    }
                    .tabItem {
                        Label("Browsing", systemImage: "list.and.film")
                    }
                    .tag(Optional(Tabs.browsing))
                }

                Form {
                    PlayerSettings()
                }
                .tabItem {
                    Label("Player", systemImage: "play.rectangle")
                }
                .tag(Optional(Tabs.player))

                Form {
                    QualitySettings()
                }
                .tabItem {
                    Label("Quality", systemImage: "4k.tv")
                }
                .tag(Optional(Tabs.quality))

                Form {
                    HistorySettings()
                }
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Optional(Tabs.history))

                if !accounts.isEmpty {
                    Form {
                        SponsorBlockSettings()
                    }
                    .tabItem {
                        Label("SponsorBlock", systemImage: "dollarsign.circle")
                    }
                    .tag(Optional(Tabs.sponsorBlock))
                }

                Group {
                    AdvancedSettings()
                }
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
                .tag(Optional(Tabs.advanced))

                Form {
                    Help()
                }
                .tabItem {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .tag(Optional(Tabs.help))
            }
            .padding(20)
            .frame(width: 600, height: windowHeight)
        #else
            NavigationView {
                settingsList
                #if os(tvOS)
                .navigationBarHidden(true)
                #endif
            }
        #endif
    }

    #if !os(macOS)
        var settingsList: some View {
            List {
                #if os(tvOS)
                    if !accounts.isEmpty {
                        AccountSelectionView()
                        Divider()
                    }
                #endif

                Section {
                    #if os(tvOS)
                        NavigationLink {
                            EditFavorites()
                        } label: {
                            Label("Favorites", systemImage: "heart.fill")
                        }
                    #endif

                    if !accounts.isEmpty {
                        NavigationLink {
                            BrowsingSettings()
                        } label: {
                            Label("Browsing", systemImage: "list.and.film")
                        }
                    }

                    NavigationLink {
                        PlayerSettings()
                    } label: {
                        Label("Player", systemImage: "play.rectangle")
                    }

                    NavigationLink {
                        QualitySettings()
                    } label: {
                        Label("Quality", systemImage: "4k.tv")
                    }

                    NavigationLink {
                        HistorySettings()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }

                    if !accounts.isEmpty {
                        NavigationLink {
                            SponsorBlockSettings()
                        } label: {
                            Label("SponsorBlock", systemImage: "dollarsign.circle")
                        }
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
            case nil:
                return accounts.isEmpty ? 680 : 400
            case .browsing:
                return 400
            case .player:
                return 680
            case .quality:
                return 420
            case .history:
                return 500
            case .sponsorBlock:
                return 700
            case .advanced:
                return 650
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
        #else
            .navigationViewStyle(.stack)
        #endif
    }
}
