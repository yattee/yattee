import Defaults
import Siesta
import SwiftUI

struct WatchNowView: View {
    @EnvironmentObject<AccountsModel> private var accounts

    var api: InvidiousAPI! {
        accounts.invidious
    }

    var body: some View {
        PlayerControlsView {
            ScrollView(.vertical, showsIndicators: false) {
                if !accounts.current.isNil {
                    VStack(alignment: .leading, spacing: 0) {
                        if api.signedIn {
                            WatchNowSection(resource: api.feed, label: "Subscriptions")
                        }
                        WatchNowSection(resource: api.popular, label: "Popular")
                        WatchNowSection(resource: api.trending(category: .default, country: .pl), label: "Trending")
                        WatchNowSection(resource: api.trending(category: .movies, country: .pl), label: "Movies")
                        WatchNowSection(resource: api.trending(category: .music, country: .pl), label: "Music")

//                  TODO: adding sections to view
//                  ===================
//                  WatchNowPlaylistSection(id: "IVPLmRFYLGYZpq61SpujNw3EKbzzGNvoDmH")
//                  WatchNowSection(resource: api.channelVideos("UCBJycsmduvYEL83R_U4JriQ"), label: "MKBHD")
                    }
                }
            }
            .id(UUID())
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
}

struct WatchNowView_Previews: PreviewProvider {
    static var previews: some View {
        WatchNowView()
            .injectFixtureEnvironmentObjects()
    }
}
