import SwiftUI

struct PopularVideosView: View {
    @ObservedObject private var provider = PopularVideosProvider()
    @EnvironmentObject private var state: AppState

    @Binding var tabSelection: TabSelection

    var body: some View {
        VideosView(tabSelection: $tabSelection, videos: videos)
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
