import Defaults
import SwiftUI

struct AppSidebarSubscriptions: View {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    var body: some View {
        Section(header: Text("Subscriptions")) {
            ForEach(subscriptions.all) { channel in
                NavigationLink(tag: TabSelection.channel(channel.id), selection: $navigation.tabSelection) {
                    LazyView(ChannelVideosView(channel: channel))
                } label: {
                    Label(channel.name, systemImage: RecentsModel.symbolSystemImage(channel.name))
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
