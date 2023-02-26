import Defaults
import SDWebImageSwiftUI
import Siesta
import SwiftUI

struct ChannelVideosView: View {
    var channel: Channel?
    var showCloseButton = false

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?
    @State private var subscriptionToggleButtonDisabled = false

    @State private var contentType = Channel.ContentType.videos
    @StateObject private var contentTypeItems = Store<[ContentItem]>()

    @State private var descriptionExpanded = false
    @StateObject private var store = Store<Channel>()

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var recents = RecentsModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared
    @Namespace private var focusNamespace

    @Default(.channelPlaylistListingStyle) private var channelPlaylistListingStyle
    @Default(.expandChannelDescription) private var expandChannelDescription
    @Default(.hideShorts) private var hideShorts

    var presentedChannel: Channel? {
        store.item ?? channel ?? recents.presentedChannel
    }

    var contentItems: [ContentItem] {
        guard contentType != .videos else {
            return ContentItem.array(of: presentedChannel?.videos ?? [])
        }

        return contentTypeItems.collection
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

            VerticalCells(items: contentItems) {
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
            .environment(\.inChannelView, true)
            .environment(\.listingStyle, channelPlaylistListingStyle)
            .environment(\.hideShorts, hideShorts)
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
                        }
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }
            #if !os(iOS)
                ToolbarItem(placement: .navigation) {
                    thumbnail
                }
                ToolbarItem {
                    ListingStyleButtons(listingStyle: $channelPlaylistListingStyle)
                }
                ToolbarItem {
                    HideShortsButtons(hide: $hideShorts)
                }
                ToolbarItem {
                    contentTypePicker
                }

                ToolbarItem {
                    HStack(spacing: 3) {
                        subscriptionsLabel
                        viewsLabel
                    }
                }

                ToolbarItem {
                    if let contentItem = presentedChannel?.contentItem {
                        ShareButton(contentItem: contentItem)
                    }
                }

                ToolbarItem {
                    subscriptionToggleButton
                        .layoutPriority(2)
                }

                ToolbarItem {
                    favoriteButton
                }

                ToolbarItem {
                    toggleWatchedButton
                }
            #endif
        }
        #endif
        .onAppear {
            descriptionExpanded = expandChannelDescription

            if let channel,
               let cache = ChannelsCacheModel.shared.retrieve(channel.cacheKey),
               store.item.isNil
            {
                store.replace(cache)
            }

            resource?.loadIfNeeded()?.onSuccess { response in
                if let channel: Channel = response.typedContent() {
                    ChannelsCacheModel.shared.store(channel)
                }
            }
        }
        .onChange(of: contentType) { _ in
            resource?.load()
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

    @ViewBuilder var favoriteButton: some View {
        if let presentedChannel {
            FavoriteButton(item: FavoriteItem(section: .channel(accounts.app.appType.rawValue, presentedChannel.id, presentedChannel.name)))
        }
    }

    var thumbnail: some View {
        ChannelAvatarView(channel: store.item)
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
            if let subscribers = store.item?.subscriptionsString {
                HStack(spacing: 0) {
                    Text(subscribers)
                    Image(systemName: "person.2.fill")
                }
            } else if store.item.isNil {
                HStack(spacing: 0) {
                    Text("1234")
                        .redacted(reason: .placeholder)
                    Image(systemName: "person.2.fill")
                }
            }
        }
        .imageScale(.small)
        .foregroundColor(.secondary)
    }

    var viewsLabel: some View {
        HStack(spacing: 0) {
            if let views = store.item?.totalViewsString {
                Text(views)

                Image(systemName: "eye.fill")
                    .imageScale(.small)
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
                        HideShortsButtons(hide: $hideShorts)
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
            if let channel = presentedChannel {
                ForEach(Channel.ContentType.allCases, id: \.self) { type in
                    if channel.hasData(for: type) {
                        Label(type.description, systemImage: type.systemImage).tag(type)
                    }
                }
            }
        }
    }

    private var resource: Resource? {
        guard let channel = presentedChannel else { return nil }

        let data = contentType != .videos ? channel.tabs.first(where: { $0.contentType == contentType })?.data : nil
        let resource = accounts.api.channel(channel.id, contentType: contentType, data: data)
        if contentType == .videos {
            resource.addObserver(store)
        } else {
            resource.addObserver(contentTypeItems)
        }

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
                            Label("Subscribe", systemImage: "circle")
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
        }
        .disabled(!feed.canMarkAllFeedAsWatched)
    }

    var markChannelAsUnwatchedButton: some View {
        Button {
            guard let channel = presentedChannel else { return }
            feed.markChannelAsUnwatched(channel.id)
        } label: {
            Label("Mark channel feed as unwatched", systemImage: "checkmark.circle")
        }
    }
}

struct ChannelVideosView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(macOS)
            ChannelVideosView(channel: Video.fixture.channel)
                .environment(\.navigationStyle, .sidebar)
        #else
            NavigationView {
                ChannelVideosView(channel: Video.fixture.channel)
            }
        #endif
    }
}
