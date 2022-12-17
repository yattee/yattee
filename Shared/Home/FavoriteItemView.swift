import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct FavoriteItemView: View {
    var item: FavoriteItem

    @Environment(\.navigationStyle) private var navigationStyle
    @StateObject private var store = FavoriteResourceObserver()

    @Default(.favorites) private var favorites

    @ObservedObject private var accounts = AccountsModel.shared
    private var playlists = PlaylistsModel.shared
    private var favoritesModel = FavoritesModel.shared
    private var navigation = NavigationModel.shared

    init(item: FavoriteItem) {
        self.item = item
    }

    var body: some View {
        Group {
            if isVisible {
                VStack(alignment: .leading, spacing: 2) {
                    itemControl
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
                        .environment(\.inChannelView, inChannelView)
                }
                .contentShape(Rectangle())
                .onAppear {
                    resource?.addObserver(store)
                    loadCacheAndResource()
                }
            }
        }
        .onChange(of: accounts.current) { _ in
            resource?.addObserver(store)
            loadCacheAndResource(force: true)
        }
    }

    func loadCacheAndResource(force: Bool = false) {
        guard var resource else { return }

        var onSuccess: (Entity<Any>) -> Void = { _ in }
        var contentItems = [ContentItem]()

        switch item.section {
        case .subscriptions:
            let feed = FeedCacheModel.shared.retrieveFeed(account: accounts.current)
            contentItems = ContentItem.array(of: feed)

            onSuccess = { response in
                if let videos: [Video] = response.typedContent() {
                    FeedCacheModel.shared.storeFeed(account: accounts.current, videos: videos)
                }
            }
        case let .channel(_, id, name):
            let channel = Channel(app: .invidious, id: id, name: name)
            if let cache = ChannelsCacheModel.shared.retrieve(channel.cacheKey) {
                contentItems = ContentItem.array(of: cache.videos)
            }

            onSuccess = { response in
                if let channel: Channel = response.typedContent() {
                    ChannelsCacheModel.shared.store(channel)
                }
            }
        case let .channelPlaylist(_, id, title):
            if let cache = ChannelPlaylistsCacheModel.shared.retrievePlaylist(.init(id: id, title: title)),
               !cache.videos.isEmpty
            {
                contentItems = ContentItem.array(of: cache.videos)
            }

            onSuccess = { response in
                if let playlist: ChannelPlaylist = response.typedContent() {
                    ChannelPlaylistsCacheModel.shared.storePlaylist(playlist: playlist)
                }
            }
        case let .playlist(_, id):
            let playlists = PlaylistsCacheModel.shared.retrievePlaylists(account: accounts.current)

            if let playlist = playlists.first(where: { $0.id == id }) {
                contentItems = ContentItem.array(of: playlist.videos)
            }
        default:
            contentItems = []
        }

        if !contentItems.isEmpty {
            store.contentItems = contentItems
        }

        if force {
            resource.load().onSuccess(onSuccess)
        } else {
            resource.loadIfNeeded()?.onSuccess(onSuccess)
        }
    }

    var inChannelView: Bool {
        switch item.section {
        case .channel:
            return true
        default:
            return false
        }
    }

    var itemControl: some View {
        VStack {
            #if os(tvOS)
                itemButton
            #else
                if itemIsNavigationLink {
                    itemNavigationLink
                } else {
                    itemButton
                }
            #endif
        }
    }

    var itemButton: some View {
        Button(action: itemButtonAction) {
            itemLabel
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }

    var itemNavigationLink: some View {
        NavigationLink(destination: itemNavigationLinkDestination) {
            itemLabel
        }
    }

    var itemIsNavigationLink: Bool {
        switch item.section {
        case .channel:
            return navigationStyle == .tab
        case .channelPlaylist:
            return navigationStyle == .tab
        case .playlist:
            return navigationStyle == .tab
        case .subscriptions:
            return navigationStyle == .tab
        case .popular:
            return navigationStyle == .tab
        default:
            return false
        }
    }

    @ViewBuilder var itemNavigationLinkDestination: some View {
        Group {
            switch item.section {
            case let .channel(_, id, name):
                ChannelVideosView(channel: .init(app: .invidious, id: id, name: name))
            case let .channelPlaylist(_, id, title):
                ChannelPlaylistView(playlist: .init(id: id, title: title))
            case let .playlist(_, id):
                ChannelPlaylistView(playlist: .init(id: id, title: label))
            case .subscriptions:
                SubscriptionsView()
            case .popular:
                PopularView()
            default:
                EmptyView()
            }
        }
        .modifier(PlayerOverlayModifier())
    }

    func itemButtonAction() {
        switch item.section {
        case let .channel(_, id, name):
            NavigationModel.shared.openChannel(.init(app: .invidious, id: id, name: name), navigationStyle: navigationStyle)
        case let .channelPlaylist(_, id, title):
            NavigationModel.shared.openChannelPlaylist(.init(id: id, title: title), navigationStyle: navigationStyle)
        case .subscriptions:
            navigation.hideViewsAboveBrowser()
            navigation.tabSelection = .subscriptions
        case .popular:
            navigation.hideViewsAboveBrowser()
            navigation.tabSelection = .popular
        case let .trending(country, category):
            navigation.hideViewsAboveBrowser()
            Defaults[.trendingCountry] = .init(rawValue: country) ?? .us
            Defaults[.trendingCategory] = category.isNil ? .default : (.init(rawValue: category!) ?? .default)
            navigation.tabSelection = .trending
        case let .searchQuery(text, _, _, _):
            navigation.hideViewsAboveBrowser()
            navigation.openSearchQuery(text)
        case let .playlist(_, id):
            navigation.tabSelection = .playlist(id)
        }
    }

    var itemLabel: some View {
        HStack {
            Text(label)
                .font(.title3.bold())
            Image(systemName: "chevron.right")
                .imageScale(.small)
        }
        .lineLimit(1)
        .padding(.trailing, 10)
    }

    private var isVisible: Bool {
        switch item.section {
        case .subscriptions:
            return accounts.app.supportsSubscriptions && !accounts.isEmpty && !accounts.current.anonymous
        case .popular:
            return accounts.app.supportsPopular
        case let .channel(appType, _, _):
            guard let appType = VideosApp.AppType(rawValue: appType) else { return false }
            return accounts.app.appType == appType
        case let .channelPlaylist(appType, _, _):
            guard let appType = VideosApp.AppType(rawValue: appType) else { return false }
            return accounts.app.appType == appType
        case let .playlist(accountID, _):
            return accounts.current?.id == accountID
        default:
            return true
        }
    }

    private var resource: Resource? {
        switch item.section {
        case .subscriptions:
            if accounts.app.supportsSubscriptions {
                return accounts.api.feed(1)
            }

        case .popular:
            if accounts.app.supportsPopular {
                return accounts.api.popular
            }

        case let .trending(country, category):
            let trendingCountry = Country(rawValue: country)!
            let trendingCategory = category.isNil ? nil : TrendingCategory(rawValue: category!)

            return accounts.api.trending(country: trendingCountry, category: trendingCategory)

        case let .channel(_, id, _):
            return accounts.api.channelVideos(id)

        case let .channelPlaylist(_, id, _):
            return accounts.api.channelPlaylist(id)

        case let .playlist(_, id):
            return accounts.api.playlist(id)

        case let .searchQuery(text, date, duration, order):
            return accounts.api.search(
                .init(
                    query: text,
                    sortBy: SearchQuery.SortOrder(rawValue: order) ?? .uploadDate,
                    date: SearchQuery.Date(rawValue: date),
                    duration: SearchQuery.Duration(rawValue: duration)
                ),
                page: nil
            )
        }

        return nil
    }

    private var label: String {
        switch item.section {
        case let .playlist(_, id):
            return playlists.find(id: id)?.title ?? "Playlist".localized()
        default:
            return item.section.label.localized()
        }
    }
}

struct FavoriteItemView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            VStack {
                FavoriteItemView(item: .init(section: .channel("peerTube", "a", "Search: resistance body upper band workout")))
                    .environment(\.navigationStyle, .tab)
                FavoriteItemView(item: .init(section: .channel("peerTube", "a", "Marques")))
                    .environment(\.navigationStyle, .sidebar)
            }
        }
    }
}
