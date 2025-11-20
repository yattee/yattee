import Defaults
import Siesta
import SwiftUI
import UniformTypeIdentifiers

struct FavoriteItemView: View {
    var item: FavoriteItem
    @Binding var favoritesChanged: Bool

    @Environment(\.navigationStyle) private var navigationStyle
    @StateObject private var store = FavoriteResourceObserver()

    @ObservedObject private var accounts = AccountsModel.shared
    private var playlists = PlaylistsModel.shared
    private var favoritesModel = FavoritesModel.shared
    private var navigation = NavigationModel.shared
    @ObservedObject private var player = PlayerModel.shared
    @ObservedObject private var watchModel = WatchModel.shared

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>
    @State private var visibleWatches = [Watch]()

    @Default(.hideShorts) private var hideShorts
    @Default(.hideWatched) private var hideWatched
    @Default(.widgetsSettings) private var widgetsSettings
    @Default(.visibleSections) private var visibleSections

    init(item: FavoriteItem, favoritesChanged: Binding<Bool>) {
        self.item = item
        _favoritesChanged = favoritesChanged
    }

    var body: some View {
        Group {
            if isVisible {
                VStack(alignment: .leading, spacing: 0) {
                    itemControl
                        .contextMenu { contextMenu }
                        .contentShape(Rectangle())
                    #if os(tvOS)
                        .padding(.leading, 40)
                    #else
                        .padding(.leading, 15)
                    #endif

                    if limitedItems.isEmpty, !(resource?.isLoading ?? false) {
                        VStack(alignment: .leading) {
                            Text(emptyItemsText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(.secondary)

                            if (FeatureFlags.hideShortsEnabled && hideShorts) || hideWatched {
                                AccentButton(text: "Disable filters", maxWidth: nil, verticalPadding: 0, minHeight: 30) {
                                    if FeatureFlags.hideShortsEnabled {
                                        hideShorts = false
                                    }
                                    hideWatched = false
                                    reloadVisibleWatches()
                                }
                            }
                        }
                        .padding(.vertical, 10)
                        #if os(tvOS)
                            .padding(.horizontal, 40)
                        #else
                            .padding(.horizontal, 15)
                        #endif
                            .frame(height: expectedContentHeight)
                    } else {
                        ZStack(alignment: .topLeading) {
                            // Reserve space immediately to prevent layout shift
                            Color.clear
                                .frame(height: expectedContentHeight)

                            // Actual content renders within the reserved space
                            Group {
                                switch widgetListingStyle {
                                case .horizontalCells:
                                    HorizontalCells(items: limitedItems)
                                case .list:
                                    ListView(items: limitedItems)
                                        .padding(.vertical, 10)
                                    #if os(tvOS)
                                        .padding(.leading, 40)
                                    #else
                                        .padding(.horizontal, 15)
                                    #endif
                                }
                            }
                            .environment(\.inChannelView, inChannelView)
                        }
                        .animation(nil, value: store.contentItems.count)
                    }
                }
                .animation(nil, value: store.contentItems.count)
                .contentShape(Rectangle())
                .onAppear {
                    if item.section == .history {
                        reloadVisibleWatches()
                    } else {
                        resource?.addObserver(store)
                        DispatchQueue.main.async {
                            self.loadCacheAndResource()
                        }
                    }
                }
                .onDisappear {
                    resource?.removeObservers(ownedBy: store)
                }
                .onChange(of: player.currentVideo) { _ in if !player.presentingPlayer { reloadVisibleWatches() } }
                .onChange(of: hideShorts) { _ in if !player.presentingPlayer && FeatureFlags.hideShortsEnabled { reloadVisibleWatches() } }
                .onChange(of: hideWatched) { _ in if !player.presentingPlayer { reloadVisibleWatches() } }
                // Delay is necessary to update the list with the new items.
                .onChange(of: favoritesChanged) { _ in if !player.presentingPlayer { Delay.by(1.0) { reloadVisibleWatches() } } }
                .onChange(of: player.presentingPlayer) { _ in
                    if player.presentingPlayer {
                        resource?.removeObservers(ownedBy: store)
                    } else {
                        resource?.addObserver(store)
                    }
                }
            }
        }
        .id(watchModel.historyToken)
        .onChange(of: accounts.current) { _ in
            DispatchQueue.main.async {
                loadCacheAndResource(force: true)
            }
        }
        .onChange(of: watchModel.historyToken) { _ in
            if !player.presentingPlayer {
                reloadVisibleWatches()
            }
        }
    }

    var emptyItemsText: String {
        var filterText = ""
        if FeatureFlags.hideShortsEnabled && hideShorts && hideWatched {
            filterText = "(watched and shorts hidden)"
        } else if FeatureFlags.hideShortsEnabled && hideShorts {
            filterText = "(shorts hidden)"
        } else if hideWatched {
            filterText = "(watched hidden)"
        }

        return "No videos to show".localized() + " " + filterText.localized()
    }

    var contextMenu: some View {
        Group {
            if item.section == .history {
                Section {
                    Button {
                        navigation.presentAlert(
                            Alert(
                                title: Text("Are you sure you want to clear history of watched videos?"),
                                message: Text("This cannot be reverted"),
                                primaryButton: .destructive(Text("Clear All")) {
                                    PlayerModel.shared.removeHistory()
                                    visibleWatches = []
                                },
                                secondaryButton: .cancel()
                            )
                        )
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                }
            }

            Button {
                favoritesModel.remove(item)
            } label: {
                Label("Remove from Favorites", systemImage: "trash")
            }

            #if os(tvOS)
                Button("Cancel", role: .cancel) {}
            #endif
        }
    }

    func reloadVisibleWatches() {
        DispatchQueue.main.async {
            guard item.section == .history else { return }

            visibleWatches = []

            let watches = Array(
                watches
                    .filter { $0.videoID != player.currentVideo?.videoID && itemVisible(.init(video: $0.video)) }
                    .prefix(favoritesModel.limit(item))
            )
            let last = watches.last

            for watch in watches {
                player.loadHistoryVideoDetails(watch) {
                    guard let video = player.historyVideo(watch.videoID), itemVisible(.init(video: video)) else { return }
                    visibleWatches.append(watch)

                    if watch == last {
                        visibleWatches.sort { $0.watchedAt ?? Date() > $1.watchedAt ?? Date() }
                    }
                }
            }
        }
    }

    var limitedItems: [ContentItem] {
        let limit = favoritesModel.limit(item)
        if item.section == .history {
            return Array(visibleWatches.prefix(limit).map { ContentItem(video: player.historyVideo($0.videoID) ?? $0.video) })
        }
        var result = [ContentItem]()
        result.reserveCapacity(min(store.contentItems.count, limit))
        for contentItem in store.contentItems where itemVisible(contentItem) {
            result.append(contentItem)
            if result.count >= limit {
                break
            }
        }
        return result
    }

    func itemVisible(_ item: ContentItem) -> Bool {
        if hideWatched, watch(item)?.finished ?? false {
            return false
        }

        guard FeatureFlags.hideShortsEnabled, hideShorts, item.contentType == .video, let video = item.video else {
            return true
        }

        return !video.short
    }

    func watch(_ item: ContentItem) -> Watch? {
        guard let id = item.video?.videoID else { return nil }
        return watches.first { $0.videoID == id }
    }

    var widgetListingStyle: WidgetListingStyle {
        favoritesModel.listingStyle(item)
    }

    var expectedContentHeight: Double {
        switch widgetListingStyle {
        case .horizontalCells:
            #if os(tvOS)
                return 600
            #else
                return 290
            #endif
        case .list:
            // Approximate height for list view items
            let itemCount = favoritesModel.limit(item)
            let itemHeight: Double = 70 // Approximate height per item
            let padding: Double = 20
            return Double(itemCount) * itemHeight + padding
        }
    }

    func loadCacheAndResource(force: Bool = false) {
        guard let resource else { return }

        var onSuccess: (Entity<Any>) -> Void = { _ in }
        var contentItems = [ContentItem]()

        switch item.section {
        case .subscriptions:
            let feed = FeedCacheModel.shared.retrieveFeed(account: accounts.current)
            contentItems = ContentItem.array(of: feed)

            onSuccess = { response in
                if let videos: [Video] = response.typedContent() {
                    FeedCacheModel.shared.storeFeed(account: accounts.current, videos: videos)
                    DispatchQueue.main.async {
                        store.contentItems = contentItems
                    }
                }
            }
        case let .channel(_, id, name):
            var channel = Channel(app: .invidious, id: id, name: name)
            if let cache = ChannelsCacheModel.shared.retrieve(channel.cacheKey),
               let cacheChannel = cache.channel,
               !cacheChannel.videos.isEmpty
            {
                contentItems = ContentItem.array(of: cacheChannel.videos)
            }

            onSuccess = { response in
                DispatchQueue.main.async {
                    if let channel: Channel = response.typedContent() {
                        ChannelsCacheModel.shared.store(channel)
                        store.contentItems = ContentItem.array(of: channel.videos)
                    } else if let videos: [Video] = response.typedContent() {
                        channel.videos = videos
                        ChannelsCacheModel.shared.store(channel)
                        store.contentItems = ContentItem.array(of: videos)
                    } else if let channelPage: ChannelPage = response.typedContent() {
                        if let channel = channelPage.channel {
                            ChannelsCacheModel.shared.store(channel)
                        }

                        store.contentItems = channelPage.results
                    }
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
                    DispatchQueue.main.async {
                        store.contentItems = contentItems
                    }
                }
            }
        case let .playlist(_, id):
            let playlists = PlaylistsCacheModel.shared.retrievePlaylists(account: accounts.current)

            if let playlist = playlists.first(where: { $0.id == id }) {
                contentItems = ContentItem.array(of: playlist.videos)
            }

            DispatchQueue.main.async {
                store.contentItems = contentItems
            }
        default:
            contentItems = []

            DispatchQueue.main.async {
                store.contentItems = contentItems
            }
        }

        if force {
            resource.load().onSuccess(onSuccess)
        } else {
            resource.loadIfNeeded()?.onSuccess(onSuccess)
        }
    }

    var navigatableItem: Bool {
        switch item.section {
        case .history:
            return false
        case .trending:
            return visibleSections.contains(.trending)
        case .subscriptions:
            return visibleSections.contains(.subscriptions) && accounts.signedIn
        case .popular:
            return visibleSections.contains(.popular) && accounts.app.supportsPopular
        default:
            return true
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
            if navigatableItem {
                #if os(tvOS)
                    itemButton
                #else
                    if itemIsNavigationLink {
                        itemNavigationLink
                    } else {
                        itemButton
                    }
                #endif
            } else {
                itemLabel
                    .foregroundColor(.secondary)
            }
        }
    }

    var itemButton: some View {
        Button(action: itemButtonAction) {
            itemLabel
                .foregroundColor(.accentColor)
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
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
        case .history:
            print("should not happen")
        }
    }

    var itemLabel: some View {
        HStack {
            Text(label)
                .font(.title3.bold())
            if navigatableItem {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
            }
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
        case .history:
            return nil

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
    struct PreviewWrapper: View {
        @State private var favoritesChanged = false

        var body: some View {
            NavigationView {
                VStack {
                    FavoriteItemView(item: .init(section: .channel("peerTube", "a", "Search: resistance body upper band workout")), favoritesChanged: $favoritesChanged)
                        .environment(\.navigationStyle, .tab)
                    FavoriteItemView(item: .init(section: .channel("peerTube", "a", "Marques")), favoritesChanged: $favoritesChanged)
                        .environment(\.navigationStyle, .sidebar)
                }
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
