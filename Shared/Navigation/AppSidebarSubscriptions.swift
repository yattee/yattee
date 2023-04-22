import Defaults
import SwiftUI

struct AppSidebarSubscriptions: View {
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var feedCount = UnwatchedFeedCountModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared

    @Default(.showUnwatchedFeedBadges) private var showUnwatchedFeedBadges

    var body: some View {
        Section(header: Text("Subscriptions")) {
            ForEach(subscriptions.all) { channel in
                NavigationLink(tag: TabSelection.channel(channel.id), selection: $navigation.tabSelection) {
                    LazyView(ChannelVideosView(channel: channel))
                } label: {
                    HStack {
                        if channel.thumbnailURLOrCached != nil {
                            ChannelAvatarView(channel: channel, subscribedBadge: false)
                                .frame(width: Constants.sidebarChannelThumbnailSize, height: Constants.sidebarChannelThumbnailSize)
                            Text(channel.name)
                        } else {
                            Label(channel.name, systemImage: RecentsModel.symbolSystemImage(channel.name))
                        }

                        Spacer()
                    }
                    .backport
                    .badge(showUnwatchedFeedBadges ? feedCount.unwatchedByChannelText(channel) : nil)
                }
                .contextMenu {
                    if subscriptions.isSubscribing(channel.id) {
                        toggleWatchedButton(channel)
                    }

                    Button("Unsubscribe") {
                        navigation.presentUnsubscribeAlert(channel, subscriptions: subscriptions)
                    }
                }
                .id("channel\(channel.id)")
            }
        }
    }

    @ViewBuilder func toggleWatchedButton(_ channel: Channel) -> some View {
        if feed.canMarkChannelAsWatched(channel.id) {
            markChannelAsWatchedButton(channel)
        } else {
            markChannelAsUnwatchedButton(channel)
        }
    }

    func markChannelAsWatchedButton(_ channel: Channel) -> some View {
        Button {
            feed.markChannelAsWatched(channel.id)
        } label: {
            Label("Mark channel feed as watched", systemImage: "checkmark.circle.fill")
        }
        .disabled(!feed.canMarkAllFeedAsWatched)
    }

    func markChannelAsUnwatchedButton(_ channel: Channel) -> some View {
        Button {
            feed.markChannelAsUnwatched(channel.id)
        } label: {
            Label("Mark channel feed as unwatched", systemImage: "checkmark.circle")
        }
    }
}

struct AppSidebarSubscriptions_Previews: PreviewProvider {
    static var previews: some View {
        AppSidebarSubscriptions()
    }
}
