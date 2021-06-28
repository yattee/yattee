import Defaults
import SwiftUI

struct VideosListView: View {
    var videos: [Video]

    var body: some View {
        Section {
            List {
                ForEach(videos) { video in
                    VideoListRowView(video: video)
                        .contextMenu { VideoContextMenuView(video: video) }
                        .listRowInsets(listRowInsets)
                }
            }
            .listStyle(GroupedListStyle())
        }
    }

    var listRowInsets: EdgeInsets {
        EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30)
    }
}
