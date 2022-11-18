import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlaylistsModel> private var playlists

    @State private var dragging: FavoriteItem?
    @State private var presentingEditFavorites = false

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
    #endif
    #if os(iOS)
        @Default(.homeRecentDocumentsItems) private var homeRecentDocumentsItems
    #endif
    @Default(.homeHistoryItems) private var homeHistoryItems
    @Default(.showFavoritesInHome) private var showFavoritesInHome
    @Default(.showOpenActionsInHome) private var showOpenActionsInHome

    private var navigation: NavigationModel { .shared }

    var body: some View {
        BrowserPlayerControls {
            ScrollView(.vertical, showsIndicators: false) {
                HStack {
                    #if os(tvOS)
                        Group {
                            if showOpenActionsInHome {
                                OpenVideosButton(text: "Open Video", imageSystemName: "globe") {
                                    NavigationModel.shared.presentingOpenVideos = true
                                }
                            }
                            OpenVideosButton(text: "Settings", imageSystemName: "gear") {
                                NavigationModel.shared.presentingSettings = true
                            }
                        }

                    #else
                        if showOpenActionsInHome {
                            OpenVideosButton(text: "Files", imageSystemName: "folder") {
                                NavigationModel.shared.presentingFileImporter = true
                            }
                            OpenVideosButton(text: "Paste", imageSystemName: "doc.on.clipboard.fill") {
                                OpenVideosModel.shared.openURLsFromClipboard(playbackMode: .playNow)
                            }
                            OpenVideosButton(imageSystemName: "ellipsis") {
                                NavigationModel.shared.presentingOpenVideos = true
                            }
                            .frame(maxWidth: 40)
                        }
                    #endif
                }
                #if os(iOS)
                .padding(.top, RefreshControl.navigationBarTitleDisplayMode == .inline ? 15 : 0)
                #else
                .padding(.top, 15)
                #endif
                #if os(tvOS)
                .padding(.horizontal, 40)
                #else
                .padding(.horizontal, 15)
                #endif

                if !accounts.current.isNil, showFavoritesInHome {
                    #if os(tvOS)
                        ForEach(Defaults[.favorites]) { item in
                            FavoriteItemView(item: item, dragging: $dragging)
                        }
                    #else
                        #if os(iOS)
                            let first = favorites.first
                        #endif
                        ForEach(favorites) { item in
                            FavoriteItemView(item: item, dragging: $dragging)
                            #if os(macOS)
                                .workaroundForVerticalScrollingBug()
                            #endif
                        }
                    #endif
                }

                if homeRecentDocumentsItems > 0 {
                    VStack {
                        HStack {
                            sectionLabel("Recent Documents")

                            Spacer()

                            Button {
                                recentDocumentsID = UUID()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.headline)
                                    .labelStyle(.iconOnly)
                                    .foregroundColor(.secondary)
                            }
                        }

                        RecentDocumentsView(limit: homeRecentDocumentsItems)
                            .id(recentDocumentsID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if homeHistoryItems > 0 {
                    VStack {
                        HStack {
                            sectionLabel("History")
                            Spacer()
                            Button {
                                navigation.presentAlert(
                                    Alert(
                                        title: Text("Are you sure you want to clear history of watched videos?"),
                                        message: Text("It cannot be reverted"),
                                        primaryButton: .destructive(Text("Clear All")) {
                                            PlayerModel.shared.removeHistory()
                                            historyID = UUID()
                                        },
                                        secondaryButton: .cancel()
                                    )
                                )
                            } label: {
                                Label("Clear History", systemImage: "trash")
                                    .font(.headline)
                                    .labelStyle(.iconOnly)
                                    .foregroundColor(.secondary)
                            }
                        }

                        .frame(maxWidth: .infinity, alignment: .leading)

                        HistoryView(limit: homeHistoryItems)
                            .id(historyID)
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
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
            #endif
            #if !os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                favoritesChanged.toggle()
            }
            #endif
        }
    }

    func sectionLabel(_ label: String) -> some View {
        Text(label)
        #if os(tvOS)
            .padding(.horizontal, 40)
        #else
            .padding(.horizontal, 15)
        #endif
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.secondary)
    }
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            HomeView()
                .injectFixtureEnvironmentObjects()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
        }
    }
}
