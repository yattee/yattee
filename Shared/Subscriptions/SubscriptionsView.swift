import Siesta
import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject private var model = SubscriptionsViewModel.shared
    @ObservedObject private var accounts = AccountsModel.shared

    var videos: [ContentItem] {
        ContentItem.array(of: model.videos)
    }

    var body: some View {
        SignInRequiredView(title: "Subscriptions".localized()) {
            VerticalCells(items: videos) {
                HStack {
                    Spacer()

                    CacheStatusHeader(refreshTime: model.formattedFeedTime, isLoading: model.isLoading)

                    #if os(tvOS)
                        Button {
                            model.loadResources(force: true)
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                                .imageScale(.small)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 10)
                    #endif
                }
            }
            .environment(\.loadMoreContentHandler) { model.loadNextPage() }
            .onAppear {
                model.loadResources()
            }
            .onChange(of: accounts.current) { _ in
                model.reset()
                model.loadResources(force: true)
            }
            #if os(iOS)
            .refreshControl { refreshControl in
                model.loadResources(force: true) {
                    refreshControl.endRefreshing()
                }
            }
            .backport
            .refreshable {
                await model.loadResources(force: true)
            }
            #endif
        }

        #if !os(tvOS)
        .background(
            Button("Refresh") {
                model.loadResources(force: true)
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
        #endif
        #if !os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            model.loadResources()
        }
        #endif
    }
}

struct SubscriptonsView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionsView()
    }
}
