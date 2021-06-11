import SwiftUI

struct VideosView: View {
    @ObservedObject var state: AppState
    
    @Binding var tabSelection: TabSelection

    var videos: [Video]

    var body: some View {
        Group {
            List {
                ForEach(videos) { video in
                    VideoThumbnailView(video: video)
                        .contextMenu {
                            if state.showingChannel {
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
    
    func closeChannelButton(name: String) -> some View {
        Button("Close \(name) Channel", action: {
            state.closeChannel()
            tabSelection = .popular
        })
    }
    
    func openChannelButton(from video: Video) -> some View {
        Button("\(video.author) Channel", action: {
            state.openChannel(from: video)
            tabSelection = .channel
        })
    }

    var listRowInsets: EdgeInsets {
        EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30)
    }
}
