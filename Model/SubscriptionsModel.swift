import Foundation
import Siesta
import SwiftUI

final class SubscriptionsModel: ObservableObject {
    @Published var channels = [Channel]()
    @Published var api: InvidiousAPI!

    var resource: Resource {
        api.subscriptions
    }

    init(api: InvidiousAPI? = nil) {
        self.api = api
    }

    var all: [Channel] {
        channels.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func subscribe(_ channelID: String, onSuccess: @escaping () -> Void = {}) {
        performRequest(channelID, method: .post, onSuccess: onSuccess)
    }

    func unsubscribe(_ channelID: String, onSuccess: @escaping () -> Void = {}) {
        performRequest(channelID, method: .delete, onSuccess: onSuccess)
    }

    func isSubscribing(_ channelID: String) -> Bool {
        channels.contains { $0.id == channelID }
    }

    func load(force: Bool = false, onSuccess: @escaping () -> Void = {}) {
        let request = force ? resource.load() : resource.loadIfNeeded()

        request?
            .onSuccess { resource in
                if let channels: [Channel] = resource.typedContent() {
                    self.channels = channels
                    onSuccess()
                }
            }
            .onFailure { _ in
                self.channels = []
            }
    }

    fileprivate func performRequest(_ channelID: String, method: RequestMethod, onSuccess: @escaping () -> Void = {}) {
        api.channelSubscription(channelID).request(method).onCompletion { _ in
            self.load(force: true, onSuccess: onSuccess)
        }
    }
}
