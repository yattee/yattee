import Siesta
import SwiftUI

struct ChannelVideosView: View {
    let channel: Channel

    @StateObject private var store = Store<Channel>()

    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @Environment(\.inNavigationView) private var inNavigationView

    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Namespace private var focusNamespace

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

            VideosCellsVertical(videos: store.item?.videos ?? [])

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
        let resource = api.channel(channel.id)
        resource.addObserver(store)

        return resource
    }

    #if !os(tvOS)
        var subscriptionToolbarItemPlacement: ToolbarItemPlacement {
            #if os(iOS)
                if horizontalSizeClass == .regular {
                    return .primaryAction // swiftlint:disable:this implicit_return
                }
            #endif

            return .automatic
        }
    #endif

    var subscriptionToggleButton: some View {
        Group {
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

    var navigationTitle: String {
        store.item?.name ?? channel.name
    }
}
