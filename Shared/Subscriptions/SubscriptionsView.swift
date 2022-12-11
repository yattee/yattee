import Defaults
import SwiftUI

struct SubscriptionsView: View {
    enum Page: String, CaseIterable, Defaults.Serializable {
        case feed
        case channels
    }

    @Default(.subscriptionsViewPage) private var subscriptionsViewPage

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

        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                subscriptionsMenu
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
            } label: {
                HStack(spacing: 12) {
                    Text(menuLabel)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .transaction { t in t.animation = nil }
            }
        }

        var menuLabel: String {
            subscriptionsViewPage == .channels ? "Channels" : "Feed"
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
