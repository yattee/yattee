import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct FavoriteItemView: View {
    let item: FavoriteItem

    @StateObject private var store = FavoriteResourceObserver()

    @Default(.favorites) private var favorites
    @Binding private var dragging: FavoriteItem?

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlaylistsModel> private var playlists

    private var favoritesModel = FavoritesModel.shared

    init(
        item: FavoriteItem,
        dragging: Binding<FavoriteItem?>
    ) {
        self.item = item
        _dragging = dragging
    }

    var body: some View {
        Group {
            if isVisible {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.title3.bold())
                        .foregroundColor(.secondary)
                        .contextMenu {
                            Button {
                                favoritesModel.remove(item)
                            } label: {
                                Label("Remove from Favorites", systemImage: "trash")
                            }
                        }
                        .contentShape(Rectangle())
                    #if os(tvOS)
                        .padding(.leading, 40)
                    #else
                        .padding(.leading, 15)
                    #endif

                    HorizontalCells(items: store.contentItems)
                }

                .contentShape(Rectangle())
                .opacity(dragging?.id == item.id ? 0.5 : 1)
                .onAppear {
                    resource?.addObserver(store)
                    resource?.load()
                }
                #if !os(tvOS)
                .onDrag {
                    dragging = item
                    return NSItemProvider(object: item.id as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: DropFavorite(item: item, favorites: $favorites, current: $dragging)
                )
                #endif
            }
        }
        .onChange(of: accounts.current) { _ in
            resource?.addObserver(store)
            resource?.load()
        }
    }

    private var isVisible: Bool {
        switch item.section {
        case .subscriptions:
            return accounts.app.supportsSubscriptions && accounts.signedIn
        case .popular:
            return accounts.app.supportsPopular
        default:
            return true
        }
    }

    private var resource: Resource? {
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
            let trendingCategory = category.isNil ? nil : TrendingCategory(rawValue: category!)

            return accounts.api.trending(country: trendingCountry, category: trendingCategory)

        case let .channel(id, _):
            return accounts.api.channelVideos(id)

        case let .channelPlaylist(id, _):
            return accounts.api.channelPlaylist(id)

        case let .playlist(id):
            return accounts.api.playlist(id)

        case let .searchQuery(text, date, duration, order):
            return accounts.api.search(.init(
                query: text,
                sortBy: SearchQuery.SortOrder(rawValue: order) ?? .uploadDate,
                date: SearchQuery.Date(rawValue: date),
                duration: SearchQuery.Duration(rawValue: duration)
            ))
        }

        return nil
    }

    private var label: String {
        if case let .playlist(id) = item.section {
            return playlists.find(id: id)?.title ?? "Playlist"
        }

        return item.section.label
    }
}
