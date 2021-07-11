import Defaults
import SwiftUI

struct VideosView: View {
    @State private var profile = Profile()

    @Default(.layout) var layout

    @Default(.showingAddToPlaylist) var showingAddToPlaylist

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var horizontalSizeClass
    #endif

    var videos: [Video]

    var body: some View {
        VStack {
            #if os(tvOS)
                if layout == .cells {
                    VideosCellsView(videos: videos, columns: self.profile.cellsColumns)
                } else {
                    VideosListView(videos: videos)
                }
            #else
                VideosListView(videos: videos)
                #if os(macOS)
                    .frame(minWidth: 400)
                #endif
            #endif
        }

        #if os(tvOS)
            .fullScreenCover(isPresented: $showingAddToPlaylist) {
                AddToPlaylistView()
            }
        #endif
    }
}
