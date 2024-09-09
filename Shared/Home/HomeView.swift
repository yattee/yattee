import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var player = PlayerModel.shared

    @State private var presentingHomeSettings = false
    @State private var favoritesChanged = false
    @State private var updateTask: Task<Void, Never>?

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>
    @State private var historyID = UUID()
    #if os(iOS)
        @State private var recentDocumentsID = UUID()
    #endif

    #if !os(tvOS)
        @Default(.favorites) private var favorites
        @Default(.widgetsSettings) private var widgetsSettings
    #endif
    @Default(.showFavoritesInHome) private var showFavoritesInHome
    @Default(.showOpenActionsInHome) private var showOpenActionsInHome
    @Default(.showQueueInHome) private var showQueueInHome

    private var navigation: NavigationModel { .shared }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                #if !os(tvOS)
                    HStack {
                        if showOpenActionsInHome {
                            AccentButton(text: "Files", imageSystemName: "folder") {
                                NavigationModel.shared.presentingFileImporter = true
                            }
                            AccentButton(text: "Paste", imageSystemName: "doc.on.clipboard.fill") {
                                OpenVideosModel.shared.openURLsFromClipboard(playbackMode: .playNow)
                            }
                            AccentButton(imageSystemName: "ellipsis") {
                                NavigationModel.shared.presentingOpenVideos = true
                            }
                            .frame(maxWidth: 40)
                        }
                    }
                #endif

                #if os(tvOS)
                    HStack {
                        if showOpenActionsInHome {
                            Button {
                                NavigationModel.shared.presentingOpenVideos = true
                            } label: {
                                Label("Open Video", systemImage: "globe")
                            }
                        }
                        Button {
                            NavigationModel.shared.presentingAccounts = true
                        } label: {
                            Label("Locations", systemImage: "globe")
                        }
                        Spacer()
                        HideWatchedButtons()
                        HideShortsButtons()
                        Button {
                            NavigationModel.shared.presentingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                    #if os(tvOS)
                    .font(.caption)
                    .imageScale(.small)
                    #endif
                #endif
            }
            .padding(.top, 15)
            #if os(tvOS)
                .padding(.horizontal, 40)
            #else
                .padding(.horizontal, 15)
            #endif

            if showQueueInHome {
                QueueView()
                #if os(tvOS)
                    .padding(.horizontal, 40)
                #else
                    .padding(.horizontal, 15)
                #endif
            }

            if !accounts.current.isNil, showFavoritesInHome {
                VStack(alignment: .leading) {
                    #if os(tvOS)
                        ForEach(Defaults[.favorites]) { item in
                            FavoriteItemView(item: item, favoritesChanged: $favoritesChanged)
                        }
                    #else
                        ForEach(favorites) { item in
                            FavoriteItemView(item: item, favoritesChanged: $favoritesChanged)
                            #if os(macOS)
                                .workaroundForVerticalScrollingBug()
                            #endif
                        }
                    #endif
                }
            }

            #if !os(tvOS)
                Color.clear.padding(.bottom, 60)
            #endif
        }
        .onAppear {
            Task {
                for await _ in Defaults.updates(.favorites) {
                    favoritesChanged.toggle()
                }
                for await _ in Defaults.updates(.widgetsSettings) {
                    favoritesChanged.toggle()
                }
            }
        }
        .onDisappear {
            updateTask?.cancel()
        }

        .onChange(of: player.presentingPlayer) { _ in
            if player.presentingPlayer {
                updateTask?.cancel()
            } else {
                Task {
                    for await _ in Defaults.updates(.favorites) {
                        favoritesChanged.toggle()
                    }
                    for await _ in Defaults.updates(.widgetsSettings) {
                        favoritesChanged.toggle()
                    }
                }
            }
        }

        .redrawOn(change: favoritesChanged)

        #if os(tvOS)
            .edgesIgnoringSafeArea(.horizontal)
        #else
            .navigationTitle("Home")
        #endif
        #if os(macOS)
        .background(Color.secondaryBackground)
        .frame(minWidth: Constants.contentViewMinWidth)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                HideWatchedButtons()
                HideShortsButtons()
                HomeSettingsButton()
            }
        }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                homeMenu
            }
        }
        #endif
        #if !os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            favoritesChanged.toggle()
        }
        #endif
    }

    func sectionLabel(_ label: String) -> some View {
        Text(label.localized())
        #if os(tvOS)
            .padding(.horizontal, 40)
        #else
            .padding(.horizontal, 15)
        #endif
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.secondary)
    }

    #if os(iOS)
        var homeMenu: some View {
            Menu {
                Section {
                    HideWatchedButtons()
                    HideShortsButtons()
                }
                Section {
                    Button {
                        navigation.presentingHomeSettings = true
                    } label: {
                        Label("Home Settings", systemImage: "gear")
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Home")
                        .foregroundColor(.primary)
                        .font(.headline)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .transaction { t in t.animation = nil }
            }
        }
    #endif
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            NavigationView {
                HomeView()
                    .injectFixtureEnvironmentObjects()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
            }
        }
    }
}
