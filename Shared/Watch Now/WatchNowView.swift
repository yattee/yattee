import Defaults
import Siesta
import SwiftUI

struct WatchNowView: View {
    @EnvironmentObject<AccountsModel> private var accounts

    var body: some View {
        PlayerControlsView {
            ScrollView(.vertical, showsIndicators: false) {
                if !accounts.current.isNil {
                    VStack(alignment: .leading, spacing: 0) {
                        if accounts.api.signedIn {
                            WatchNowSection(resource: accounts.api.feed, label: "Subscriptions")
                        }
                        if accounts.app.supportsPopular {
                            WatchNowSection(resource: accounts.api.popular, label: "Popular")
                        }
                        WatchNowSection(resource: accounts.api.trending(country: .pl, category: .default), label: "Trending")
                        if accounts.app.supportsTrendingCategories {
                            WatchNowSection(resource: accounts.api.trending(country: .pl, category: .movies), label: "Movies")
                            WatchNowSection(resource: accounts.api.trending(country: .pl, category: .music), label: "Music")
                        }

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
