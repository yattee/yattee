import Siesta
import SwiftUI

struct PlaylistVideosView: View {
    let playlist: Playlist

    var videos: [ContentItem] {
        ContentItem.array(of: playlist.videos)
    }

    init(_ playlist: Playlist) {
        self.playlist = playlist
    }

    var body: some View {
        PlayerControlsView {
            VerticalCells(items: videos)
            #if !os(tvOS)
                .navigationTitle("\(playlist.title) Playlist")
            #endif
        }
    }
}
