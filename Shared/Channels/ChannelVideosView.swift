import Defaults
import SDWebImageSwiftUI
import Siesta
import SwiftUI

struct ChannelVideosView: View {
    var channel: Channel
    var showCloseButton = false
    var inNavigationView = true

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?
    @State private var subscriptionToggleButtonDisabled = false

    @State private var page: ChannelPage?
    @State private var contentType = Channel.ContentType.videos
    @StateObject private var contentTypeItems = Store<[ContentItem]>()

    @State private var descriptionExpanded = false
    @StateObject private var store = Store<ChannelPage>()

    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var recents = RecentsModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared
    @Namespace private var focusNamespace

    @Default(.channelPlaylistListingStyle) private var channelPlaylistListingStyle
    @Default(.expandChannelDescription) private var expandChannelDescription

    var presentedChannel: Channel? {
        store.item?.channel ?? channel
    }

    var contentItems: [ContentItem] {
        contentTypeItems.collection
    }

    var body: some View {
        let content = VStack {
            #if os(tvOS)
                VStack {
                    HStack(spacing: 24) {
                        thumbnail

                        Text(navigationTitle)
                            .font(.headline)
                            .frame(alignment: .leading)

                        Spacer()

                        subscriptionsLabel
                        viewsLabel

                        subscriptionToggleButton
                        favoriteButton
                            .labelStyle(.iconOnly)
                    }
                    contentTypePicker
                        .pickerStyle(.automatic)
                }
                .frame(maxWidth: .infinity)
            #endif

            VerticalCells(items: contentItems, edgesIgnoringSafeArea: verticalCellsEdgesIgnoringSafeArea) {
                if let description = presentedChannel?.description, !description.isEmpty {
                    Button {
                        withAnimation(.spring()) {
                            descriptionExpanded.toggle()
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            banner

                            ZStack(alignment: .topTrailing) {
                                Text(description)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(descriptionExpanded ? 50 : 1)
                                    .multilineTextAlignment(.leading)
                                #if os(tvOS)
                                    .foregroundColor(.primary)
                                #else
                                    .foregroundColor(.secondary)
                                #endif
                            }
                        }
                        .padding(.bottom, 10)
                    }
                    .buttonStyle(.plain)
                } else {
                    banner
                }
            }
            .environment(\.loadMoreContentHandler) { loadNextPage() }
            .environment(\.inChannelView, true)
            .environment(\.listingStyle, channelPlaylistListingStyle)
            #if os(tvOS)
                .prefersDefaultFocus(in: focusNamespace)
            #endif
        }

        #if !os(tvOS)
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .principal) {
                    channelMenu
                }
            #endif
            ToolbarItem(placement: .cancellationAction) {
                if showCloseButton {
                    Button {
                        withAnimation(Constants.overlayAnimation) {
                            navigation.presentingChannel = false
                            navigation.presentingChannelSheet = false
                        }
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    #if !os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
            #if os(macOS)
                ToolbarItem(placement: .navigation) {
                    thumbnail
                }
                ToolbarItemGroup {
                    if !inNavigationView {
                        Text(navigationTitle)
                            .fontWeight(.bold)
                    }

                    ListingStyleButtons(listingStyle: $channelPlaylistListingStyle)
                    HideWatchedButtons()
                    HideShortsButtons()
                    contentTypePicker
                }

                ToolbarItemGroup {
                    HStack(spacing: 3) {
                        subscriptionsLabel
                        viewsLabel
                    }

                    if let contentItem = presentedChannel?.contentItem {
                        ShareButton(contentItem: contentItem)
                    }

                    subscriptionToggleButton
                        .layoutPriority(2)

                    favoriteButton
                        .labelStyle(.iconOnly)

                    toggleWatchedButton
                        .labelStyle(.iconOnly)
                }
            #endif
        }
        #endif
        .onAppear {
            descriptionExpanded = expandChannelDescription

            if let cache = ChannelsCacheModel.shared.retrieve(channel.cacheKey), store.item.isNil {
                store.replace(cache)
            }

            load()
        }
        .onChange(of: contentType) { _ in
            load()
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(tvOS)
        .navigationTitle(navigationTitle)
        #endif

        return Group {
            if #available(macOS 12.0, *) {
                content
                #if os(tvOS)
                .background(Color.background(scheme: colorScheme))
                #endif
                #if !os(iOS)
                .focusScope(focusNamespace)
                #endif
            } else {
                content
            }
        }
    }

    var verticalCellsEdgesIgnoringSafeArea: Edge.Set {
        #if os(tvOS)
            return .horizontal
        #else
            return .init()
        #endif
    }

    @ViewBuilder var favoriteButton: some View {
        if let presentedChannel {
            FavoriteButton(item: FavoriteItem(section: .channel(accounts.app.appType.rawValue, presentedChannel.id, presentedChannel.name)))
        }
    }

    var thumbnail: some View {
        ChannelAvatarView(channel: store.item?.channel)
            .id("channel-avatar-\(store.item?.channel?.id ?? "")")
        #if os(tvOS)
            .frame(width: 80, height: 80, alignment: .trailing)
        #else
            .frame(width: 30, height: 30, alignment: .trailing)
        #endif
    }

    @ViewBuilder var banner: some View {
        if let banner = presentedChannel?.bannerURL {
            WebImage(url: banner)
                .resizable()
                .placeholder { Color.clear.frame(height: 0) }
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    var subscriptionsLabel: some View {
        Group {
            if let subscribers = store.item?.channel?.subscriptionsString {
                HStack(spacing: 0) {
                    Image(systemName: "person.2.fill")
                    Text(subscribers)
                }
            } else if store.item.isNil {
                HStack(spacing: 0) {
                    Image(systemName: "person.2.fill")
                    Text("1234")
                        .redacted(reason: .placeholder)
                }
            }
        }
        .imageScale(.small)
        .foregroundColor(.secondary)
    }

    var viewsLabel: some View {
        HStack(spacing: 0) {
            if let views = store.item?.channel?.totalViewsString {
                Image(systemName: "eye.fill")
                    .imageScale(.small)

                Text(views)
            }
        }
        .foregroundColor(.secondary)
    }

    #if !os(tvOS)
        var channelMenu: some View {
            Menu {
                if let channel = presentedChannel {
                    contentTypePicker
                    Section {
                        subscriptionToggleButton
                        FavoriteButton(item: FavoriteItem(section: .channel(accounts.app.appType.rawValue, channel.id, channel.name)))
                    }

                    if subscriptions.isSubscribing(channel.id) {
                        toggleWatchedButton
                    }

                    ListingStyleButtons(listingStyle: $channelPlaylistListingStyle)

                    Section {
                        HideWatchedButtons()
                        HideShortsButtons()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    thumbnail

                    VStack(alignment: .leading) {
                        Text(presentedChannel?.name ?? "Channel")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .layoutPriority(1)
                            .frame(minWidth: 160, alignment: .leading)

                        Group {
                            HStack(spacing: 12) {
                                subscriptionsLabel

                                if presentedChannel?.verified ?? false {
                                    Image(systemName: "checkmark.seal.fill")
                                        .imageScale(.small)
                                }

                                viewsLabel
                            }
                            .frame(minWidth: 160, alignment: .leading)
                        }
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    }

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .frame(maxWidth: 320)
            }
        }
    #endif

    private var contentTypePicker: some View {
        Picker("Content type", selection: $contentType) {
            if presentedChannel != nil {
                ForEach(Channel.ContentType.allCases, id: \.self) { type in
                    if typeAvailable(type) {
                        Label(type.description, systemImage: type.systemImage).tag(type)
                    }
                }
            }
        }
        .labelsHidden()
    }

    private func typeAvailable(_ type: Channel.ContentType) -> Bool {
        type.alwaysAvailable || (presentedChannel?.hasData(for: type) ?? false)
    }

    private var resource: Resource? {
        guard let channel = presentedChannel else { return nil }

        let tabData = channel.tabs.first { $0.contentType == contentType }?.data
        let data = contentType != .videos ? tabData : nil
        let resource = accounts.api.channel(channel.id, contentType: contentType, data: data)

        if contentType == .videos {
            resource.addObserver(store)
        }
        resource.addObserver(contentTypeItems)

        return resource
    }

    @ViewBuilder private var subscriptionToggleButton: some View {
        if let channel = presentedChannel {
            Group {
                if accounts.app.supportsSubscriptions && accounts.signedIn {
                    if subscriptions.isSubscribing(channel.id) {
                        Button {
                            subscriptionToggleButtonDisabled = true

                            subscriptions.unsubscribe(channel.id) {
                                subscriptionToggleButtonDisabled = false
                            }
                        } label: {
                            Label("Unsubscribe", systemImage: "xmark.circle")
                                .help("Unsubscribe")
                            #if os(iOS)
                                .labelStyle(.automatic)
                            #else
                                .labelStyle(.titleOnly)
                            #endif
                        }
                    } else {
                        Button {
                            subscriptionToggleButtonDisabled = true

                            subscriptions.subscribe(channel.id) {
                                subscriptionToggleButtonDisabled = false
                                navigation.sidebarSectionChanged.toggle()
                            }
                        } label: {
                            Label("Subscribe", systemImage: "star.circle")
                                .help("Subscribe")
                            #if os(iOS)
                                .labelStyle(.automatic)
                            #else
                                .labelStyle(.titleOnly)
                            #endif
                        }
                    }
                }
            }
            .disabled(subscriptionToggleButtonDisabled)
        }
    }

    private var navigationTitle: String {
        presentedChannel?.name ?? "No channel"
    }

    @ViewBuilder var toggleWatchedButton: some View {
        if let channel = presentedChannel {
            if feed.canMarkChannelAsWatched(channel.id) {
                markChannelAsWatchedButton
            } else {
                markChannelAsUnwatchedButton
            }
        }
    }

    var markChannelAsWatchedButton: some View {
        Button {
            guard let channel = presentedChannel else { return }
            feed.markChannelAsWatched(channel.id)
        } label: {
            Label("Mark channel feed as watched", systemImage: "checkmark.circle.fill")
                .help("Mark channel feed as watched")
        }
        .disabled(!feed.canMarkAllFeedAsWatched)
    }

    var markChannelAsUnwatchedButton: some View {
        Button {
            guard let channel = presentedChannel else { return }
            feed.markChannelAsUnwatched(channel.id)
        } label: {
            Label("Mark channel feed as unwatched", systemImage: "checkmark.circle")
                .help("Mark channel feed as unwatched")
        }
    }

    func load() {
        resource?
            .load()
            .onSuccess { response in
                if let page: ChannelPage = response.typedContent() {
                    if let channel = page.channel {
                        ChannelsCacheModel.shared.store(channel)
                    }
                    self.page = page
                    self.contentTypeItems.replace(page.results)
                }
            }
            .onFailure { error in
                navigation.presentAlert(title: "Could not load channel data", message: error.userMessage)
            }
    }

    func loadNextPage() {
        guard let channel = presentedChannel, let pageToLoad = page, !pageToLoad.last else {
            return
        }

        var next = pageToLoad.nextPage
        if contentType == .videos, !pageToLoad.last {
            next = next ?? ""
        }

        let tabData = channel.tabs.first { $0.contentType == contentType }?.data
        let data = contentType != .videos ? tabData : nil
        accounts.api.channel(channel.id, contentType: contentType, data: data, page: next).load().onSuccess { response in
            if let page: ChannelPage = response.typedContent() {
                self.page = page
                let keys = self.contentTypeItems.collection.map(\.cacheKey)
                let items = self.contentTypeItems.collection + page.results.filter { !keys.contains($0.cacheKey) }
                self.contentTypeItems.replace(items)
            }
        }
    }
}

struct ChannelVideosView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(macOS)
            ChannelVideosView(channel: Video.fixture.channel, showCloseButton: true, inNavigationView: false)
                .environment(\.navigationStyle, .sidebar)
        #else
            NavigationView {
                ChannelVideosView(channel: Video.fixture.channel)
            }
        #endif
    }
}
