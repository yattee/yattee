import Defaults
import SwiftUI

struct AppSidebarRecents: View {
    @Binding var selection: TabSelection?

    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<Recents> private var recents

    @Default(.recentlyOpened) private var recentItems

    var body: some View {
        Group {
            if !recentItems.isEmpty {
                Section(header: Text("Recents")) {
                    ForEach(recentItems.reversed()) { recent in
                        Group {
                            switch recent.type {
                            case .channel:
                                RecentNavigationLink(recent: recent, selection: $selection) {
                                    LazyView(ChannelVideosView(Channel(id: recent.id, name: recent.title)))
                                }
                            case .query:
                                RecentNavigationLink(recent: recent, selection: $selection, systemImage: "magnifyingglass") {
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
    @EnvironmentObject<Recents> private var recents

    var recent: RecentItem
    @Binding var selection: TabSelection?

    var systemImage: String?
    let destination: DestinationContent

    init(
        recent: RecentItem,
        selection: Binding<TabSelection?>,
        systemImage: String? = nil,
        @ViewBuilder destination: () -> DestinationContent
    ) {
        self.recent = recent
        _selection = selection
        self.systemImage = systemImage
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(tag: TabSelection.recentlyOpened(recent.tag), selection: $selection) {
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
