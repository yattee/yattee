//
//  SubscriptionService.swift
//  Yattee
//
//  Service for managing subscriptions through the selected provider.
//  Supports local (iCloud) and Invidious account subscriptions.
//

import Foundation

/// Errors that can occur during subscription operations.
enum SubscriptionError: LocalizedError, Sendable {
    case alreadySubscribed
    case notSubscribed
    case providerNotAvailable
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadySubscribed:
            return String(localized: "subscription.error.alreadySubscribed")
        case .notSubscribed:
            return String(localized: "subscription.error.notSubscribed")
        case .providerNotAvailable:
            return String(localized: "subscription.error.providerNotAvailable")
        case .operationFailed(let message):
            return message
        }
    }
}

/// Service that manages subscriptions through the selected subscription provider.
/// The provider is determined by the user's subscription account setting.
@MainActor
@Observable
final class SubscriptionService {
    // MARK: - Dependencies

    private let dataManager: DataManager
    private let settingsManager: SettingsManager
    private let instancesManager: InstancesManager
    private let invidiousCredentialsManager: InvidiousCredentialsManager
    private let pipedCredentialsManager: PipedCredentialsManager
    private let invidiousAPI: InvidiousAPI
    private let pipedAPI: PipedAPI

    // MARK: - Providers

    private var localProvider: LocalSubscriptionProvider?
    private var invidiousProvider: InvidiousSubscriptionProvider?
    private var pipedProvider: PipedSubscriptionProvider?

    // MARK: - State

    /// Whether a subscription operation is in progress.
    private(set) var isLoading = false

    /// The last error that occurred.
    private(set) var lastError: Error?

    // MARK: - Initialization

    init(
        dataManager: DataManager,
        settingsManager: SettingsManager,
        instancesManager: InstancesManager,
        invidiousCredentialsManager: InvidiousCredentialsManager,
        pipedCredentialsManager: PipedCredentialsManager,
        invidiousAPI: InvidiousAPI,
        pipedAPI: PipedAPI
    ) {
        self.dataManager = dataManager
        self.settingsManager = settingsManager
        self.instancesManager = instancesManager
        self.invidiousCredentialsManager = invidiousCredentialsManager
        self.pipedCredentialsManager = pipedCredentialsManager
        self.invidiousAPI = invidiousAPI
        self.pipedAPI = pipedAPI

        // Initialize providers
        self.localProvider = LocalSubscriptionProvider(dataManager: dataManager)
        self.invidiousProvider = InvidiousSubscriptionProvider(
            invidiousAPI: invidiousAPI,
            credentialsManager: invidiousCredentialsManager,
            instancesManager: instancesManager,
            settingsManager: settingsManager
        )
        self.pipedProvider = PipedSubscriptionProvider(
            pipedAPI: pipedAPI,
            credentialsManager: pipedCredentialsManager,
            instancesManager: instancesManager,
            settingsManager: settingsManager
        )
    }

    // MARK: - Current Provider

    /// Returns the current subscription provider based on the user's account setting.
    var currentProvider: (any SubscriptionProvider)? {
        let account = settingsManager.subscriptionAccount

        switch account.type {
        case .local:
            return localProvider
        case .invidious:
            return invidiousProvider
        case .piped:
            return pipedProvider
        }
    }

    /// The current subscription account type.
    var currentAccountType: SubscriptionAccountType {
        settingsManager.subscriptionAccount.type
    }

    // MARK: - Subscribe

    /// Subscribes to a channel using the current provider.
    /// - Parameter channel: The channel to subscribe to.
    /// - Throws: SubscriptionProviderError if the operation fails.
    func subscribe(to channel: Channel) async throws {
        guard let provider = currentProvider else {
            throw SubscriptionError.providerNotAvailable
        }

        isLoading = true
        lastError = nil

        do {
            try await provider.subscribe(to: channel)
            LoggingService.shared.info(
                "Subscribed to \(channel.name) via \(provider.accountType)",
                category: .general
            )
        } catch {
            lastError = error
            LoggingService.shared.error(
                "Failed to subscribe to \(channel.name): \(error.localizedDescription)",
                category: .general
            )
            throw error
        }

        isLoading = false
    }

    /// Subscribes to a channel from an Author.
    /// - Parameters:
    ///   - author: The author/channel to subscribe to.
    ///   - source: The content source.
    func subscribe(to author: Author, source: ContentSource) async throws {
        let channel = Channel(
            id: ChannelID(source: source, channelID: author.id),
            name: author.name,
            subscriberCount: author.subscriberCount,
            thumbnailURL: author.thumbnailURL
        )
        try await subscribe(to: channel)
    }

    // MARK: - Unsubscribe

    /// Unsubscribes from a channel using the current provider.
    /// - Parameter channelID: The channel ID to unsubscribe from.
    /// - Throws: SubscriptionProviderError if the operation fails.
    func unsubscribe(from channelID: String) async throws {
        guard let provider = currentProvider else {
            throw SubscriptionError.providerNotAvailable
        }

        isLoading = true
        lastError = nil

        do {
            try await provider.unsubscribe(from: channelID)
            LoggingService.shared.info(
                "Unsubscribed from \(channelID) via \(provider.accountType)",
                category: .general
            )
        } catch {
            lastError = error
            LoggingService.shared.error(
                "Failed to unsubscribe from \(channelID): \(error.localizedDescription)",
                category: .general
            )
            throw error
        }

        isLoading = false
    }

    // MARK: - Query

    /// Checks if subscribed to a channel.
    /// - Parameter channelID: The channel ID to check.
    /// - Returns: `true` if subscribed, `false` otherwise.
    func isSubscribed(to channelID: String) async -> Bool {
        guard let provider = currentProvider else {
            return false
        }
        return await provider.isSubscribed(to: channelID)
    }

    /// Fetches all subscriptions from the current provider.
    /// - Returns: Array of subscribed channels.
    func fetchSubscriptions() async throws -> [Channel] {
        guard let provider = currentProvider else {
            throw SubscriptionError.providerNotAvailable
        }

        isLoading = true
        lastError = nil

        do {
            let channels = try await provider.fetchSubscriptions()
            isLoading = false
            return channels
        } catch {
            lastError = error
            isLoading = false
            throw error
        }
    }

    /// Synchronously fetches subscriptions for local provider.
    /// Returns nil if the current provider is not local (requires async fetch).
    func fetchSubscriptionsSync() -> [Channel]? {
        guard currentAccountType == .local else {
            return nil
        }

        return dataManager.subscriptions().map { subscription in
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

    /// Refreshes the subscription cache from the current provider.
    func refreshCache() async throws {
        guard let provider = currentProvider else {
            throw SubscriptionError.providerNotAvailable
        }

        isLoading = true
        lastError = nil

        do {
            try await provider.refreshCache()
            isLoading = false
        } catch {
            lastError = error
            isLoading = false
            throw error
        }
    }

    // MARK: - Synchronous Helpers (for backwards compatibility)

    /// Synchronously checks if subscribed to a channel.
    /// Uses cached data from DataManager for instant response.
    /// - Parameter channelID: The channel ID to check.
    /// - Returns: `true` if subscribed (based on local cache), `false` otherwise.
    func isSubscribedSync(to channelID: String) -> Bool {
        dataManager.isSubscribed(to: channelID)
    }

    /// Synchronously subscribes to a channel (local provider only).
    /// For Invidious provider, this will only update local cache.
    /// - Parameter channel: The channel to subscribe to.
    func subscribeSync(to channel: Channel) {
        dataManager.subscribe(to: channel)
    }

    /// Synchronously unsubscribes from a channel (local provider only).
    /// For Invidious provider, this will only update local cache.
    /// - Parameter channelID: The channel ID to unsubscribe from.
    func unsubscribeSync(from channelID: String) {
        dataManager.unsubscribe(from: channelID)
    }
}
