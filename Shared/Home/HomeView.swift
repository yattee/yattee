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

    var favoritesObserver: Any?

    #if !os(tvOS)
        @Default(.favorites) private var favorites
    #endif
    @Default(.homeHistoryItems) private var homeHistoryItems
    @Default(.showFavoritesInHome) private var showFavoritesInHome
    @Default(.showOpenActionsInHome) private var showOpenActionsInHome

    private var navigation: NavigationModel { .shared }

    var body: some View {
        BrowserPlayerControls {
            ScrollView(.vertical, showsIndicators: false) {
                if showOpenActionsInHome {
                    HStack {
                        #if os(tvOS)
                            OpenVideosButton(text: "Open Video", imageSystemName: "globe") {
                                NavigationModel.shared.presentingOpenVideos = true
                            }
                            .frame(maxWidth: 600)
                        #else
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
                }

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
                            #if os(iOS)
                            .padding(.top, item == first && RefreshControl.navigationBarTitleDisplayMode == .inline ? 10 : 0)
                            #endif
                        }
                    #endif
                }

                if homeHistoryItems > 0 {
                    VStack {
                        Text("History")

                        #if os(tvOS)
                            .padding(.horizontal, 40)
                        #else
                            .padding(.horizontal, 15)
                        #endif
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(.secondary)

                        HistoryView(limit: homeHistoryItems)
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
                .onDrop(of: [UTType.text], delegate: DropFavoriteOutside(current: $dragging))
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
}

struct Favorites_Previews: PreviewProvider {
    static var previews: some View {
        TabView {
            HomeView()
//                .overlay(VideoPlayerView().injectFixtureEnvironmentObjects())
                .injectFixtureEnvironmentObjects()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
        }
    }
}
