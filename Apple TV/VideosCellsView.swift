import Defaults
import SwiftUI

struct VideosCellsView: View {
    @State private var columns: Int

    init(videos: [Video], columns: Int = 3) {
        self.videos = videos
        self.columns = columns
    }

    var videos = [Video]()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: items, alignment: .center) {
                ForEach(videos) { video in
                    VideoView(video: video)
                        .contextMenu { VideoContextMenuView(video: video) }
                }
            }
            .padding()
        }
    }

    var items: [GridItem] {
        Array(repeating: .init(.fixed(600)), count: gridColumns)
    }

    var gridColumns: Int {
        videos.count < columns ? videos.count : columns
    }
}
