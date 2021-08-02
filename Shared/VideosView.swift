import Defaults
import SwiftUI

struct VideosView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    @State private var profile = Profile()

    #if os(tvOS)
        @Default(.layout) private var layout
    #endif

    var videos: [Video]

    var body: some View {
        VStack {
            #if os(tvOS)
                if layout == .cells {
                    VideosCellsView(videos: videos)
                } else {
                    VideosListView(videos: videos)
                }
            #else
                VideosCellsView(videos: videos)
            #endif
        }
        #if os(macOS)
            .background()
        #endif
    }
}
