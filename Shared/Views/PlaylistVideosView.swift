import Siesta
import SwiftUI

struct PlaylistVideosView: View {
    let playlist: Playlist

    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var model

    @StateObject private var store = Store<ChannelPlaylist>()

    var contentItems: [ContentItem] {
        var videos = playlist.videos

        if videos.isEmpty {
            videos = store.item?.videos ?? []
            if !player.accounts.app.userPlaylistsEndpointIncludesVideos {
                var i = 0

                for index in videos.indices {
                    var video = videos[index]
                    video.indexID = "\(i)"
                    i += 1
                    videos[index] = video
                }
            }
        }

        return ContentItem.array(of: videos)
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
        BrowserPlayerControls {
            VerticalCells(items: contentItems)
                .onAppear {
                    if !player.accounts.app.userPlaylistsEndpointIncludesVideos {
                        resource?.load()
                    }
                }
                .onChange(of: model.reloadPlaylists) { _ in
                    resource?.load()
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
                        player.play(videos)
                    } label: {
                        Label("Play All", systemImage: "play")
                    }

                    Button {
                        player.play(videos, shuffling: true)
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
