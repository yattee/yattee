import SwiftUI

struct PopularVideosView: View {
    @ObservedObject private var provider = PopularVideosProvider()
    @ObservedObject var state: AppState
    @Binding var tabSelection: TabSelection

    var body: some View {
        Group {
            List {
                ForEach(provider.videos) { video in
                    VideoThumbnailView(video: video)
                        .contextMenu {
                            Button("\(video.author) Channel", action: {
                                state.setChannel(from: video)
                                tabSelection = .channel
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
}
