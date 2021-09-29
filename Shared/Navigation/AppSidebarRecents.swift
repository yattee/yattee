import Defaults
import SwiftUI

struct AppSidebarRecents: View {
    @EnvironmentObject<RecentsModel> private var recents

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
                                    LazyView(ChannelVideosView(channel: recent.channel!))
                                }
                            case .query:
                                RecentNavigationLink(recent: recent, systemImage: "magnifyingglass") {
                                    LazyView(SearchView(recent.query!))
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
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<RecentsModel> private var recents

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
                Label(recent.title, systemImage: labelSystemImage)

                Spacer()

                Button(action: {
                    recents.close(recent)
                }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }
        }
        .id(recent.tag)
    }

    var labelSystemImage: String {
        systemImage != nil ? systemImage! : AppSidebarNavigation.symbolSystemImage(recent.title)
    }
}
