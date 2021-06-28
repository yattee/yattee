import Defaults
import SwiftUI

struct VideosListView: View {
    @Default(.tabSelection) var tabSelection

    var videos: [Video]

    var body: some View {
        Section {
            List {
                ForEach(videos) { video in
                    VideoListRowView(video: video)
                        .contextMenu {
                            if tabSelection == .channel {
                                closeChannelButton(name: video.author)
                            } else {
                                openChannelButton(from: video)
                            }
                        }
                        .listRowInsets(listRowInsets)
                }
            }
            .listStyle(GroupedListStyle())
        }
    }

    func openChannelButton(from video: Video) -> some View {
        Button("\(video.author) Channel") {
            Defaults[.openChannel] = Channel.from(video: video)
            tabSelection = .channel
        }
    }

    func closeChannelButton(name: String) -> some View {
        Button("Close \(name) Channel") {
            Defaults.reset(.openChannel)
        }
    }

    var listRowInsets: EdgeInsets {
        EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30)
    }
}
