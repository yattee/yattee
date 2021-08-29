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

    func subscribe(_ channelID: String) {
        performChannelSubscriptionRequest(channelID, method: .post)
    }

    func unsubscribe(_ channelID: String) {
        performChannelSubscriptionRequest(channelID, method: .delete)
    }

    func subscribed(_ channelID: String) -> Bool {
        channels.contains { $0.id == channelID }
    }

    fileprivate func load() {
        resource.load().onSuccess { resource in
            if let channels: [Channel] = resource.typedContent() {
                self.channels = channels
            }
        }
    }

    fileprivate func performChannelSubscriptionRequest(_ channelID: String, method: RequestMethod) {
        InvidiousAPI.shared.channelSubscription(channelID).request(method).onCompletion { _ in
            self.load()
        }
    }
}
