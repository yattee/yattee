import Defaults
import Siesta
import SwiftUI

struct SubscriptionsView: View {
    enum Page: String, CaseIterable, Defaults.Serializable {
        case feed
        case channels
    }

    @Default(.subscriptionsViewPage) private var subscriptionsViewPage
    @Default(.subscriptionsListingStyle) private var subscriptionsListingStyle

    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared

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
                    HStack {
                        Picker("Page", selection: $subscriptionsViewPage) {
                            Label("Feed", systemImage: "film").tag(Page.feed)
                            Label("Channels", systemImage: "person.3.fill").tag(Page.channels)
                        }
                        .pickerStyle(.segmented)
                        .labelStyle(.titleOnly)
                    }
                    .frame(maxWidth: 500)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    subscriptionsMenu
                }

                ToolbarItem {
                    RequestErrorButton(error: requestError)
                }
            }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup {
                ListingStyleButtons(listingStyle: $subscriptionsListingStyle)
                HideWatchedButtons()
                HideShortsButtons()
                toggleWatchedButton
                    .id(feed.watchedId)
                playUnwatchedButton
                    .id(feed.watchedId)
            }
        }
        #endif
    }

    var requestError: RequestError? {
        subscriptionsViewPage == .channels ? subscriptions.error : feed.error
    }

    #if os(iOS)
        var subscriptionsMenu: some View {
            Menu {
                if subscriptionsViewPage == .feed {
                    ListingStyleButtons(listingStyle: $subscriptionsListingStyle)

                    Section {
                        HideWatchedButtons()
                        HideShortsButtons()
                    }

                    playUnwatchedButton

                    toggleWatchedButton
                }

                Section {
                    SettingsButtons()
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.large)
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

    var playUnwatchedButton: some View {
        Button {
            feed.playUnwatchedFeed()
        } label: {
            Label("Play all unwatched", systemImage: "play")
        }
        .help("Play all unwatched")
        .disabled(!feed.canPlayUnwatchedFeed)
    }

    @ViewBuilder var toggleWatchedButton: some View {
        if feed.canMarkAllFeedAsWatched {
            markAllFeedAsWatchedButton
        } else {
            markAllFeedAsUnwatchedButton
        }
    }

    var markAllFeedAsWatchedButton: some View {
        Button {
            feed.markAllFeedAsWatched()
        } label: {
            Label("Mark all as watched", systemImage: "checkmark.circle.fill")
        }
        .help("Mark all as watched")
        .disabled(!feed.canMarkAllFeedAsWatched)
    }

    var markAllFeedAsUnwatchedButton: some View {
        Button {
            feed.markAllFeedAsUnwatched()
        } label: {
            Label("Mark all as unwatched", systemImage: "checkmark.circle")
        }
        .help("Mark all as unwatched")
    }
}

struct SubscriptionsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SubscriptionsView()
        }
    }
}
