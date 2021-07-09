import Defaults
import SwiftUI

struct VideosView: View {
    @State private var profile = Profile()

    @Default(.layout) var layout
    @Default(.tabSelection) var tabSelection

    @Default(.showingAddToPlaylist) var showingAddToPlaylist

    var videos: [Video]

    var body: some View {
        VStack {
            if layout == .cells {
                VideosCellsView(videos: videos, columns: self.profile.cellsColumns)
            } else {
                VideosListView(videos: videos)
            }
        }
        .fullScreenCover(isPresented: $showingAddToPlaylist) {
            AddToPlaylistView()
        }
    }
}
