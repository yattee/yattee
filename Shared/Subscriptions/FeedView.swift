import Defaults
import Siesta
import SwiftUI

struct FeedView: View {
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared
    @ObservedObject private var feedCount = UnwatchedFeedCountModel.shared

    @Default(.showCacheStatus) private var showCacheStatus

    #if os(tvOS)
        @Default(.subscriptionsListingStyle) private var subscriptionsListingStyle
        @StateObject private var accountsModel = AccountsViewModel()
    #endif

    var videos: [ContentItem] {
        guard let selectedChannel else {
            return ContentItem.array(of: feed.videos)
        }
        return ContentItem.array(of: feed.videos.filter {
            $0.channel.id == selectedChannel.id
        })
    }

    var channels: [Channel] {
        feed.videos.map(\.channel).unique()
    }

    @State private var selectedChannel: Channel?
    #if os(tvOS)
        @FocusState private var focusedChannel: String?
    #endif
    @State private var feedChannelsViewVisible = false
    private var navigation = NavigationModel.shared
    private let dismiss_channel_list_id = "dismiss_channel_list_id"

    var body: some View {
        #if os(tvOS)
            GeometryReader { geometry in
                ZStack {
                    // selected channel feed view
                    HStack(spacing: 0) {
                        // sidebar - show channels
                        if feedChannelsViewVisible {
                            Spacer()
                                .frame(width: geometry.size.width * 0.3)
                        }
                        selectedFeedView
                    }
                    .disabled(feedChannelsViewVisible)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    if feedChannelsViewVisible {
                        HStack(spacing: 0) {
                            // sidebar - show channels
                            feedChannelsView
                                .padding(.all)
                                .frame(width: geometry.size.width * 0.3)
                                .background()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                            Rectangle()
                                .fill(.clear)
                                .id(dismiss_channel_list_id)
                                .focusable()
                                .focused(self.$focusedChannel, equals: dismiss_channel_list_id)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    }
                }
            }
        #else
            selectedFeedView
        #endif
    }

    #if os(tvOS)

        var accountsPicker: some View {
            ForEach(accountsModel.sortedAccounts.filter { $0.anonymous == false }) { account in
                Button(action: {
                    AccountsModel.shared.setCurrent(account)
                }) {
                    HStack {
                        Text("\(account.description) (\(account.instance.app.rawValue))")
                        if account == accountsModel.currentAccount {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }

        var feedChannelsView: some View {
            ScrollViewReader { proxy in
                VStack {
                    Text("Channels")
                        .font(.subheadline)
                    if #available(tvOS 17.0, *) {
                        List(selection: $selectedChannel) {
                            Button(action: {
                                self.selectedChannel = nil
                                self.feedChannelsViewVisible = false
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: RecentsModel.symbolSystemImage("A"))
                                        .imageScale(.large)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 35, height: 35)
                                    Text("All")
                                    Spacer()
                                    feedCount.unwatchedText
                                }
                            }
                            .padding(.all)
                            .background(RoundedRectangle(cornerRadius: 8.0)
                                .fill(self.selectedChannel == nil ? Color.secondary : Color.clear))
                            .font(.caption)
                            .buttonStyle(PlainButtonStyle())
                            .focused(self.$focusedChannel, equals: "all")

                            ForEach(channels, id: \.self) { channel in
                                Button(action: {
                                    self.selectedChannel = channel
                                    self.feedChannelsViewVisible = false
                                }) {
                                    HStack(spacing: 16) {
                                        ChannelAvatarView(channel: channel, subscribedBadge: false)
                                            .frame(width: 50, height: 50)
                                        Text(channel.name)
                                            .lineLimit(1)
                                        Spacer()
                                        if let unwatchedCount = feedCount.unwatchedByChannelText(channel) {
                                            unwatchedCount
                                        }
                                    }
                                }
                                .padding(.all)
                                .background(RoundedRectangle(cornerRadius: 8.0)
                                    .fill(self.selectedChannel == channel ? Color.secondary : Color.clear))
                                .font(.caption)
                                .buttonStyle(PlainButtonStyle())
                                .focused(self.$focusedChannel, equals: channel.id)
                            }
                        }
                        .onChange(of: self.focusedChannel) {
                            if self.focusedChannel == "all" {
                                withAnimation {
                                    self.selectedChannel = nil
                                }
                            } else if self.focusedChannel == dismiss_channel_list_id {
                                self.feedChannelsViewVisible = false
                            } else {
                                withAnimation {
                                    self.selectedChannel = channels.first {
                                        $0.id == self.focusedChannel
                                    }
                                }
                            }
                        }
                        .onAppear {
                            guard let selectedChannel = self.selectedChannel else {
                                return
                            }
                            proxy.scrollTo(selectedChannel, anchor: .top)
                        }
                        .onExitCommand {
                            withAnimation {
                                self.feedChannelsViewVisible = false
                            }
                        }
                    }
                }
            }
        }
    #endif

    var selectedFeedView: some View {
        VerticalCells(items: videos) { if shouldDisplayHeader { header } }
            .environment(\.loadMoreContentHandler) { feed.loadNextPage() }
            .onAppear {
                feed.loadResources()
            }
        #if os(iOS)
            .refreshControl { refreshControl in
                feed.loadResources(force: true) {
                    refreshControl.endRefreshing()
                }
            }
            .backport
            .refreshable {
                await feed.loadResources(force: true)
            }
        #endif
        #if !os(tvOS)
            .background(
            Button("Refresh") {
                feed.loadResources(force: true)
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
        #if !os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                feed.loadResources()
        }
        #endif
    }

    var header: some View {
        HStack(spacing: 16) {
            #if os(tvOS)
                if #available(tvOS 17.0, *) {
                    Menu {
                        accountsPicker
                    } label: {
                        Label("Channels", systemImage: "filemenu.and.selection")
                            .labelStyle(.iconOnly)
                            .imageScale(.small)
                            .font(.caption)
                    } primaryAction: {
                        withAnimation {
                            self.feedChannelsViewVisible = true
                            self.focusedChannel = selectedChannel?.id ?? "all"
                        }
                    }
                    .opacity(feedChannelsViewVisible ? 0 : 1)
                    .frame(minWidth: feedChannelsViewVisible ? 0 : nil, maxWidth: feedChannelsViewVisible ? 0 : nil)
                }
                channelHeaderView
                if selectedChannel == nil {
                    Spacer()
                }
                if feedChannelsViewVisible == false {
                    ListingStyleButtons(listingStyle: $subscriptionsListingStyle)
                    HideWatchedButtons()
                    HideShortsButtons()
                }
            #endif

            if feedChannelsViewVisible == false {
                if showCacheStatus {
                    CacheStatusHeader(
                        refreshTime: feed.formattedFeedTime,
                        isLoading: feed.isLoading
                    )
                }

                #if os(tvOS)
                    Button {
                        feed.loadResources(force: true)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                            .imageScale(.small)
                            .font(.caption)
                    }
                #endif
            }
        }
        .padding(.leading, 30)
        #if os(tvOS)
            .padding(.bottom, 15)
            .padding(.trailing, 30)
        #endif
    }

    var channelHeaderView: some View {
        guard let selectedChannel else {
            return AnyView(
                Text("All Channels")
                    .font(.caption)
                    .frame(alignment: .leading)
                    .lineLimit(1)
                    .padding(0)
                    .padding(.leading, 16)
            )
        }

        return AnyView(
            HStack(spacing: 16) {
                ChannelAvatarView(channel: selectedChannel, subscribedBadge: false)
                    .id("channel-avatar-\(selectedChannel.id)")
                    .frame(width: 80, height: 80)
                Text("\(selectedChannel.name)")
                    .font(.caption)
                    .frame(alignment: .leading)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                if feedChannelsViewVisible == false {
                    Button(action: {
                        navigation.openChannel(selectedChannel, navigationStyle: .tab)
                    }) {
                        Text("Visit Channel")
                            .font(.caption)
                            .frame(alignment: .leading)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(0)
            .padding(.leading, 16)
        )
    }

    var shouldDisplayHeader: Bool {
        #if os(tvOS)
            true
        #else
            showCacheStatus
        #endif
    }
}

struct FeedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FeedView()
        }
    }
}
