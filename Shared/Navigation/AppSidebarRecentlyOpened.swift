import SwiftUI

struct AppSidebarRecentlyOpened: View {
    @Binding var selection: TabSelection?

    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<Subscriptions> private var subscriptions

    @State private var subscriptionsChanged = false

    var body: some View {
        Group {
            if !recentlyOpened.isEmpty {
                Section(header: Text("Recently Opened")) {
                    ForEach(recentlyOpened) { channel in
                        NavigationLink(tag: TabSelection.channel(channel.id), selection: $selection) {
                            LazyView(ChannelVideosView(channel))
                        } label: {
                            HStack {
                                Label(channel.name, systemImage: AppSidebarNavigation.symbolSystemImage(channel.name))

                                Spacer()

                                Button(action: { navigationState.closeChannel(channel) }) {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .foregroundColor(.secondary)
                                .buttonStyle(.plain)
                            }
                        }

                        // force recalculating the view on change of subscriptions
                        .opacity(subscriptionsChanged ? 1 : 1)
                        .id(channel.id)
                        .contextMenu {
                            Button("Subscribe") {
                                subscriptions.subscribe(channel.id) {
                                    navigationState.sidebarSectionChanged.toggle()
                                }
                            }
                        }
                    }
                }
                .onChange(of: subscriptions.all) { _ in
                    subscriptionsChanged.toggle()
                }
            }
        }
    }

    var recentlyOpened: [Channel] {
        navigationState.openChannels.filter { !subscriptions.all.contains($0) }
    }
}
