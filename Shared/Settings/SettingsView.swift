import Defaults
import Foundation
import SwiftUI
struct SettingsView: View {
    static let matrixURL = URL(string: "https://tinyurl.com/matrix-yattee")!
    static let discordURL = URL(string: "https://yattee.stream/discord")!

    #if os(macOS)
        private enum Tabs: Hashable {
            case browsing, player, controls, quality, history, sponsorBlock, locations, advanced, help
        }

        @State private var selection: Tabs = .browsing
    #endif

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.presentationMode) private var presentationMode
    #endif

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var model = SettingsModel.shared

    @Default(.instances) private var instances

    var body: some View {
        settings
            .alert(isPresented: $model.presentingAlert) { model.alert }
    }

    var settings: some View {
        #if os(macOS)
            TabView(selection: $selection) {
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
                    PlayerControlsSettings()
                }
                .tabItem {
                    Label("Controls", systemImage: "hand.tap")
                }
                .tag(Tabs.controls)

                Form {
                    QualitySettings()
                }
                .tabItem {
                    Label("Quality", systemImage: "4k.tv")
                }
                .tag(Tabs.quality)

                Form {
                    HistorySettings()
                }
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tabs.history)

                if !accounts.isEmpty {
                    Form {
                        SponsorBlockSettings()
                    }
                    .tabItem {
                        Label("SponsorBlock", systemImage: "dollarsign.circle")
                    }
                    .tag(Tabs.sponsorBlock)
                }
                Form {
                    LocationsSettings()
                }
                .tabItem {
                    Label("Locations", systemImage: "globe")
                }
                .tag(Tabs.locations)

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
            .frame(width: 650, height: windowHeight)
        #else
            NavigationView {
                settingsList
                    .navigationTitle("Settings")
            }
        #endif
    }

    #if !os(macOS)
        var settingsList: some View {
            List {
                #if os(tvOS)
                    if !accounts.isEmpty {
                        Section(header: Text("Current Location")) {
                            NavigationLink(destination: AccountsView()) {
                                if let account = accounts.current {
                                    Text(account.isPublic ? account.description : "\(account.description) — \(account.instance.shortDescription)")
                                } else {
                                    Text("Not Selected")
                                }
                            }
                        }
                        Divider()
                    }
                #endif

                Section {
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
                        PlayerControlsSettings()
                    } label: {
                        Label("Controls", systemImage: "hand.tap")
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
                        LocationsSettings()
                    } label: {
                        Label("Locations", systemImage: "globe")
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
                return 820
            case .player:
                return 450
            case .controls:
                return 800
            case .quality:
                return 420
            case .history:
                return 500
            case .sponsorBlock:
                return 700
            case .locations:
                return 600
            case .advanced:
                return 380
            case .help:
                return 650
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
