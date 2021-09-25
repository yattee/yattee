import Foundation
import SwiftUI

struct UnsubscribeAlertModifier: ViewModifier {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    func body(content: Content) -> some View {
        content
            .alert(unsubscribeAlertTitle, isPresented: $navigation.presentingUnsubscribeAlert) {
                if let channel = navigation.channelToUnsubscribe {
                    Button("Unsubscribe", role: .destructive) {
                        subscriptions.unsubscribe(channel.id)
                    }
                }
            }
    }

    var unsubscribeAlertTitle: String {
        if let channel = navigation.channelToUnsubscribe {
            return "Unsubscribe from \(channel.name)"
        }

        return "Unknown channel"
    }
}
