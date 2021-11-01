import Siesta
import SwiftUI

struct SubscriptionsView: View {
    @StateObject private var store = Store<[Video]>()

    @EnvironmentObject<AccountsModel> private var accounts

    var feed: Resource? {
        accounts.api.feed
    }

    var videos: [ContentItem] {
        ContentItem.array(of: store.collection)
    }

    var body: some View {
        PlayerControlsView {
            SignInRequiredView(title: "Subscriptions") {
                VerticalCells(items: videos)
                    .onAppear {
                        loadResources()
                    }
                    .onChange(of: accounts.current) { _ in
                        loadResources(force: true)
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                FavoriteButton(item: FavoriteItem(section: .subscriptions))
            }
        }
        .refreshable {
            loadResources(force: true)
        }
    }

    fileprivate func loadResources(force: Bool = false) {
        feed?.addObserver(store)

        if let request = force ? accounts.api.home?.load() : accounts.api.home?.loadIfNeeded() {
            request.onSuccess { _ in
                loadFeed(force: force)
            }
        } else {
            loadFeed(force: force)
        }
    }

    fileprivate func loadFeed(force: Bool = false) {
        _ = force ? feed?.load() : feed?.loadIfNeeded()
    }
}
