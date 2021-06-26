import SwiftUI

struct SubscriptionsView: View {
    @Binding var tabSelection: TabSelection

    @ObservedObject private var provider = SubscriptionVideosProvider()

    var body: some View {
        VideosView(tabSelection: $tabSelection, videos: videos)
    }

    var videos: [Video] {
        if provider.videos.isEmpty {
            provider.load()
        }

        return provider.videos
    }
}
