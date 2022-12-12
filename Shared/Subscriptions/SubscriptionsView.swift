import Defaults
import SwiftUI

struct SubscriptionsView: View {
    enum Page: String, CaseIterable, Defaults.Serializable {
        case feed
        case channels
    }

    @Default(.subscriptionsViewPage) private var subscriptionsViewPage
    @Default(.subscriptionsListingStyle) private var subscriptionsListingStyle

    @ObservedObject private var feed = FeedModel.shared

    var body: some View {
        SignInRequiredView(title: "Subscriptions".localized()) {
            switch subscriptionsViewPage {
            case .feed:
                FeedView()
            case .channels:
                ChannelsView()
                #if os(tvOS)
                    .ignoresSafeArea(.all, edges: .horizontal)
                #endif
            }
        }
        .environment(\.listingStyle, subscriptionsListingStyle)

        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    subscriptionsMenu
                }
            }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                ListingStyleButtons(listingStyle: $subscriptionsListingStyle)
            }
        }
        #endif
    }

    #if os(iOS)
        var subscriptionsMenu: some View {
            Menu {
                Picker("Page", selection: $subscriptionsViewPage) {
                    Label("Feed", systemImage: "film").tag(Page.feed)
                    Label("Channels", systemImage: "person.3.fill").tag(Page.channels)
                }

                if subscriptionsViewPage == .feed {
                    ListingStyleButtons(listingStyle: $subscriptionsListingStyle)

                    Button {
                        feed.playUnwatchedFeed()
                    } label: {
                        Label("Play unwatched", systemImage: "play")
                    }

                    Button {
                        feed.markAllFeedAsWatched()
                    } label: {
                        Label("Mark all as watched", systemImage: "checkmark.circle.fill")
                    }

                    Button {
                        feed.markAllFeedAsUnwatched()
                    } label: {
                        Label("Mark all as unwatched", systemImage: "checkmark.circle")
                    }
                }

                Section {
                    SettingsButtons()
                }
            } label: {
                HStack(spacing: 12) {
                    menuLabel
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .transaction { t in t.animation = nil }
            }
        }

        var menuLabel: some View {
            HStack {
                Image(systemName: subscriptionsViewPage == .channels ? "person.3.fill" : "film")
                    .imageScale(.small)
                Text(subscriptionsViewPage.rawValue.capitalized.localized())
                    .font(.headline)
            }
        }
    #endif
}

struct SubscriptionsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SubscriptionsView()
        }
    }
}
