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

    /// The account this provider is bound to. One provider per account, so two
    /// logins on the same instance never share a subscription cache.
    let account: Account

    private let invidiousAPI: InvidiousAPI
    private let credentialsManager: InvidiousCredentialsManager
    private let accountsManager: AccountsManager

    /// Records the outcome of a server call against the account. The
    /// classification lives in one place so the feed cache, which talks to the
    /// same servers without going through a provider, reaches the same verdict.
    private func recordOutcome(_ error: Error?, credential: String) {
        // Only for the secret the request actually used. Signing in again — or
        // a switch of Apple account — replaces it under the same key while a
        // request is still out, and a late 401 would otherwise reject the
        // replacement, or a late success clear a rejection it never earned.
        guard credentialsManager.credential(for: account) == credential else { return }

        accountsManager.recordServerOutcome(error, for: account)
    }

    /// In-memory cache of subscribed channel IDs for fast lookup.
    private var cachedChannelIDs: Set<String> = []

    /// In-memory cache of full channel data for display.
    private var cachedChannels: [Channel] = []

    /// Whether the cache has been populated from the server.
    private var cachePopulated = false

    // MARK: - Initialization

    init(
        account: Account,
        invidiousAPI: InvidiousAPI,
        credentialsManager: InvidiousCredentialsManager,
        accountsManager: AccountsManager,
        settingsManager: SettingsManager
    ) {
        self.account = account
        self.invidiousAPI = invidiousAPI
        self.credentialsManager = credentialsManager
        self.accountsManager = accountsManager
    }

    // MARK: - SubscriptionProvider

    func fetchSubscriptions() async throws -> [Channel] {
        let (instance, sid) = try await getAuthenticatedInstance()
        
        // Fetch subscriptions from Invidious
        let subscriptions = try await tracking(credential: sid) {
            try await invidiousAPI.subscriptions(instance: instance, sid: sid)
        }
        
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
        try await tracking(credential: sid) {
            try await invidiousAPI.subscribe(to: channel.id.channelID, instance: instance, sid: sid)
        }
        
        // Update in-memory cache only
        cachedChannelIDs.insert(channel.id.channelID)
        if !cachedChannels.contains(where: { $0.id.channelID == channel.id.channelID }) {
            cachedChannels.append(channel)
        }
        
        LoggingService.shared.info("Subscribed to \(channel.name) on Invidious", category: .api)
    }

    func unsubscribe(from channelID: String) async throws {
        let (instance, sid) = try await getAuthenticatedInstance()
        
        // Unsubscribe on Invidious server. Tracked like every other
        // authenticated call: a rejected credential noticed here must mark the
        // account, or it keeps reporting itself as signed in.
        try await tracking(credential: sid) {
            try await invidiousAPI.unsubscribe(from: channelID, instance: instance, sid: sid)
        }
        
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

    var cachedSubscriptionCount: Int? {
        cachePopulated ? cachedChannels.count : nil
    }

    var cachedSubscriptions: [Channel]? {
        cachePopulated ? cachedChannels : nil
    }

    // MARK: - Private Helpers

    /// Gets the authenticated Invidious instance and session ID from account settings.
    /// Runs a server call and records what it implies about the credential.
    private func tracking<T>(credential: String, _ operation: () async throws -> T) async rethrows -> T {
        do {
            let value = try await operation()
            recordOutcome(nil, credential: credential)
            return value
        } catch {
            recordOutcome(error, credential: credential)
            throw error
        }
    }

    private func getAuthenticatedInstance() async throws -> (Instance, String) {
        // The account names its instance directly - no falling back to
        // "some enabled Invidious instance", which could silently send one
        // account's request to a server it has no credential for.
        guard let instance = accountsManager.instance(for: account), instance.isEnabled else {
            throw SubscriptionProviderError.instanceNotConfigured
        }

        guard let sid = credentialsManager.credential(for: account) else {
            throw SubscriptionProviderError.notAuthenticated
        }

        return (instance, sid)
    }
}
