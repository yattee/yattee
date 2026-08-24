//
//  DataContextValidator.swift
//  Yattee
//
//  Decides whether the selected data context can be used right now.
//

import Foundation

/// Why the selected context cannot be used at the moment.
enum DataContextUnavailability: Hashable, Sendable {
    /// The account exists but its instance hasn't arrived from iCloud yet.
    case instancePending
    /// No credential on this device yet. On tvOS this never resolves on its own
    /// — app Keychain items are not synced there — so the UI offers a local
    /// sign-in rather than implying a wait.
    case credentialMissing
    /// The server rejected the credential; the user must sign in again.
    case credentialRejected
    /// The server could not be reached.
    case unreachable
}

/// The three states a context can be in.
///
/// The distinction that matters is between *unknown* and *gone*. Anything that
/// might still resolve — a slow iCloud Keychain, an instance that hasn't synced
/// — is `temporarilyUnavailable` and leaves the user's choice untouched. Only
/// a deletion the app can point at turns into `removed`.
enum DataContextValidity: Hashable, Sendable {
    case valid
    case temporarilyUnavailable(DataContextUnavailability)
    case removed

    var isValid: Bool { self == .valid }
}

/// Validates the selected `DataContext` and supplies the list of switchable
/// contexts.
///
/// Replaces `SubscriptionAccountValidator`, which auto-corrected on any
/// selection it could not immediately verify. That was safe when a context
/// could only be "an instance I am logged into", but with credentials arriving
/// asynchronously it would silently discard the user's choice during a slow
/// Keychain sync — so correction is now restricted to deletions.
@MainActor
@Observable
final class DataContextValidator {
    private let accountsManager: AccountsManager
    private let instancesManager: InstancesManager
    private let toastManager: ToastManager
    private weak var appEnvironment: AppEnvironment?

    init(
        accountsManager: AccountsManager,
        instancesManager: InstancesManager,
        toastManager: ToastManager
    ) {
        self.accountsManager = accountsManager
        self.instancesManager = instancesManager
        self.toastManager = toastManager
    }

    func setAppEnvironment(_ environment: AppEnvironment) {
        appEnvironment = environment
    }

    // MARK: - Validity

    var validity: DataContextValidity {
        validity(of: accountsManager.currentContext)
    }

    func validity(of context: DataContext) -> DataContextValidity {
        switch context {
        case .local:
            // Local data is always present. The feed additionally needs a
            // Yattee Server, but that is a feed-level concern, not a reason to
            // reject the context.
            return .valid

        case let .account(id):
            guard let account = accountsManager.account(id: id) else {
                // Absence is not proof. An account can be missing because it
                // hasn't synced yet; only an actual deletion removes it, and
                // that path corrects the context directly.
                return .temporarilyUnavailable(.instancePending)
            }

            guard accountsManager.instance(for: account) != nil else {
                return .temporarilyUnavailable(.instancePending)
            }

            switch accountsManager.status(for: id) {
            case .signedIn: return .valid
            case .credentialMissing: return .temporarilyUnavailable(.credentialMissing)
            case .credentialRejected: return .temporarilyUnavailable(.credentialRejected)
            case .unreachable: return .temporarilyUnavailable(.unreachable)
            }
        }
    }

    /// The context reads should actually use.
    ///
    /// Falls back to `.local` while the selected context is unusable, but the
    /// fallback is **never persisted** — the moment the credential or instance
    /// arrives, the user's choice takes effect again without them having to
    /// reselect it.
    var effectiveContext: DataContext {
        validity.isValid ? accountsManager.currentContext : .local
    }

    /// Whether writes may be sent to the current context's server.
    ///
    /// Deliberately not the same as having a read fallback: a subscribe or a
    /// playlist edit must fail visibly rather than being redirected into local
    /// data the user did not choose.
    var allowsServerMutations: Bool {
        validity.isValid
    }

    /// Set while the selected context is unusable, for the banner.
    var unavailability: DataContextUnavailability? {
        if case let .temporarilyUnavailable(reason) = validity { return reason }
        return nil
    }

    // MARK: - Available contexts

    /// Every context the user can switch to.
    ///
    /// Includes accounts that are currently signed out: hiding them would make
    /// a temporarily unreachable account look deleted, and the switcher is
    /// where the user goes to fix exactly that.
    var availableContexts: [DataContext] {
        let accountContexts = accountsManager.selectableAccounts
            .filter { accountsManager.instance(for: $0)?.isEnabled ?? false }
            .map { DataContext.account($0.id) }

        return [.local] + accountContexts
    }

    // MARK: - Correction

    /// Corrects the context only when the selected account is provably gone.
    ///
    /// Called after deletions. A timeout, a failed fetch or a missing record
    /// must never reach here — those are all "unknown", and treating them as
    /// removal is how a user loses their selection during a slow sync.
    func correctIfContextRemoved() {
        guard case let .account(id) = accountsManager.currentContext else { return }
        guard accountsManager.account(id: id) == nil else { return }

        // Only an explicit deletion clears the account from the store, so
        // reaching here means the account really is gone.
        accountsManager.setContext(.local)

        toastManager.showInfo(
            String(localized: "subscriptions.accountSwitched.title"),
            subtitle: String(localized: "subscriptions.account.local")
        )

        LoggingService.shared.info(
            "Selected account was deleted — data context reset to local",
            category: .general
        )
    }

    // MARK: - Display

    func displayName(for context: DataContext) -> String {
        switch context {
        case .local:
            return String(localized: "subscriptions.account.local")

        case let .account(id):
            guard let account = accountsManager.account(id: id) else {
                return String(localized: "subscriptions.account.local")
            }
            return displayName(for: account)
        }
    }

    /// User-set label, else the stored login identifier, else the host.
    ///
    /// The username lives in the Keychain beside the credential rather than in
    /// synced metadata, so it is only available on a device that is signed in.
    func displayName(for account: Account) -> String {
        if let name = account.displayName, !name.isEmpty { return name }

        if let username = appEnvironment?
            .accountCredentialsManager(for: account)?
            .username(for: account),
            !username.isEmpty {
            if let host = accountsManager.instance(for: account)?.url.host {
                return "\(username)@\(host)"
            }
            return username
        }

        if let instance = accountsManager.instance(for: account) {
            if let name = instance.name, !name.isEmpty { return name }
            return instance.url.host ?? instance.type.displayName
        }

        return String(localized: "accounts.status.instanceMissing")
    }
}
