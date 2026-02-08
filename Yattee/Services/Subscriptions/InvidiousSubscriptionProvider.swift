//
//  InvidiousSubscriptionProvider.swift
//  Yattee
//
//  Invidious subscription provider that manages subscriptions on an Invidious instance.
//  Uses in-memory cache only - does NOT persist to SwiftData to avoid corrupting local subscriptions.
//

import Foundation

/// Invidious subscription provider that syncs with an Invidious instance account.
/// Subscriptions are managed on the Invidious server and kept in memory only.
/// This provider does NOT write to SwiftData to preserve local subscriptions.
@MainActor
final class InvidiousSubscriptionProvider: SubscriptionProvider {
    // MARK: - Properties

    let accountType: SubscriptionAccountType = .invidious

    private let invidiousAPI: InvidiousAPI
    private let credentialsManager: InvidiousCredentialsManager
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
        invidiousAPI: InvidiousAPI,
        credentialsManager: InvidiousCredentialsManager,
        instancesManager: InstancesManager,
        settingsManager: SettingsManager
    ) {
        self.invidiousAPI = invidiousAPI
        self.credentialsManager = credentialsManager
        self.instancesManager = instancesManager
        self.settingsManager = settingsManager
    }

    // MARK: - SubscriptionProvider

    func fetchSubscriptions() async throws -> [Channel] {
        let (instance, sid) = try await getAuthenticatedInstance()
        
        // Fetch subscriptions from Invidious
        let subscriptions = try await invidiousAPI.subscriptions(instance: instance, sid: sid)
        
        // Update in-memory cache
        cachedChannelIDs = Set(subscriptions.map(\.authorId))
        cachedChannels = subscriptions.map { $0.toChannel(baseURL: instance.url) }
        cachePopulated = true
        
        LoggingService.shared.info("Fetched \(subscriptions.count) Invidious subscriptions", category: .api)
        
        return cachedChannels
    }

    func subscribe(to channel: Channel) async throws {
        let (instance, sid) = try await getAuthenticatedInstance()
        
        // Subscribe on Invidious server
        try await invidiousAPI.subscribe(to: channel.id.channelID, instance: instance, sid: sid)
        
        // Update in-memory cache only
        cachedChannelIDs.insert(channel.id.channelID)
        if !cachedChannels.contains(where: { $0.id.channelID == channel.id.channelID }) {
            cachedChannels.append(channel)
        }
        
        LoggingService.shared.info("Subscribed to \(channel.name) on Invidious", category: .api)
    }

    func unsubscribe(from channelID: String) async throws {
        let (instance, sid) = try await getAuthenticatedInstance()
        
        // Unsubscribe on Invidious server
        try await invidiousAPI.unsubscribe(from: channelID, instance: instance, sid: sid)
        
        // Update in-memory cache only
        cachedChannelIDs.remove(channelID)
        cachedChannels.removeAll { $0.id.channelID == channelID }
        
        LoggingService.shared.info("Unsubscribed from \(channelID) on Invidious", category: .api)
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

    /// Gets the authenticated Invidious instance and session ID from account settings.
    private func getAuthenticatedInstance() async throws -> (Instance, String) {
        // Get the instance ID from subscription account settings
        let account = settingsManager.subscriptionAccount

        let instance: Instance?
        if let instanceID = account.instanceID {
            // Use the specific instance from account settings
            instance = instancesManager.instances.first { $0.id == instanceID && $0.isEnabled }
        } else {
            // Fallback to first enabled Invidious instance
            instance = instancesManager.instances.first { $0.type == .invidious && $0.isEnabled }
        }

        guard let instance else {
            throw SubscriptionProviderError.instanceNotConfigured
        }

        // Get session ID
        guard let sid = credentialsManager.sid(for: instance) else {
            throw SubscriptionProviderError.notAuthenticated
        }

        return (instance, sid)
    }
}
