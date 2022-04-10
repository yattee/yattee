import Siesta
import SwiftUI

struct PlaylistVideosView: View {
    let playlist: Playlist

    @Environment(\.inNavigationView) private var inNavigationView
    @EnvironmentObject<PlayerModel> private var player

    @StateObject private var store = Store<ChannelPlaylist>()

    var contentItems: [ContentItem] {
        ContentItem.array(of: playlist.videos.isEmpty ? (store.item?.videos ?? []) : playlist.videos)
    }

    private var resource: Resource? {
        let resource = player.accounts.api.playlist(playlist.id)
        resource?.addObserver(store)

        return resource
    }

    var videos: [Video] {
        contentItems.compactMap(\.video)
    }

    init(_ playlist: Playlist) {
        self.playlist = playlist
    }

    var body: some View {
        PlayerControlsView {
            VerticalCells(items: contentItems)
                .onAppear {
                    if !player.accounts.app.userPlaylistsEndpointIncludesVideos {
                        resource?.loadIfNeeded()
                    }
                }
            #if !os(tvOS)
                .navigationTitle("\(playlist.title) Playlist")
            #endif
        }
        .toolbar {
            ToolbarItem(placement: playlistButtonsPlacement) {
                HStack {
                    FavoriteButton(item: FavoriteItem(section: .channelPlaylist(playlist.id, playlist.title)))

                    Button {
                        player.play(videos, inNavigationView: inNavigationView)
                    } label: {
                        Label("Play All", systemImage: "play")
                    }

                    Button {
                        player.play(videos, shuffling: true, inNavigationView: inNavigationView)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                }
            }
        }
    }

    private var playlistButtonsPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .navigationBarTrailing
        #else
            .automatic
        #endif
    }
}
