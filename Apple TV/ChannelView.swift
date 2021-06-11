import SwiftUI

struct ChannelView: View {
    @ObservedObject private var provider = ChannelVideosProvider()
    @ObservedObject var state: AppState

    @Binding var tabSelection: TabSelection

    var body: some View {
        Group {
            List {
                ForEach(videos) { video in
                    VideoThumbnailView(video: video)
                        .contextMenu {
                            Button("Close \(video.author) channel", action: {
                                state.closeChannel()
                                tabSelection = .popular
                            })
                        }
                        .listRowInsets(listRowInsets)
                }
            }
            .listStyle(GroupedListStyle())
        }
        .task {
            async {
                provider.load()
            }
        }
    }

    var listRowInsets: EdgeInsets {
        EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30)
    }

    var videos: [Video] {
        if state.channelID != provider.channelID {
            provider.videos = []
            provider.channelID = state.channelID
            provider.load()
        }

        return provider.videos
    }
}

//
// struct ChannelView_Previews: PreviewProvider {
//    static var previews: some View {
//        ChannelView()
//    }
// }
