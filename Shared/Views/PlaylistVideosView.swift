import Siesta
import SwiftUI

struct PlaylistVideosView: View {
    let playlist: Playlist

    init(_ playlist: Playlist) {
        self.playlist = playlist
    }

    var body: some View {
        PlayerControlsView {
            VideosCellsVertical(videos: playlist.videos)
            #if !os(tvOS)
                .navigationTitle("\(playlist.title) Playlist")
            #endif
        }
    }
}
