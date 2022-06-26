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
        BrowserPlayerControls {
            SignInRequiredView(title: "Subscriptions") {
                VerticalCells(items: videos)
                    .onAppear {
                        loadResources()
                    }
                    .onChange(of: accounts.current) { _ in
                        loadResources(force: true)
                    }
                #if os(iOS)
                    .refreshControl { refreshControl in
                        loadResources(force: true) {
                            refreshControl.endRefreshing()
                        }
                    }
                #endif
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                FavoriteButton(item: FavoriteItem(section: .subscriptions))
            }
        }
        #if !os(tvOS)
        .background(
            Button("Refresh") {
                loadResources(force: true)
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
        #endif
    }

    private func loadResources(force: Bool = false, onCompletion: @escaping () -> Void = {}) {
        feed?.addObserver(store)

        if accounts.app == .invidious {
            // Invidious for some reason won't refresh feed until homepage is loaded
            if let request = force ? accounts.api.home?.load() : accounts.api.home?.loadIfNeeded() {
                request.onSuccess { _ in
                    loadFeed(force: force, onCompletion: onCompletion)
                }
            } else {
                loadFeed(force: force, onCompletion: onCompletion)
            }
        } else {
            loadFeed(force: force, onCompletion: onCompletion)
        }
    }

    private func loadFeed(force: Bool = false, onCompletion: @escaping () -> Void = {}) {
        if let request = force ? feed?.load() : feed?.loadIfNeeded() {
            request.onCompletion { _ in
                onCompletion()
            }
        } else {
            onCompletion()
        }
    }
}

struct SubscriptonsView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionsView()
            .injectFixtureEnvironmentObjects()
    }
}
