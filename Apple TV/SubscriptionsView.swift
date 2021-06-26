import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject private var provider = SubscriptionVideosProvider()

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
