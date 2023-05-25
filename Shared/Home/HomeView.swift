import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject private var accounts = AccountsModel.shared

    @State private var presentingHomeSettings = false
    @State private var favoritesChanged = false

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>
    @State private var historyID = UUID()
    #if os(iOS)
        @State private var recentDocumentsID = UUID()
    #endif

    var favoritesObserver: Any?

    #if !os(tvOS)
        @Default(.favorites) private var favorites
        @Default(.widgetsSettings) private var widgetsSettings
    #endif
    @Default(.homeHistoryItems) private var homeHistoryItems
    @Default(.showFavoritesInHome) private var showFavoritesInHome
    @Default(.showOpenActionsInHome) private var showOpenActionsInHome
    @Default(.showQueueInHome) private var showQueueInHome

    private var navigation: NavigationModel { .shared }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                HStack {
                    #if os(tvOS)
                        Group {
                            if showOpenActionsInHome {
                                AccentButton(text: "Open Video", imageSystemName: "globe") {
                                    NavigationModel.shared.presentingOpenVideos = true
                                }
                            }
                            AccentButton(text: "Locations", imageSystemName: "globe") {
                                NavigationModel.shared.presentingAccounts = true
                            }

                            AccentButton(text: "Settings", imageSystemName: "gear") {
                                NavigationModel.shared.presentingSettings = true
                            }
                        }
                    #else
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
                    #endif
                }

                #if os(tvOS)
                    HStack {
                        Spacer()
                        HideWatchedButtons()
                        HideShortsButtons()
                        HomeSettingsButton()
                    }
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
                            FavoriteItemView(item: item)
                        }
                    #else
                        ForEach(favorites) { item in
                            FavoriteItemView(item: item)
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
            Defaults.observe(.favorites) { _ in
                favoritesChanged.toggle()
            }
            .tieToLifetime(of: accounts)
            Defaults.observe(.widgetsSettings) { _ in
                favoritesChanged.toggle()
            }
            .tieToLifetime(of: accounts)
        }

        .redrawOn(change: favoritesChanged)

        #if os(tvOS)
            .edgesIgnoringSafeArea(.horizontal)
        #else
            .navigationTitle("Home")
        #endif
        #if os(macOS)
        .background(Color.secondaryBackground)
        .frame(minWidth: 360)
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
