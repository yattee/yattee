import Foundation
import Siesta
import SwiftUI

final class SubscriptionsModel: ObservableObject {
    static var shared = SubscriptionsModel()

    @Published var channels = [Channel]()
    var accounts: AccountsModel { .shared }

    var resource: Resource? {
        accounts.api.subscriptions
    }

    var all: [Channel] {
        channels.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func subscribe(_ channelID: String, onSuccess: @escaping () -> Void = {}) {
        accounts.api.subscribe(channelID) {
            self.scheduleLoad(onSuccess: onSuccess)
        }
    }

    func unsubscribe(_ channelID: String, onSuccess: @escaping () -> Void = {}) {
        accounts.api.unsubscribe(channelID) {
            self.scheduleLoad(onSuccess: onSuccess)
        }
    }

    func isSubscribing(_ channelID: String) -> Bool {
        channels.contains { $0.id == channelID }
    }

    func load(force: Bool = false, onSuccess: @escaping () -> Void = {}) {
        guard accounts.app.supportsSubscriptions, accounts.signedIn else {
            channels = []
            return
        }

        let request = force ? resource?.load() : resource?.loadIfNeeded()

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

    private func scheduleLoad(onSuccess: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.load(force: true, onSuccess: onSuccess)
        }
    }
}
