import Siesta
import SwiftUI

struct PlaylistVideosView: View {
    let playlist: Playlist

    @ObservedObject private var accounts = AccountsModel.shared
    var player = PlayerModel.shared
    @ObservedObject private var model = PlaylistsModel.shared

    @StateObject private var channelPlaylist = Store<ChannelPlaylist>()
    @StateObject private var userPlaylist = Store<Playlist>()

    var contentItems: [ContentItem] {
        var videos = playlist.videos

        if videos.isEmpty {
            videos = userPlaylist.item?.videos ?? channelPlaylist.item?.videos ?? []
            if !accounts.app.userPlaylistsEndpointIncludesVideos {
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
        let resource = accounts.api.playlist(playlist.id)

        if accounts.app.userPlaylistsUseChannelPlaylistEndpoint {
            resource?.addObserver(channelPlaylist)
        } else {
            resource?.addObserver(userPlaylist)
        }

        return resource
    }

    var videos: [Video] {
        contentItems.compactMap(\.video)
    }

    init(_ playlist: Playlist) {
        self.playlist = playlist
    }

    var body: some View {
        VerticalCells(items: contentItems)
            .onAppear {
                guard contentItems.isEmpty else { return }
                resource?.load()
            }
            .onChange(of: model.reloadPlaylists) { _ in
                resource?.load()
            }
        #if !os(tvOS)
            .navigationTitle("\(playlist.title) Playlist")
        #endif
            .toolbar {
                ToolbarItem(placement: playlistButtonsPlacement) {
                    HStack {
                        FavoriteButton(item: FavoriteItem(section: .channelPlaylist(playlist.id, playlist.title)))

                        Button {
                            player.play(videos)
                        } label: {
                            Label("Play All", systemImage: "play")
                        }
                        .contextMenu {
                            Button {
                                player.play(videos, shuffling: true)
                            } label: {
                                Label("Shuffle All", systemImage: "shuffle")
                            }
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
