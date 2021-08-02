import Defaults
import SwiftUI

struct VideosListView: View {
    var videos: [Video]

    var body: some View {
        Section {
            ScrollViewReader { scrollView in
                List {
                    ForEach(videos) { video in
                        VideoView(video: video, layout: .list)
                            .listRowInsets(EdgeInsets())
                    }
                    .onChange(of: videos) { videos in
                        guard let video = videos.first else {
                            return
                        }

                        scrollView.scrollTo(video.id, anchor: .top)
                    }
                }
            }
            .listStyle(GroupedListStyle())
        }
    }
}

struct VideosListView_Previews: PreviewProvider {
    static var previews: some View {
        VideosListView(videos: Video.allFixtures)
    }
}
