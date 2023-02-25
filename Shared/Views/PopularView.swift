import Defaults
import Siesta
import SwiftUI

struct PopularView: View {
    @StateObject private var store = Store<[Video]>()

    @ObservedObject private var accounts = AccountsModel.shared

    @State private var error: RequestError?

    @Default(.popularListingStyle) private var popularListingStyle
    @Default(.hideShorts) private var hideShorts

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
                resource?.loadIfNeeded()?
                    .onFailure { self.error = $0 }
                    .onSuccess { _ in self.error = nil }
            }
            .environment(\.listingStyle, popularListingStyle)
        #if !os(tvOS)
            .navigationTitle("Popular")
            .background(
                Button("Refresh") {
                    resource?.load()
                        .onFailure { self.error = $0 }
                        .onSuccess { _ in self.error = nil }
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
            .onFailure { self.error = $0 }
            .onSuccess { _ in self.error = nil }
        }
        .backport
        .refreshable {
            DispatchQueue.main.async {
                resource?.load()
                    .onFailure { self.error = $0 }
                    .onSuccess { _ in self.error = nil }
            }
        }
        .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                ListingStyleButtons(listingStyle: $popularListingStyle)
            }

            ToolbarItem {
                HideShortsButtons(hide: $hideShorts)
            }
        }
        #else
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    resource?.loadIfNeeded()?
                        .onFailure { self.error = $0 }
                        .onSuccess { _ in self.error = nil }
                }
        #endif
    }

    #if os(iOS)
        private var popularMenu: some View {
            Menu {
                ListingStyleButtons(listingStyle: $popularListingStyle)

                Section {
                    HideShortsButtons(hide: $hideShorts)
                }

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
