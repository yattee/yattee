import Siesta
import SwiftUI

struct PlaylistVideosView: View {
    let playlist: Playlist

    init(_ playlist: Playlist) {
        self.playlist = playlist
    }

    var body: some View {
        VideosView(videos: playlist.videos)
        #if !os(tvOS)
            .navigationTitle("\(playlist.title) Playlist")
        #endif
    }
}
