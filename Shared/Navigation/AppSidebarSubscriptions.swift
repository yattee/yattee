import Defaults
import SwiftUI

struct AppSidebarSubscriptions: View {
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared

    var body: some View {
        Section(header: Text("Subscriptions")) {
            ForEach(subscriptions.all) { channel in
                NavigationLink(tag: TabSelection.channel(channel.id), selection: $navigation.tabSelection) {
                    LazyView(ChannelVideosView(channel: channel).modifier(PlayerOverlayModifier()))
                } label: {
                    if channel.thumbnailURL != nil {
                        HStack {
                            ChannelAvatarView(channel: channel, subscribedBadge: false)
                                .frame(width: 20, height: 20)

                            Text(channel.name)
                        }
                    } else {
                        Label(channel.name, systemImage: RecentsModel.symbolSystemImage(channel.name))
                    }
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
}

struct AppSidebarSubscriptions_Previews: PreviewProvider {
    static var previews: some View {
        AppSidebarSubscriptions()
    }
}
