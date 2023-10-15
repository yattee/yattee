import Defaults
import SwiftUI

struct AppSidebarSubscriptions: View {
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var feedCount = UnwatchedFeedCountModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared

    @Default(.showUnwatchedFeedBadges) private var showUnwatchedFeedBadges
    @Default(.keepChannelsWithUnwatchedFeedOnTop) private var keepChannelsWithUnwatchedFeedOnTop
    @Default(.showChannelAvatarInChannelsLists) private var showChannelAvatarInChannelsLists

    @State private var channelLinkActive = false
    @State private var channelForLink: Channel?

    var body: some View {
        Section(header: Text("Subscriptions")) {
            ForEach(channels) { channel in
                NavigationLink(tag: TabSelection.channel(channel.id), selection: $navigation.tabSelection) {
                    LazyView(ChannelVideosView(channel: channel))
                } label: {
                    HStack {
                        if showChannelAvatarInChannelsLists {
                            ChannelAvatarView(channel: channel, subscribedBadge: false)
                                .frame(width: Constants.sidebarChannelThumbnailSize, height: Constants.sidebarChannelThumbnailSize)

                            Text(channel.name)
                        } else {
                            Label(channel.name, systemImage: RecentsModel.symbolSystemImage(channel.name))
                        }

                        Spacer()
                    }
                    .lineLimit(1)
                    .backport
                    .badge(showUnwatchedFeedBadges ? feedCount.unwatchedByChannelText(channel) : nil)
                }
                .contextMenu {
                    Button("Unsubscribe") {
                        navigation.presentUnsubscribeAlert(channel, subscriptions: subscriptions)
                    }
                }
                .id("channel\(channel.id)")
            }
        }
    }

    var channels: [Channel] {
        keepChannelsWithUnwatchedFeedOnTop ? subscriptions.allByUnwatchedCount : subscriptions.all
    }
}

struct AppSidebarSubscriptions_Previews: PreviewProvider {
    static var previews: some View {
        AppSidebarSubscriptions()
    }
}
