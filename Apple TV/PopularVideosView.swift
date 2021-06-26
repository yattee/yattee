import SwiftUI

struct PopularVideosView: View {
    @ObservedObject private var provider = PopularVideosProvider()

    var body: some View {
        VideosView(videos: videos)
    }

    var videos: [Video] {
        if provider.videos.isEmpty {
            provider.load()
        }

        return provider.videos
    }
}
