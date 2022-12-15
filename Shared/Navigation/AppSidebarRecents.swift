import Defaults
import SwiftUI

struct AppSidebarRecents: View {
    @ObservedObject private var navigation = NavigationModel.shared
    var recents = RecentsModel.shared

    @Default(.recentlyOpened) private var recentItems

    var body: some View {
        Group {
            if !recentItems.isEmpty {
                Section(header: Text("Recents")) {
                    ForEach(recentItems.reversed()) { recent in
                        Group {
                            switch recent.type {
                            case .channel:
                                RecentNavigationLink(recent: recent) {
                                    LazyView(ChannelVideosView(channel: recent.channel!).modifier(PlayerOverlayModifier()))
                                }

                            case .playlist:
                                RecentNavigationLink(recent: recent, systemImage: "list.and.film") {
                                    LazyView(ChannelPlaylistView(playlist: recent.playlist!).modifier(PlayerOverlayModifier()))
                                }

                            case .query:
                                RecentNavigationLink(recent: recent, systemImage: "magnifyingglass") {
                                    LazyView(SearchView(recent.query!).modifier(PlayerOverlayModifier()))
                                }
                            }
                        }
                        .contextMenu {
                            Button("Clear All Recents") {
                                recents.clear()
                            }

                            Button("Clear Search History") {
                                recents.clearQueries()
                            }
                            .disabled(!recentItems.contains { $0.type == .query })
                        }
                    }
                }
            }
        }
    }
}

struct RecentNavigationLink<DestinationContent: View>: View {
    var recents = RecentsModel.shared
    @ObservedObject private var navigation = NavigationModel.shared

    var recent: RecentItem
    var systemImage: String?
    let destination: DestinationContent

    init(
        recent: RecentItem,
        systemImage: String? = nil,
        @ViewBuilder destination: () -> DestinationContent
    ) {
        self.recent = recent
        self.systemImage = systemImage
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(tag: TabSelection.recentlyOpened(recent.tag), selection: $navigation.tabSelection) {
            destination
        } label: {
            HStack {
                if recent.type == .channel,
                   let channel = recent.channel,
                   channel.thumbnailURLOrCached != nil
                {
                    ChannelAvatarView(channel: channel, subscribedBadge: false)
                        .frame(width: Constants.sidebarChannelThumbnailSize, height: Constants.sidebarChannelThumbnailSize)

                    Text(channel.name)
                } else {
                    Label(recent.title, systemImage: labelSystemImage)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    recents.close(recent)
                }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundColor(.secondary)
                .opacity(0.5)
                .buttonStyle(.plain)
            }
        }
        .id(recent.tag)
    }

    var labelSystemImage: String {
        systemImage != nil ? systemImage! : RecentsModel.symbolSystemImage(recent.title)
    }
}
