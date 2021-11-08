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
                        ForEach(favorites) { item in
                            FavoriteItemView(item: item, dragging: $dragging)
                        }
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
                .sheet(isPresented: $presentingEditFavorites) {
                    EditFavorites()
                }
                .edgesIgnoringSafeArea(.horizontal)
            #else
                .onDrop(of: [UTType.text], delegate: DropFavoriteOutside(current: $dragging))
                .navigationTitle("Favorites")
            #endif
            #if os(macOS)
            .background()
            .frame(minWidth: 360)
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
