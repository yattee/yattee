import Foundation
import Siesta
import SwiftUI

final class Subscriptions: ObservableObject {
    @Published var channels = [Channel]()

    var resource: Resource {
        InvidiousAPI.shared.subscriptions
    }

    init() {
        load()
    }

    var all: [Channel] {
        channels.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func subscribe(_ channelID: String, onSuccess: @escaping () -> Void = {}) {
        performChannelSubscriptionRequest(channelID, method: .post, onSuccess: onSuccess)
    }

    func unsubscribe(_ channelID: String, onSuccess: @escaping () -> Void = {}) {
        performChannelSubscriptionRequest(channelID, method: .delete, onSuccess: onSuccess)
    }

    func isSubscribing(_ channelID: String) -> Bool {
        channels.contains { $0.id == channelID }
    }

    fileprivate func load(onSuccess: @escaping () -> Void = {}) {
        resource.load().onSuccess { resource in
            if let channels: [Channel] = resource.typedContent() {
                self.channels = channels
                onSuccess()
            }
        }
    }

    fileprivate func performChannelSubscriptionRequest(_ channelID: String, method: RequestMethod, onSuccess: @escaping () -> Void = {}) {
        InvidiousAPI.shared.channelSubscription(channelID).request(method).onCompletion { _ in
            self.load(onSuccess: onSuccess)
        }
    }
}
