import Siesta
import SwiftUI

struct SubscriptionsView: View {
    @StateObject private var store = Store<[Video]>()

    @EnvironmentObject<AccountsModel> private var accounts

    var api: InvidiousAPI {
        accounts.invidious
    }

    var feed: Resource {
        api.feed
    }

    var body: some View {
        PlayerControlsView {
            SignInRequiredView(title: "Subscriptions") {
                VideosCellsVertical(videos: store.collection)
                    .onAppear {
                        loadResources()
                    }
                    .onChange(of: accounts.account) { _ in
                        loadResources(force: true)
                    }
            }
        }
        .refreshable {
            loadResources(force: true)
        }
    }

    fileprivate func loadResources(force: Bool = false) {
        feed.addObserver(store)

        if let request = force ? api.home.load() : api.home.loadIfNeeded() {
            request.onSuccess { _ in
                loadFeed(force: force)
            }
        } else {
            loadFeed(force: force)
        }
    }

    fileprivate func loadFeed(force: Bool = false) {
        _ = force ? feed.load() : feed.loadIfNeeded()
    }
}
