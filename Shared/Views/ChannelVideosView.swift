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

    @StateObject private var store = Store<Channel>()

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var recents = RecentsModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared
    @Namespace private var focusNamespace

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
                            .font(.title2)
                            .frame(alignment: .leading)

                        Spacer()

                        subscriptionsLabel
                        viewsLabel

                        subscriptionToggleButton

                        if let channel = presentedChannel {
                            FavoriteButton(item: FavoriteItem(section: .channel(accounts.app.appType.rawValue, channel.id, channel.name)))
                                .labelStyle(.iconOnly)
                        }
                    }
                    contentTypePicker
                        .pickerStyle(.automatic)
                }
                .frame(maxWidth: .infinity)
            #endif

            VerticalCells(items: contentItems) {
                banner
            }
            .environment(\.inChannelView, true)
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
                    if let presentedChannel {
                        FavoriteButton(item: FavoriteItem(section: .channel(accounts.app.appType.rawValue, presentedChannel.id, presentedChannel.name)))
                    }
                }
            #endif
        }
        #endif
        .onAppear {
            resource?.loadIfNeeded()
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
}

struct ChannelVideosView_Previews: PreviewProvider {
    static var previews: some View {
        ChannelVideosView(channel: Video.fixture.channel)
            .environment(\.navigationStyle, .tab)
            .injectFixtureEnvironmentObjects()

        NavigationView {
            Spacer()
            ChannelVideosView(channel: Video.fixture.channel)
                .environment(\.navigationStyle, .sidebar)
        }
    }
}
