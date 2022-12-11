import Defaults
import SwiftUI

struct AppSidebarSubscriptions: View {
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var subscriptions = SubsribedChannelsModel.shared

    var body: some View {
        Section(header: Text("Subscriptions")) {
            ForEach(subscriptions.all) { channel in
                NavigationLink(tag: TabSelection.channel(channel.id), selection: $navigation.tabSelection) {
                    LazyView(ChannelVideosView(channel: channel).modifier(PlayerOverlayModifier()))
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

struct AppSidebarSubscriptions_Previews: PreviewProvider {
    static var previews: some View {
        AppSidebarSubscriptions()
    }
}
