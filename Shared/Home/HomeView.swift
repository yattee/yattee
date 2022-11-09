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

    private var navigation: NavigationModel { .shared }

    var body: some View {
        BrowserPlayerControls {
            ScrollView(.vertical, showsIndicators: false) {
                if !accounts.current.isNil {
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

                    HistoryView(limit: 100)
                }

                #if os(tvOS)
                    HStack {
                        Button {
                            navigation.presentingOpenVideos = true
                        } label: {
                            Label("Open Videos...", systemImage: "folder")
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                #else
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
