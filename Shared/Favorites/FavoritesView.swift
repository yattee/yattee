import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct FavoritesView: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlaylistsModel> private var playlists

    @State private var dragging: FavoriteItem?
    @State private var presentingEditFavorites = false

    @State private var favoritesChanged = false

    var favoritesObserver: Any?

    #if !os(tvOS)
        @Default(.favorites) private var favorites
    #endif

    var body: some View {
        PlayerControlsView {
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
                        Color.clear.padding(.bottom, 30)
                    #endif
                }
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
                .navigationTitle("Favorites")
            #endif
            #if os(macOS)
            .background(Color.secondaryBackground)
            .frame(minWidth: 360)
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
            #endif
        }
    }
}

struct Favorites_Previews: PreviewProvider {
    static var previews: some View {
        FavoritesView()
            .injectFixtureEnvironmentObjects()
    }
}
