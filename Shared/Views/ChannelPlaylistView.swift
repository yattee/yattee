import Siesta
import SwiftUI

struct ChannelPlaylistView: View {
    var playlist: ChannelPlaylist?

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?

    @StateObject private var store = Store<ChannelPlaylist>()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents

    private var items: [ContentItem] {
        ContentItem.array(of: store.item?.videos ?? [])
    }

    private var presentedPlaylist: ChannelPlaylist? {
        playlist ?? recents.presentedPlaylist
    }

    private var resource: Resource? {
        guard let playlist = presentedPlaylist else {
            return nil
        }

        let resource = accounts.api.channelPlaylist(playlist.id)
        resource?.addObserver(store)

        return resource
    }

    var body: some View {
        if navigationStyle == .tab {
            NavigationView {
                BrowserPlayerControls {
                    content
                }
            }
        } else {
            BrowserPlayerControls {
                content
            }
        }
    }

    var content: some View {
        VStack(alignment: .leading) {
            #if os(tvOS)
                HStack {
                    if let playlist = presentedPlaylist {
                        Text(playlist.title)
                            .font(.title2)
                            .frame(alignment: .leading)

                        Spacer()

                        FavoriteButton(item: FavoriteItem(section: .channelPlaylist(playlist.id, playlist.title)))
                            .labelStyle(.iconOnly)
                    }

                    playButton
                        .labelStyle(.iconOnly)
                }
            #endif
            VerticalCells(items: items)
                .environment(\.inChannelPlaylistView, true)
        }
        .onAppear {
            if navigationStyle == .tab {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    resource?.loadIfNeeded()
                }
            } else {
                resource?.loadIfNeeded()
            }
        }
        #if os(tvOS)
        .background(Color.background(scheme: colorScheme))
        #else
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if navigationStyle == .tab {
                    Button("Done") {
                        withAnimation(Constants.overlayAnimation) {
                            navigation.presentingPlaylist = false
                        }
                    }
                }
            }

            ToolbarItem(placement: playlistButtonsPlacement) {
                HStack {
                    ShareButton(contentItem: contentItem)

                    if let playlist = presentedPlaylist {
                        FavoriteButton(item: FavoriteItem(section: .channelPlaylist(playlist.id, playlist.title)))
                    }

                    playButton
                }
            }
        }
        .navigationTitle(presentedPlaylist?.title ?? "")
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
            player.playbackMode = .queue
            player.play(videos)
        } label: {
            Label("Play All", systemImage: "play")
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
