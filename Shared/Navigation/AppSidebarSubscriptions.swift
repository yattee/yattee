import Defaults
import SwiftUI

struct AppSidebarSubscriptions: View {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @Binding var selection: TabSelection?

    var body: some View {
        Section(header: Text("Subscriptions")) {
            ForEach(subscriptions.all) { channel in
                NavigationLink(tag: TabSelection.channel(channel.id), selection: $selection) {
                    LazyView(ChannelVideosView(channel: channel))
                } label: {
                    Label(channel.name, systemImage: AppSidebarNavigation.symbolSystemImage(channel.name))
                }
                .contextMenu {
                    Button("Unsubscribe") {
                        navigation.presentUnsubscribeAlert(channel)
                    }
                }
                .modifier(UnsubscribeAlertModifier())
            }
        }
        .onAppear {
            subscriptions.load()
        }
    }

    var unsubscribeAlertTitle: String {
        if let channel = navigation.channelToUnsubscribe {
            return "Unsubscribe from \(channel.name)"
        }

        return "Unknown channel"
    }
}
