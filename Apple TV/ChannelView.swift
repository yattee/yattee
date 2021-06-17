import SwiftUI

struct ChannelView: View {
    @ObservedObject private var provider = ChannelVideosProvider()
    @EnvironmentObject private var state: AppState

    @Binding var tabSelection: TabSelection

    var body: some View {
        VideosView(tabSelection: $tabSelection, videos: videos)
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
