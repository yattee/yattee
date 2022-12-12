import Cache
import Foundation
import Logging
import Siesta
import SwiftUI
import SwiftyJSON

final class SubscribedChannelsModel: ObservableObject, CacheModel {
    static var shared = SubscribedChannelsModel()
    let logger = Logger(label: "stream.yattee.cache.channels")

    static let diskConfig = DiskConfig(name: "channels")
    static let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, JSON>(
        diskConfig: SubscribedChannelsModel.diskConfig,
        memoryConfig: SubscribedChannelsModel.memoryConfig,
        transformer: BaseCacheModel.jsonTransformer
    )

    @Published var isLoading = false
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
        guard accounts.app.supportsSubscriptions, !isLoading, accounts.signedIn, let account = accounts.current else {
            channels = []
            return
        }

        loadCachedChannels(account)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let request = force ? self.resource?.load() : self.resource?.loadIfNeeded()

            if request != nil {
                self.isLoading = true
            }

            request?
                .onCompletion { [weak self] _ in
                    self?.isLoading = false
                }
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
    }

    func loadCachedChannels(_ account: Account) {
        let cache = getChannels(account: account)
        if !cache.isEmpty {
            DispatchQueue.main.async {
                self.channels = cache
            }
        }
    }

    func storeChannels(account: Account, channels: [Channel]) {
        let date = iso8601DateFormatter.string(from: Date())
        logger.info("caching channels \(channelsDateCacheKey(account)) -- \(date)")

        let dateObject: JSON = ["date": date]
        let channelsObject: JSON = ["channels": channels.map(\.json).map(\.object)]

        try? storage?.setObject(dateObject, forKey: channelsDateCacheKey(account))
        try? storage?.setObject(channelsObject, forKey: channelsCacheKey(account))
    }

    func getChannels(account: Account) -> [Channel] {
        logger.info("getting channels \(channelsDateCacheKey(account))")

        if let json = try? storage?.object(forKey: channelsCacheKey(account)),
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

    private func channelsCacheKey(_ account: Account) -> String {
        "channels-\(account.id)"
    }

    private func channelsDateCacheKey(_ account: Account) -> String {
        "channels-\(account.id)-date"
    }

    func getChannelsTime(account: Account) -> Date? {
        if let json = try? storage?.object(forKey: channelsDateCacheKey(account)),
           let string = json.dictionaryValue["date"]?.string,
           let date = iso8601DateFormatter.date(from: string)
        {
            return date
        }

        return nil
    }

    var channelsTime: Date? {
        if let account = accounts.current {
            return getChannelsTime(account: account)
        }

        return nil
    }

    var formattedCacheTime: String {
        getFormattedDate(channelsTime)
    }
}
