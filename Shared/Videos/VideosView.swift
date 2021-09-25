import Defaults
import SwiftUI

struct VideosView: View {
    @EnvironmentObject<NavigationModel> private var navigation

    #if os(tvOS)
        @Default(.layout) private var layout
    #endif

    var videos: [Video]

    var body: some View {
        VStack {
            #if os(tvOS)
                if layout == .cells {
                    VideosCellsVertical(videos: videos)
                } else {
                    VideosListView(videos: videos)
                }
            #else
                VideosCellsVertical(videos: videos)
            #endif
        }
        #if os(macOS)
            .background()
            .frame(minWidth: 360)
        #endif
    }
}
