import Siesta
import SwiftUI

struct ChannelVideosView: View {
    let channel: Channel

    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<Subscriptions> private var subscriptions

    @Environment(\.inNavigationView) private var inNavigationView

    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @ObservedObject private var store = Store<Channel>()

    @Namespace private var focusNamespace

    init(_ channel: Channel) {
        self.channel = channel

        resource.addObserver(store)
    }

    var body: some View {
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

            VideosView(videos: store.item?.videos ?? [])

            #if !os(iOS)
                .prefersDefaultFocus(in: focusNamespace)
            #endif
        }
        #if !os(iOS)
            .focusScope(focusNamespace)
        #endif
        #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: subscriptionToolbarItemPlacement) {
                    HStack {
                        if let channel = store.item, let subscribers = channel.subscriptionsString {
                            Text("**\(subscribers)** subscribers")
                                .foregroundColor(.secondary)
                        }

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
        #endif
        .modifier(UnsubscribeAlertModifier())
            .onAppear {
                resource.loadIfNeeded()
            }
            .navigationTitle(navigationTitle)
    }

    var resource: Resource {
        InvidiousAPI.shared.channel(channel.id)
    }

    #if !os(tvOS)
        var subscriptionToolbarItemPlacement: ToolbarItemPlacement {
            #if os(iOS)
                if horizontalSizeClass == .regular {
                    return .primaryAction
                }
            #endif

            return .status
        }
    #endif

    var subscriptionToggleButton: some View {
        Group {
            if subscriptions.isSubscribing(channel.id) {
                Button("Unsubscribe") {
                    navigationState.presentUnsubscribeAlert(channel)
                }
            } else {
                Button("Subscribe") {
                    subscriptions.subscribe(channel.id) {
                        navigationState.sidebarSectionChanged.toggle()
                    }
                }
            }
        }
    }

    var navigationTitle: String {
        store.item?.name ?? channel.name
    }
}
