import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct FavoritesView: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlaylistsModel> private var playlists

    @State private var dragging: FavoriteItem?
    @State private var presentingEditFavorites = false

    @Default(.favorites) private var favorites

    var body: some View {
        PlayerControlsView {
            ScrollView(.vertical, showsIndicators: false) {
                if !accounts.current.isNil {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(favorites) { item in
                            VStack {
                                if let resource = resource(item) {
                                    FavoriteItemView(item: item, resource: resource, favorites: $favorites, dragging: $dragging)
                                }
                            }
                        }
                    }

                    #if os(tvOS)
                        Button {
                            presentingEditFavorites = true
                        } label: {
                            Text("Edit Favorites...")
                        }
                    #endif
                }
            }
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

    func resource(_ item: FavoriteItem) -> Resource? {
        switch item.section {
        case .subscriptions:
            if accounts.app.supportsSubscriptions {
                return accounts.api.feed
            }

        case .popular:
            if accounts.app.supportsPopular {
                return accounts.api.popular
            }

        case let .trending(country, category):
            let trendingCountry = Country(rawValue: country)!
            let trendingCategory = category.isNil ? nil : TrendingCategory(rawValue: category!)!

            return accounts.api.trending(country: trendingCountry, category: trendingCategory)

        case let .channel(id, _):
            return accounts.api.channelVideos(id)

        case let .channelPlaylist(id, _):
            return accounts.api.channelPlaylist(id)

        case let .playlist(id):
            return accounts.api.playlist(id)
        }

        return nil
    }
}

struct Favorites_Previews: PreviewProvider {
    static var previews: some View {
        FavoritesView()
            .injectFixtureEnvironmentObjects()
    }
}
