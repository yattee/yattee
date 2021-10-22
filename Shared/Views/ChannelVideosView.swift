import Siesta
import SwiftUI

struct ChannelVideosView: View {
    let channel: Channel

    @StateObject private var store = Store<Channel>()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.inNavigationView) private var inNavigationView

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                PlayerControlsView {
                    content
                }
            }
        #else
            PlayerControlsView {
                content
            }
        #endif
    }

    var content: some View {
        VStack {
            #if os(tvOS)
                HStack {
                    Text(navigationTitle)
                        .font(.title2)
                        .frame(alignment: .leading)

                    Spacer()

                    if let subscribers = store.item?.subscriptionsString {
                        Text("**\(subscribers)** subscribers")
                            .foregroundColor(.secondary)
                    }

                    subscriptionToggleButton
                }
                .frame(maxWidth: .infinity)
            #endif

            VerticalCells(items: videos)

            #if !os(iOS)
                .prefersDefaultFocus(in: focusNamespace)
            #endif
        }
        #if !os(iOS)
            .focusScope(focusNamespace)
        #endif
        #if !os(tvOS)
            .toolbar {
                ToolbarItem {
                    HStack {
                        Text("**\(store.item?.subscriptionsString ?? "loading")** subscribers")
                            .foregroundColor(.secondary)
                            .opacity(store.item?.subscriptionsString != nil ? 1 : 0)

                        subscriptionToggleButton
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    if inNavigationView {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        #else
            .background(.thickMaterial)
        #endif
        .modifier(UnsubscribeAlertModifier())
            .onAppear {
                if store.item.isNil {
                    resource.addObserver(store)
                    resource.load()
                }
            }
            .navigationTitle(navigationTitle)
    }

    var resource: Resource {
        let resource = accounts.api.channel(channel.id)
        resource.addObserver(store)

        return resource
    }

    var subscriptionToggleButton: some View {
        Group {
            if accounts.app.supportsSubscriptions && accounts.signedIn {
                if subscriptions.isSubscribing(channel.id) {
                    Button("Unsubscribe") {
                        navigation.presentUnsubscribeAlert(channel)
                    }
                } else {
                    Button("Subscribe") {
                        subscriptions.subscribe(channel.id) {
                            navigation.sidebarSectionChanged.toggle()
                        }
                    }
                }
            }
        }
    }

    var navigationTitle: String {
        store.item?.name ?? channel.name
    }
}
