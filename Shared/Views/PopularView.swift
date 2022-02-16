import Siesta
import SwiftUI

struct PopularView: View {
    @StateObject private var store = Store<[Video]>()

    @EnvironmentObject<AccountsModel> private var accounts

    var resource: Resource? {
        accounts.api.popular
    }

    var videos: [ContentItem] {
        ContentItem.array(of: store.collection)
    }

    var body: some View {
        BrowserPlayerControls {
            VerticalCells(items: videos)
                .onAppear {
                    resource?.addObserver(store)
                    resource?.loadIfNeeded()
                }
            #if !os(tvOS)
                .navigationTitle("Popular")
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                FavoriteButton(item: FavoriteItem(section: .popular))
            }
        }
        #if !os(tvOS)
        .background(
            Button("Refresh") {
                resource?.load()
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
        #if os(iOS)
        .refreshControl { refreshControl in
            resource?.load().onCompletion { _ in
                refreshControl.endRefreshing()
            }
        }
        .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
        #endif
    }
}
