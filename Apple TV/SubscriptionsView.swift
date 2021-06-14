import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject private var provider = SubscriptionVideosProvider()
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
        provider.videos
    }
}
