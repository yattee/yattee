import Defaults
import Siesta
import SwiftUI

struct PopularView: View {
    @StateObject private var store = Store<[Video]>()

    @ObservedObject private var accounts = AccountsModel.shared

    @Default(.popularListingStyle) private var popularListingStyle

    var resource: Resource? {
        accounts.api.popular
    }

    var videos: [ContentItem] {
        ContentItem.array(of: store.collection)
    }

    var body: some View {
        VerticalCells(items: videos)
            .onAppear {
                resource?.addObserver(store)
                resource?.loadIfNeeded()
            }
            .environment(\.listingStyle, popularListingStyle)
        #if !os(tvOS)
            .navigationTitle("Popular")
            .background(
                Button("Refresh") {
                    resource?.load()
                }
                .keyboardShortcut("r")
                .opacity(0)
            )
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                popularMenu
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshControl { refreshControl in
            resource?.load().onCompletion { _ in
                refreshControl.endRefreshing()
            }
            .onFailure { error in
                NavigationModel.shared.presentAlert(title: "Could not refresh Popular", message: error.userMessage)
            }
        }
        .backport
        .refreshable {
            DispatchQueue.main.async {
                resource?.load()
            }
        }
        .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                ListingStyleButtons(listingStyle: $popularListingStyle)
            }
        }
        #else
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    resource?.loadIfNeeded()
                }
        #endif
    }

    #if os(iOS)
        private var popularMenu: some View {
            Menu {
                ListingStyleButtons(listingStyle: $popularListingStyle)

                Section {
                    SettingsButtons()
                }
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .foregroundColor(.primary)
                            .imageScale(.small)

                        Text("Popular")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .transaction { t in t.animation = nil }
            }
        }
    #endif
}

struct PopularView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PopularView()
        }
    }
}
