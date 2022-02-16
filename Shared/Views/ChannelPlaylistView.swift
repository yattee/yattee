import Siesta
import SwiftUI

struct ChannelPlaylistView: View {
    var playlist: ChannelPlaylist

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?

    @StateObject private var store = Store<ChannelPlaylist>()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.inNavigationView) private var inNavigationView

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlayerModel> private var player

    var items: [ContentItem] {
        ContentItem.array(of: store.item?.videos ?? [])
    }

    var resource: Resource? {
        accounts.api.channelPlaylist(playlist.id)
    }

    var body: some View {
        #if os(iOS)
            if inNavigationView {
                content
            } else {
                BrowserPlayerControls {
                    content
                }
            }
        #else
            BrowserPlayerControls {
                content
            }
        #endif
    }

    var content: some View {
        VStack(alignment: .leading) {
            #if os(tvOS)
                HStack {
                    Text(playlist.title)
                        .font(.title2)
                        .frame(alignment: .leading)

                    Spacer()

                    FavoriteButton(item: FavoriteItem(section: .channelPlaylist(playlist.id, playlist.title)))
                        .labelStyle(.iconOnly)

                    playButton
                        .labelStyle(.iconOnly)
                    shuffleButton
                        .labelStyle(.iconOnly)
                }
            #endif
            VerticalCells(items: items)
                .environment(\.inChannelPlaylistView, true)
        }
        #if os(iOS)
        .sheet(isPresented: $presentingShareSheet) {
            if let shareURL = shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        #endif
        .onAppear {
            resource?.addObserver(store)
            resource?.loadIfNeeded()
        }
        #if os(tvOS)
        .background(Color.background(scheme: colorScheme))
        #else
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ShareButton(
                    contentItem: contentItem,
                    presentingShareSheet: $presentingShareSheet,
                    shareURL: $shareURL
                )
            }

            ToolbarItem(placement: playlistButtonsPlacement) {
                HStack {
                    FavoriteButton(item: FavoriteItem(section: .channelPlaylist(playlist.id, playlist.title)))

                    playButton
                    shuffleButton
                }
            }
        }
        .navigationTitle(playlist.title)
            #if os(iOS)
                .navigationBarHidden(player.playerNavigationLinkActive)
            #endif
        #endif
    }

    private var playlistButtonsPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .navigationBarTrailing
        #else
            .automatic
        #endif
    }

    private var playButton: some View {
        Button {
            player.play(videos, inNavigationView: inNavigationView)
        } label: {
            Label("Play All", systemImage: "play")
        }
    }

    private var shuffleButton: some View {
        Button {
            player.play(videos, shuffling: true, inNavigationView: inNavigationView)
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
    }

    private var videos: [Video] {
        items.compactMap(\.video)
    }

    private var contentItem: ContentItem {
        ContentItem(playlist: playlist)
    }
}

struct ChannelPlaylistView_Previews: PreviewProvider {
    static var previews: some View {
        ChannelPlaylistView(playlist: ChannelPlaylist.fixture)
            .injectFixtureEnvironmentObjects()
    }
}
