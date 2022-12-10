import Cache
import Foundation
import Logging
import Siesta
import SwiftUI
import SwiftyJSON

final class SubscriptionsModel: ObservableObject {
    static var shared = SubscriptionsModel()
    let logger = Logger(label: "stream.yattee.cache.channels")

    static let diskConfig = DiskConfig(name: "channels")
    static let memoryConfig = MemoryConfig()

    let storage = try! Storage<String, JSON>(
        diskConfig: SubscriptionsModel.diskConfig,
        memoryConfig: SubscriptionsModel.memoryConfig,
        transformer: CacheModel.jsonTransformer
    )

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
        guard accounts.app.supportsSubscriptions, accounts.signedIn, let account = accounts.current else {
            channels = []
            return
        }

        loadCachedChannels(account)

        let request = force ? resource?.load() : resource?.loadIfNeeded()

        request?
            .onSuccess { resource in
                if let channels: [Channel] = resource.typedContent() {
                    self.channels = channels
                    self.storeChannels(account: account, channels: channels)
                    onSuccess()
                }
            }
            .onFailure { _ in
                self.channels = []
            }
    }

    func loadCachedChannels(_ account: Account) {
        let cache = getChannels(account: account)
        if !cache.isEmpty {
            channels = cache
        }
    }

    func storeChannels(account: Account, channels: [Channel]) {
        let date = dateFormatter.string(from: Date())
        logger.info("caching channels \(channelsDateCacheKey(account)) -- \(date)")

        let dateObject: JSON = ["date": date]
        let channelsObject: JSON = ["channels": channels.map(\.json).map(\.object)]

        try? storage.setObject(dateObject, forKey: channelsDateCacheKey(account))
        try? storage.setObject(channelsObject, forKey: channelsCacheKey(account))
    }

    func getChannels(account: Account) -> [Channel] {
        logger.info("getting channels \(channelsDateCacheKey(account))")

        if let json = try? storage.object(forKey: channelsCacheKey(account)),
           let channels = json.dictionaryValue["channels"]
        {
            return channels.arrayValue.map { Channel.from($0) }
        }

        return []
    }

    private func scheduleLoad(onSuccess: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.load(force: true, onSuccess: onSuccess)
        }
    }

    private var dateFormatter: ISO8601DateFormatter {
        .init()
    }

    private func channelsCacheKey(_ account: Account) -> String {
        "channels-\(account.id)"
    }

    private func channelsDateCacheKey(_ account: Account) -> String {
        "channels-\(account.id)-date"
    }
}
