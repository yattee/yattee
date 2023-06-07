import Defaults
import Siesta
import SwiftUI

struct PopularView: View {
    @StateObject private var store = Store<[Video]>()

    @ObservedObject private var accounts = AccountsModel.shared

    @State private var error: RequestError?

    @Default(.popularListingStyle) private var popularListingStyle

    var resource: Resource? {
        accounts.api.popular
    }

    var videos: [ContentItem] {
        ContentItem.array(of: store.collection)
    }

    var body: some View {
        VerticalCells(items: videos) { if shouldDisplayHeader { header } }
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
                HideWatchedButtons()
            }

            ToolbarItem {
                HideShortsButtons()
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
                    HideWatchedButtons()
                    HideShortsButtons()
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

    var shouldDisplayHeader: Bool {
        #if os(tvOS)
            true
        #else
            false
        #endif
    }

    var header: some View {
        HStack {
            Spacer()
            ListingStyleButtons(listingStyle: $popularListingStyle)
            HideWatchedButtons()
            HideShortsButtons()

            Button {
                resource?.load()
                    .onFailure { self.error = $0 }
                    .onSuccess { _ in self.error = nil }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .imageScale(.small)
                    .font(.caption)
            }
        }
        .padding(.leading, 30)
        .padding(.bottom, 15)
        .padding(.trailing, 30)
    }
}

struct PopularView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PopularView()
        }
    }
}
