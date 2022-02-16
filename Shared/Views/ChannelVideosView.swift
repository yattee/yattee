import Siesta
import SwiftUI

struct ChannelVideosView: View {
    let channel: Channel

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?
    @State private var subscriptionToggleButtonDisabled = false

    @StateObject private var store = Store<Channel>()

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.inNavigationView) private var inNavigationView
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @EnvironmentObject<PlayerModel> private var player
    #endif

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @Namespace private var focusNamespace

    var videos: [ContentItem] {
        ContentItem.array(of: store.item?.videos ?? [])
    }

    var body: some View {
        #if os(iOS)
            if inNavigationView {
                content
            } else {
                BrowserPlayerControls {
                    content
                }
            }
        #else
            BrowserPlayerControls {
                content
            }
        #endif
    }

    var content: some View {
        let content = VStack {
            #if os(tvOS)
                HStack {
                    Text(navigationTitle)
                        .font(.title2)
                        .frame(alignment: .leading)

                    Spacer()

                    FavoriteButton(item: FavoriteItem(section: .channel(channel.id, channel.name)))
                        .labelStyle(.iconOnly)

                    if let subscribers = store.item?.subscriptionsString {
                        Text("**\(subscribers)** subscribers")
                            .foregroundColor(.secondary)
                    }

                    subscriptionToggleButton
                }
                .frame(maxWidth: .infinity)
            #endif

            VerticalCells(items: videos)
                .environment(\.inChannelView, true)
            #if os(tvOS)
                .prefersDefaultFocus(in: focusNamespace)
            #endif
        }

        #if !os(tvOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ShareButton(
                    contentItem: contentItem,
                    presentingShareSheet: $presentingShareSheet,
                    shareURL: $shareURL
                )
            }

            ToolbarItem {
                HStack {
                    HStack(spacing: 3) {
                        Text("\(store.item?.subscriptionsString ?? "loading")")
                            .fontWeight(.bold)
                        Text(" subscribers")
                    }
                    .allowsTightening(true)
                    .foregroundColor(.secondary)
                    .opacity(store.item?.subscriptionsString != nil ? 1 : 0)

                    subscriptionToggleButton

                    FavoriteButton(item: FavoriteItem(section: .channel(channel.id, channel.name)))
                }
            }
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $presentingShareSheet) {
            if let shareURL = shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        #endif
        .onAppear {
            if store.item.isNil {
                resource.addObserver(store)
                resource.load()
            }
        }
        #if os(iOS)
        .navigationBarHidden(player.playerNavigationLinkActive)
        #endif
        .navigationTitle(navigationTitle)

        return Group {
            if #available(macOS 12.0, *) {
                content
                #if os(tvOS)
                .background(Color.background(scheme: colorScheme))
                #endif
                #if !os(iOS)
                .focusScope(focusNamespace)
                #endif
            } else {
                content
            }
        }
    }

    private var resource: Resource {
        let resource = accounts.api.channel(channel.id)
        resource.addObserver(store)

        return resource
    }

    private var subscriptionToggleButton: some View {
        Group {
            if accounts.app.supportsSubscriptions && accounts.signedIn {
                if subscriptions.isSubscribing(channel.id) {
                    Button("Unsubscribe") {
                        subscriptionToggleButtonDisabled = true

                        subscriptions.unsubscribe(channel.id) {
                            subscriptionToggleButtonDisabled = false
                        }
                    }
                } else {
                    Button("Subscribe") {
                        subscriptionToggleButtonDisabled = true

                        subscriptions.subscribe(channel.id) {
                            subscriptionToggleButtonDisabled = false
                            navigation.sidebarSectionChanged.toggle()
                        }
                    }
                }
            }
        }
        .disabled(subscriptionToggleButtonDisabled)
    }

    private var contentItem: ContentItem {
        ContentItem(channel: channel)
    }

    private var navigationTitle: String {
        store.item?.name ?? channel.name
    }
}
