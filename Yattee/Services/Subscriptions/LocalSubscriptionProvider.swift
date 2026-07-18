//
//  LocalSubscriptionProvider.swift
//  Yattee
//
//  Local subscription provider using SwiftData with iCloud sync.
//  This is the default provider when using "Yattee (iCloud)" subscription account.
//

import Foundation

/// Local subscription provider that stores subscriptions in SwiftData.
/// Syncs with iCloud via CloudKitSyncEngine.
@MainActor
final class LocalSubscriptionProvider: SubscriptionProvider {
    // MARK: - Properties

    let accountType: SubscriptionAccountType = .local
    private let dataManager: DataManager

    // MARK: - Initialization

    init(dataManager: DataManager) {
        self.dataManager = dataManager
    }

    // MARK: - SubscriptionProvider

    func fetchSubscriptions() async throws -> [Channel] {
        // Convert Subscription models to Channel models
        dataManager.subscriptions().map { subscription in
            Channel(
                id: ChannelID(source: subscription.contentSource, channelID: subscription.channelID),
                name: subscription.name,
                description: subscription.channelDescription,
                subscriberCount: subscription.subscriberCount,
                thumbnailURL: subscription.avatarURL,
                bannerURL: subscription.bannerURL,
                isVerified: subscription.isVerified
            )
        }
    }

    func subscribe(to channel: Channel) async throws {
        // Check if already subscribed
        if dataManager.isSubscribed(to: channel.id.channelID) {
            throw SubscriptionProviderError.alreadySubscribed
        }
        dataManager.subscribe(to: channel)
    }

    func unsubscribe(from channelID: String) async throws {
        // Check if subscribed
        guard dataManager.isSubscribed(to: channelID) else {
            throw SubscriptionProviderError.notSubscribed
        }
        dataManager.unsubscribe(from: channelID)
    }

    func isSubscribed(to channelID: String) async -> Bool {
        dataManager.isSubscribed(to: channelID)
    }

    func refreshCache() async throws {
        // Local provider doesn't need cache refresh - data is already local
    }
}
