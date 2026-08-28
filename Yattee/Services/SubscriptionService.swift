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

    /// One provider per account, built on demand and kept so its in-memory
    /// subscription cache survives context switches.
    private var accountProviders: [UUID: any SubscriptionProvider] = [:]

    private weak var accountsManager: AccountsManager?
    private weak var contextValidator: DataContextValidator?

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

        // Account providers are built lazily: which accounts exist is not known
        // until AccountsManager has loaded and iCloud has delivered instances.
        self.localProvider = LocalSubscriptionProvider(dataManager: dataManager)
    }

    func setContextValidator(_ validator: DataContextValidator) {
        contextValidator = validator
    }

    func setAccountsManager(_ manager: AccountsManager) {
        accountsManager = manager

        // Providers cache another identity's subscriptions in memory, so they
        // cannot outlive a change of Apple Account.
        NotificationCenter.default.addObserver(
            forName: .credentialIdentityScopeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.discardAllProviders() }
        }

        // Switching context deliberately keeps the providers — each is one
        // account's cache and stays valid — but a fetch already running belongs
        // to the account that was selected when it started, and finishing after
        // the switch would put its channels on screen for another one.
        NotificationCenter.default.addObserver(
            forName: .dataContextDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.providerGeneration += 1 }
        }
    }

    // MARK: - Current Provider

    /// The provider for a context, built on first use.
    ///
    /// Returns nil for an account whose instance or backend cannot supply
    /// subscriptions — a caller that gets nil must surface that rather than
    /// quietly falling back to local data the user did not select.
    func provider(for context: DataContext) -> (any SubscriptionProvider)? {
        switch context {
        case .local:
            return localProvider

        case let .account(id):
            if let existing = accountProviders[id] { return existing }

            guard let accountsManager,
                  let account = accountsManager.account(id: id),
                  let instance = accountsManager.instance(for: account),
                  instance.type.accountCapabilities.supportsSubscriptions
            else { return nil }

            let provider: (any SubscriptionProvider)?
            switch instance.type {
            case .invidious:
                provider = InvidiousSubscriptionProvider(
                    account: account,
                    invidiousAPI: invidiousAPI,
                    credentialsManager: invidiousCredentialsManager,
                    accountsManager: accountsManager,
                    settingsManager: settingsManager
                )
            case .piped:
                provider = PipedSubscriptionProvider(
                    account: account,
                    pipedAPI: pipedAPI,
                    credentialsManager: pipedCredentialsManager,
                    accountsManager: accountsManager,
                    settingsManager: settingsManager
                )
            default:
                provider = nil
            }

            accountProviders[id] = provider
            return provider
        }
    }

    /// Drops a removed account's provider so its cached subscriptions cannot be
    /// served after the account is gone.
    func discardProvider(for accountID: UUID) {
        accountProviders[accountID] = nil
        providerGeneration += 1
    }

    /// Drops every cached provider, for a change of Apple account.
    ///
    /// Bumping the generation is the half that matters: emptying the dictionary
    /// only affects future lookups, while a fetch already awaiting a response
    /// still holds its provider and would otherwise deliver the previous
    /// identity's subscriptions.
    func discardAllProviders() {
        accountProviders.removeAll()
        providerGeneration += 1
    }

    /// Which generation of logins the cached providers belong to. Bumped
    /// whenever one is discarded, so a fetch that outlived its provider can be
    /// told from a current one.
    fileprivate var providerGeneration = 0

    /// The provider for **writes**.
    ///
    /// Always the raw selected context, never the read fallback: a subscribe
    /// must fail visibly when the account is unavailable rather than silently
    /// landing in local data the user did not choose.
    var currentProvider: (any SubscriptionProvider)? {
        provider(for: currentContext)
    }

    /// The provider for **reads**.
    ///
    /// Uses the validator's effective context, which falls back to local while
    /// the selected account is waiting on its instance or credential. The
    /// fallback is not persisted, so the user's choice takes effect again on
    /// its own once the account resolves.
    var readProvider: (any SubscriptionProvider)? {
        provider(for: contextValidator?.effectiveContext ?? currentContext)
    }

    /// The selected context, or `.local` before accounts have loaded.
    var currentContext: DataContext {
        accountsManager?.currentContext ?? .local
    }

    /// Subscription count for the active account, when known without a network fetch.
    /// Always available for local accounts; nil for server accounts until their cache is populated.
    var cachedSubscriptionCount: Int? {
        readProvider?.cachedSubscriptionCount
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
            postChangeNotificationForServerAccount()
            LoggingService.shared.info(
                "Subscribed to \(channel.name) via \(provider.context)",
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
            postChangeNotificationForServerAccount()
            LoggingService.shared.info(
                "Unsubscribed from \(channelID) via \(provider.context)",
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
        guard let provider = readProvider else {
            return false
        }
        return await provider.isSubscribed(to: channelID)
    }

    /// Fetches all subscriptions from the current provider.
    /// - Returns: Array of subscribed channels.
    func fetchSubscriptions() async throws -> [Channel] {
        guard let provider = readProvider else {
            throw SubscriptionError.providerNotAvailable
        }

        isLoading = true
        lastError = nil

        // Dropping a provider from the cache does not stop a fetch it has
        // already started: the running task holds it, and the result would
        // arrive afterwards as the current account's subscriptions. Signing in
        // again or switching Apple account changes neither the context nor the
        // account ID, so nothing else downstream would notice.
        let generation = providerGeneration

        do {
            let channels = try await provider.fetchSubscriptions()
            isLoading = false

            guard generation == providerGeneration else {
                LoggingService.shared.info(
                    "Discarding subscriptions fetched for a login that has since been replaced",
                    category: .general
                )
                throw SubscriptionError.providerNotAvailable
            }

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
        guard (contextValidator?.effectiveContext ?? currentContext).isLocal else {
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
        guard let provider = readProvider else {
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

    // MARK: - Import

    /// Imports parsed external subscriptions (YouTube CSV / OPML) into the active account.
    /// Local accounts write to SwiftData; server accounts subscribe on the server,
    /// one channel at a time. Channels that are already subscribed are skipped.
    func importSubscriptions(_ channels: [(channelID: String, name: String)]) async -> (imported: Int, skipped: Int) {
        guard !currentContext.isLocal else {
            return dataManager.importSubscriptionsFromExternal(channels)
        }

        guard let provider = currentProvider else { return (0, channels.count) }

        // Populate the cache so already-subscribed channels can be skipped
        try? await provider.refreshCache()

        var imported = 0
        var skipped = 0
        for entry in channels {
            if await provider.isSubscribed(to: entry.channelID) {
                skipped += 1
                continue
            }
            do {
                try await provider.subscribe(to: Channel(id: .global(entry.channelID), name: entry.name))
                imported += 1
            } catch {
                skipped += 1
                LoggingService.shared.error(
                    "Failed to import subscription \(entry.channelID): \(error.localizedDescription)",
                    category: .general
                )
            }
        }

        if imported > 0 {
            postChangeNotificationForServerAccount()
        }

        return (imported, skipped)
    }

    // MARK: - Private Helpers

    /// Posts a subscriptions-changed notification for server accounts.
    /// Local accounts already post it from DataManager with a change payload.
    private func postChangeNotificationForServerAccount() {
        guard !currentContext.isLocal else { return }
        NotificationCenter.default.post(name: .subscriptionsDidChange, object: nil)
    }
}
