//
//  DataContextValidator.swift
//  Yattee
//
//  Decides whether the selected data context can be used right now.
//

import Foundation

/// Why the selected context cannot be used at the moment.
enum DataContextUnavailability: Hashable, Sendable {
    /// Nothing is known yet: the Apple account the credentials are keyed by is
    /// still being established, so the Keychain cannot be read under the right
    /// scope. Never render this as "sign in required".
    case checking
    /// The account exists but its instance hasn't arrived from iCloud yet.
    case instancePending
    /// The account's instance has been switched off. The selection is kept —
    /// the user can turn the instance back on — but nothing may be served from
    /// or written to a server they have disabled.
    case instanceDisabled
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

            guard let instance = accountsManager.instance(for: account) else {
                return .temporarilyUnavailable(.instancePending)
            }

            // The account's own status says nothing about the instance being
            // switched off, and `availableContexts` already hides disabled
            // instances — a context that stayed valid here would keep sending
            // requests to a server the user has turned off.
            guard instance.isEnabled else {
                return .temporarilyUnavailable(.instanceDisabled)
            }

            switch accountsManager.status(for: id) {
            case .signedIn: return .valid
            case .checking: return .temporarilyUnavailable(.checking)
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
    /// Called after deletions and on foreground activation. A timeout, a failed
    /// fetch or a record that simply has not arrived must never move anything —
    /// those are all "unknown", and treating them as removal is how a user
    /// loses their selection during a slow sync. Only the deletion tombstone
    /// counts, and the repair it triggers is never published.
    func correctIfContextRemoved() {
        // An unresolved identity has not loaded anybody's accounts yet, so
        // neither the selection nor the tombstones read here are the ones this
        // device will end up with.
        guard accountsManager.isIdentityResolved else { return }

        // The manager owns the decision: it holds the tombstones, and it
        // repairs the same way an account deleted right now would be — onto a
        // signed-in login on the same server when there is one, keeping the
        // replaced choice's timestamp and publishing nothing.
        guard accountsManager.correctContextIfAccountDeleted() else { return }

        toastManager.showInfo(
            String(localized: "subscriptions.accountSwitched.title"),
            subtitle: displayName(for: accountsManager.currentContext)
        )

        LoggingService.shared.info(
            "Selected account was deleted — data context repaired",
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

    /// User-set label, else whatever the account falls back to.
    func displayName(for account: Account) -> String {
        if let name = account.displayName, !name.isEmpty { return name }
        return defaultDisplayName(for: account)
    }

    /// What the account is called with no user-set label: the stored login
    /// identifier, else the source's name, else its host.
    ///
    /// Device-local by nature. The username lives in the Keychain beside the
    /// credential rather than in synced metadata, so it is only available on a
    /// device that is signed in — two devices holding the very same account can
    /// legitimately fall back to different names for it.
    func defaultDisplayName(for account: Account) -> String {
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

    /// What a rename field's contents mean once the user is done typing.
    ///
    /// `nil` clears the user-set label and hands the account back to
    /// `defaultDisplayName`; anything else is stored as typed.
    ///
    /// The question the field cannot answer on its own is what an *untouched*
    /// save means. The field starts prefilled with the label the row shows, and
    /// on an account with no user-set label that label is device-local — the
    /// login identifier only exists where the credential does. Saving it
    /// unedited must not turn one device's fallback into a synced label every
    /// other device is then made to display, so that case clears instead.
    ///
    /// The test is editedness, never equality with the default: on a second
    /// device the string that device happens to fall back to is a perfectly
    /// ordinary name to *choose*, and typing it has to store and sync like any
    /// other. An unedited save on an account that already carries a label
    /// re-states that label, which the manager then drops as a no-op — the name
    /// stays, rather than being silently cleared by a tap that changed nothing.
    static func renamedDisplayName(
        _ input: String,
        prefilledWith prefill: String,
        hasUserSetLabel: Bool
    ) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let wasEdited = trimmed != prefill.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wasEdited || hasUserSetLabel else { return nil }

        return trimmed
    }
}
