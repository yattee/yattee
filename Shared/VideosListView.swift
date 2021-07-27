import Defaults
import SwiftUI

struct VideosListView: View {
    var videos: [Video]

    var body: some View {
        Section {
            List {
                ForEach(videos) { video in
                    VideoView(video: video, layout: .list)
                        .contextMenu { VideoContextMenuView(video: video) }
                    #if os(tvOS)
                        .listRowInsets(listRowInsets)

                    #elseif os(iOS)
                        .listRowInsets(EdgeInsets(.zero))
                        .listRowSeparator(.hidden)
                    #endif
                }
            }
            #if os(tvOS)
                .listStyle(GroupedListStyle())
            #endif
        }
    }

    var listRowInsets: EdgeInsets {
        EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30)
    }
}

struct VideosListView_Previews: PreviewProvider {
    static var previews: some View {
        VideosListView(videos: Video.allFixtures)
    }
}
