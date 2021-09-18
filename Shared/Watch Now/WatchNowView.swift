import Siesta
import SwiftUI

struct WatchNowView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                WatchNowSection(resource: InvidiousAPI.shared.feed, label: "Subscriptions")
                WatchNowSection(resource: InvidiousAPI.shared.popular, label: "Popular")
                WatchNowSection(resource: InvidiousAPI.shared.trending(category: .default, country: .pl), label: "Trending")
                WatchNowSection(resource: InvidiousAPI.shared.trending(category: .movies, country: .pl), label: "Movies")
                WatchNowSection(resource: InvidiousAPI.shared.trending(category: .music, country: .pl), label: "Music")

//              TODO: adding sections to view
//              ===================
//              WatchNowPlaylistSection(id: "IVPLmRFYLGYZpq61SpujNw3EKbzzGNvoDmH")
//              WatchNowSection(resource: InvidiousAPI.shared.channelVideos("UCBJycsmduvYEL83R_U4JriQ"), label: "MKBHD")
            }
        }
        #if os(tvOS)
            .edgesIgnoringSafeArea(.horizontal)
        #else
            .navigationTitle("Watch Now")
        #endif
        #if os(macOS)
            .background()
            .frame(minWidth: 360)
        #endif
    }
}

struct WatchNowView_Previews: PreviewProvider {
    static var previews: some View {
        WatchNowView()
            .environmentObject(Subscriptions())
            .environmentObject(NavigationState())
    }
}
