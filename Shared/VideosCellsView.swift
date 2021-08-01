import Defaults
import SwiftUI

struct VideosCellsView: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var videos = [Video]()

    var body: some View {
        ScrollViewReader { scrollView in
            ScrollView(.vertical, showsIndicators: scrollViewShowsIndicators) {
                LazyVGrid(columns: items, alignment: .center) {
                    ForEach(videos) { video in
                        VideoView(video: video, layout: .cells)
                            .contextMenu { VideoContextMenuView(video: video) }
                    }
                }
                .padding()
            }
            .onChange(of: videos) { [videos] newVideos in
                guard !videos.isEmpty, let video = newVideos.first else {
                    return
                }

                scrollView.scrollTo(video.id, anchor: .top)
            }
        }
    }

    var items: [GridItem] {
        [GridItem(.adaptive(minimum: adaptiveGridItemMinimumSize))]
    }

    var gridColumns: Int {
        videos.count < 3 ? videos.count : 3
    }

    var adaptiveGridItemMinimumSize: CGFloat {
        #if os(iOS)
            return verticalSizeClass == .regular ? 340 : 800
        #elseif os(tvOS)
            return 560
        #else
            return 340
        #endif
    }

    var scrollViewShowsIndicators: Bool {
        #if !os(tvOS)
            true
        #else
            false
        #endif
    }
}

struct VideoCellsView_Previews: PreviewProvider {
    static var previews: some View {
        VideosView(videos: Video.allFixtures)
            .frame(minWidth: 1000)
            .environmentObject(NavigationState())
    }
}
