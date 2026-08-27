//
//  SubscriptionAccountValidator.swift
//  Yattee
//
//  Validates subscription account selection and handles auto-correction
//  when the selected account becomes unavailable.
//

import Foundation

/// Validates subscription account selection and provides available accounts for the picker.
/// Automatically corrects to a valid account if the current selection becomes invalid.
@MainActor
@Observable
final class SubscriptionAccountValidator {
    // MARK: - Dependencies

    private let settingsManager: SettingsManager
    private let instancesManager: InstancesManager
    private let invidiousCredentialsManager: InvidiousCredentialsManager
    private let pipedCredentialsManager: PipedCredentialsManager
    private let toastManager: ToastManager
    private let feedCache: SubscriptionFeedCache
    /// Availability is decided by accounts now: a login created after the
    /// revamp writes only an account-scoped Keychain key, so the instance-keyed
    /// check this validator used would never see it.
    private weak var accountsManager: AccountsManager?

    // MARK: - Observation State

    private var observationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        settingsManager: SettingsManager,
        instancesManager: InstancesManager,
        invidiousCredentialsManager: InvidiousCredentialsManager,
        pipedCredentialsManager: PipedCredentialsManager,
        toastManager: ToastManager,
        feedCache: SubscriptionFeedCache
    ) {
        self.settingsManager = settingsManager
        self.instancesManager = instancesManager
        self.invidiousCredentialsManager = invidiousCredentialsManager
        self.pipedCredentialsManager = pipedCredentialsManager
        self.toastManager = toastManager
        self.feedCache = feedCache

        startObserving()
    }

    func setAccountsManager(_ manager: AccountsManager) {
        accountsManager = manager
    }

    /// Whether any account on this instance is usable.
    private func hasSignedInAccount(for instance: Instance) -> Bool {
        guard let accountsManager else { return false }
        return accountsManager.accounts(forInstance: instance.id)
            .contains { accountsManager.status(for: $0.id) == .signedIn }
    }

    /// Stops observation. Call before releasing the validator.
    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Available Accounts

    /// Available subscription accounts based on current configuration.
    /// Only includes accounts that are properly configured and authenticated.
    var availableAccounts: [SubscriptionAccount] {
        var accounts: [SubscriptionAccount] = []

        // Add local if Yattee Server is configured and enabled
        let hasYatteeServer = instancesManager.instances.contains {
            $0.type == .yatteeServer && $0.isEnabled
        }
        if hasYatteeServer {
            accounts.append(.local)
        }

        // Add logged-in and enabled Invidious instances
        for instance in instancesManager.instances {
            if instance.type == .invidious &&
               instance.isEnabled &&
               hasSignedInAccount(for: instance) {
                accounts.append(.invidious(instance.id))
            }
        }

        // Add logged-in and enabled Piped instances
        for instance in instancesManager.instances {
            if instance.type == .piped &&
               instance.isEnabled &&
               hasSignedInAccount(for: instance) {
                accounts.append(.piped(instance.id))
            }
        }

        return accounts
    }

    /// Whether any subscription accounts are available.
    var hasAvailableAccounts: Bool {
        !availableAccounts.isEmpty
    }

    // MARK: - Validation

    /// Whether the current subscription account is valid.
    var isCurrentAccountValid: Bool {
        let current = settingsManager.subscriptionAccount
        return availableAccounts.contains(current)
    }

    /// Validates the current account and auto-corrects if invalid.
    /// Call this on app launch and when configuration changes.
    func validateAndCorrectIfNeeded() {
        guard !isCurrentAccountValid else {
            LoggingService.shared.debug(
                "Current subscription account is valid: \(settingsManager.subscriptionAccount.type)",
                category: .general
            )
            return
        }

        // A selection whose account still exists is never corrected here. This
        // validator predates account-scoped credentials and reads "not signed
        // in" as "not available", which is now routinely temporary — an
        // unresolved identity scope, or a credential iCloud Keychain has yet to
        // deliver. Correcting on that would silently discard the user's choice
        // and desynchronize this setting from the data context, which is
        // preserved. Only a deletion removes an account, and that path corrects
        // the context and this setting together.
        if let instanceID = settingsManager.subscriptionAccount.instanceID,
           let accountsManager,
           !accountsManager.accounts(forInstance: instanceID).isEmpty {
            LoggingService.shared.debug(
                "Leaving the subscription account alone — its login has not been removed",
                category: .general
            )
            return
        }

        let previousAccount = settingsManager.subscriptionAccount

        // Find first available account to switch to
        if let newAccount = availableAccounts.first {
            settingsManager.subscriptionAccount = newAccount
            adoptCorrectedSelection(newAccount)
            feedCache.handleAccountChange()

            let newName = displayName(for: newAccount)
            LoggingService.shared.info(
                "Auto-corrected subscription account from \(previousAccount.type) to \(newAccount.type)",
                category: .general
            )

            toastManager.showInfo(
                String(localized: "subscriptions.accountSwitched.title"),
                subtitle: newName
            )
        } else {
            // No valid accounts available - set to local anyway
            // The feed will show an appropriate error state
            settingsManager.subscriptionAccount = .local
            adoptCorrectedSelection(.local)
            feedCache.handleAccountChange()

            LoggingService.shared.warning(
                "No valid subscription accounts available, defaulting to local",
                category: .general
            )
        }
    }

    /// Moves the data context with a correction made to the legacy setting.
    ///
    /// Reads and writes resolve through the context now, so correcting only the
    /// legacy value would leave the picker naming one account while the data
    /// came from another.
    private func adoptCorrectedSelection(_ account: SubscriptionAccount) {
        guard let accountsManager else { return }

        let context = accountsManager.context(forLegacyInstanceID: account.instanceID)
        guard context != accountsManager.currentContext else { return }

        accountsManager.setContext(context)
    }

    // MARK: - Display Names

    /// Returns a display name for the given subscription account.
    func displayName(for account: SubscriptionAccount) -> String {
        switch account.type {
        case .local:
            return String(localized: "subscriptions.account.local")

        case .invidious:
            guard let instanceID = account.instanceID,
                  let instance = instancesManager.instances.first(where: { $0.id == instanceID }) else {
                return String(localized: "subscriptions.account.invidious")
            }
            // Use instance name if available, otherwise use hostname
            let instanceName: String
            if let name = instance.name, !name.isEmpty {
                instanceName = name
            } else {
                instanceName = instance.url.host ?? "Invidious"
            }
            return String(localized: "subscriptions.account.invidiousInstance \(instanceName)")

        case .piped:
            guard let instanceID = account.instanceID,
                  let instance = instancesManager.instances.first(where: { $0.id == instanceID }) else {
                return String(localized: "subscriptions.account.piped")
            }
            // Use instance name if available, otherwise use hostname
            let instanceName: String
            if let name = instance.name, !name.isEmpty {
                instanceName = name
            } else {
                instanceName = instance.url.host ?? "Piped"
            }
            return String(localized: "subscriptions.account.pipedInstance \(instanceName)")
        }
    }

    /// Returns the instance for an Invidious or Piped account, if available.
    func instance(for account: SubscriptionAccount) -> Instance? {
        guard account.type == .invidious || account.type == .piped,
              let instanceID = account.instanceID else {
            return nil
        }
        return instancesManager.instances.first { $0.id == instanceID }
    }

    // MARK: - Observation

    /// Starts observing changes to instances and credentials.
    private func startObserving() {
        observationTask?.cancel()

        observationTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                // Wait for changes using withObservationTracking
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        // Access the observed properties to register for tracking
                        _ = self.instancesManager.instances
                        _ = self.invidiousCredentialsManager.loggedInInstanceIDs
                        _ = self.pipedCredentialsManager.loggedInInstanceIDs
                    } onChange: {
                        // Resume when a change is detected
                        continuation.resume()
                    }
                }

                guard !Task.isCancelled else { break }

                // Small delay to batch rapid changes
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { break }

                // Validate after changes
                self.validateAndCorrectIfNeeded()
            }
        }
    }
}
