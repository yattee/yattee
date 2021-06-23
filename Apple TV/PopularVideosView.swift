import SwiftUI

struct PopularVideosView: View {
    @ObservedObject private var provider = PopularVideosProvider()

    @Binding var tabSelection: TabSelection

    var body: some View {
        VideosView(tabSelection: $tabSelection, videos: videos)
            .task {
                Task.init {
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
