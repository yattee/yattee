//
//  PipedSubscriptionProvider.swift
//  Yattee
//
//  Piped subscription provider that manages subscriptions on a Piped instance.
//  Uses in-memory cache only - does NOT persist to SwiftData to avoid corrupting local subscriptions.
//

import Foundation

/// Piped subscription provider that syncs with a Piped instance account.
/// Subscriptions are managed on the Piped server and kept in memory only.
/// This provider does NOT write to SwiftData to preserve local subscriptions.
@MainActor
final class PipedSubscriptionProvider: SubscriptionProvider {
    // MARK: - Properties

    let accountType: SubscriptionAccountType = .piped

    private let pipedAPI: PipedAPI
    private let credentialsManager: PipedCredentialsManager
    private let instancesManager: InstancesManager
    private let settingsManager: SettingsManager

    /// In-memory cache of subscribed channel IDs for fast lookup.
    private var cachedChannelIDs: Set<String> = []

    /// In-memory cache of full channel data for display.
    private var cachedChannels: [Channel] = []

    /// Whether the cache has been populated from the server.
    private var cachePopulated = false

    // MARK: - Initialization

    init(
        pipedAPI: PipedAPI,
        credentialsManager: PipedCredentialsManager,
        instancesManager: InstancesManager,
        settingsManager: SettingsManager
    ) {
        self.pipedAPI = pipedAPI
        self.credentialsManager = credentialsManager
        self.instancesManager = instancesManager
        self.settingsManager = settingsManager
    }

    // MARK: - SubscriptionProvider

    func fetchSubscriptions() async throws -> [Channel] {
        let (instance, authToken) = try await getAuthenticatedInstance()

        // Fetch subscriptions from Piped
        let subscriptions = try await pipedAPI.subscriptions(instance: instance, authToken: authToken)

        // Update in-memory cache
        cachedChannelIDs = Set(subscriptions.map(\.channelId))
        cachedChannels = subscriptions.map { $0.toChannel() }
        cachePopulated = true

        LoggingService.shared.info("Fetched \(subscriptions.count) Piped subscriptions", category: .api)

        return cachedChannels
    }

    func subscribe(to channel: Channel) async throws {
        let (instance, authToken) = try await getAuthenticatedInstance()

        // Subscribe on Piped server
        try await pipedAPI.subscribe(channelID: channel.id.channelID, instance: instance, authToken: authToken)

        // Update in-memory cache only
        cachedChannelIDs.insert(channel.id.channelID)
        if !cachedChannels.contains(where: { $0.id.channelID == channel.id.channelID }) {
            cachedChannels.append(channel)
        }

        LoggingService.shared.info("Subscribed to \(channel.name) on Piped", category: .api)
    }

    func unsubscribe(from channelID: String) async throws {
        let (instance, authToken) = try await getAuthenticatedInstance()

        // Unsubscribe on Piped server
        try await pipedAPI.unsubscribe(channelID: channelID, instance: instance, authToken: authToken)

        // Update in-memory cache only
        cachedChannelIDs.remove(channelID)
        cachedChannels.removeAll { $0.id.channelID == channelID }

        LoggingService.shared.info("Unsubscribed from \(channelID) on Piped", category: .api)
    }

    func isSubscribed(to channelID: String) async -> Bool {
        // If cache isn't populated yet, try to refresh it
        if !cachePopulated {
            do {
                _ = try await fetchSubscriptions()
            } catch {
                // Can't determine subscription status without server connection
                return false
            }
        }
        return cachedChannelIDs.contains(channelID)
    }

    func refreshCache() async throws {
        // Simply fetch subscriptions again - this updates in-memory cache
        _ = try await fetchSubscriptions()
    }

    // MARK: - Private Helpers

    /// Gets the authenticated Piped instance and auth token from account settings.
    private func getAuthenticatedInstance() async throws -> (Instance, String) {
        // Get the instance ID from subscription account settings
        let account = settingsManager.subscriptionAccount

        let instance: Instance?
        if let instanceID = account.instanceID {
            // Use the specific instance from account settings
            instance = instancesManager.instances.first { $0.id == instanceID && $0.isEnabled }
        } else {
            // Fallback to first enabled Piped instance
            instance = instancesManager.instances.first { $0.type == .piped && $0.isEnabled }
        }

        guard let instance else {
            throw SubscriptionProviderError.instanceNotConfigured
        }

        // Get auth token
        guard let authToken = credentialsManager.credential(for: instance) else {
            throw SubscriptionProviderError.notAuthenticated
        }

        return (instance, authToken)
    }
}
