import Foundation
import SwiftUI

struct UnsubscribeAlertModifier: ViewModifier {
    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<Subscriptions> private var subscriptions

    func body(content: Content) -> some View {
        content
            .alert(unsubscribeAlertTitle, isPresented: $navigationState.presentingUnsubscribeAlert) {
                if let channel = navigationState.channelToUnsubscribe {
                    Button("Unsubscribe", role: .destructive) {
                        subscriptions.unsubscribe(channel.id) {
                            navigationState.openChannel(channel)
                            navigationState.sidebarSectionChanged.toggle()
                        }
                    }
                }
            }
    }

    var unsubscribeAlertTitle: String {
        if let channel = navigationState.channelToUnsubscribe {
            return "Unsubscribe from \(channel.name)"
        }

        return "Unknown channel"
    }
}
