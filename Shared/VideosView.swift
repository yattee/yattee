import Defaults
import SwiftUI

struct VideosView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    @State private var profile = Profile()

    #if os(tvOS)
        @Default(.layout) var layout
    #endif

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
            .fullScreenCover(isPresented: $navigationState.showingVideo) {
                if let video = navigationState.video {
                    VideoPlayerView(video)
                }
            }
            .fullScreenCover(isPresented: $showingAddToPlaylist) {
                AddToPlaylistView()
            }

        #endif
    }
}
