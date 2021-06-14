import SwiftUI

struct PopularVideosView: View {
    @ObservedObject private var provider = PopularVideosProvider()
    @ObservedObject var state: AppState

    @Binding var tabSelection: TabSelection

    var body: some View {
        VideosView(state: state, tabSelection: $tabSelection, videos: videos)
            .task {
                async {
                    provider.load()
                }
            }
    }

    var videos: [Video] {
        if provider.videos.isEmpty {
            provider.load()
        }

        return provider.videos
    }
}
