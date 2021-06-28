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
            LazyVGrid(columns: items, spacing: 10) {
                ForEach(videos) { video in
                    VideoCellView(video: video)
                }
            }
            .padding()
        }
    }

    var items: [GridItem] {
        Array(repeating: .init(.fixed(600)), count: columns)
    }
}
