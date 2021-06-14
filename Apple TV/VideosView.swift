import SwiftUI

struct VideosView: View {
    @ObservedObject var state: AppState

    @Binding var tabSelection: TabSelection

    var videos: [Video]

    var body: some View {
        Section {
            List {
                ForEach(videos) { video in
                    VideoThumbnailView(video: video)
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
            state.openChannel(from: video)
            tabSelection = .channel
        }
    }

    func closeChannelButton(name: String) -> some View {
        Button("Close \(name) Channel") {
            tabSelection = .popular
            state.closeChannel()
        }
    }

    var listRowInsets: EdgeInsets {
        EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30)
    }
}
