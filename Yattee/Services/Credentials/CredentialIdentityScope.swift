//
//  CredentialIdentityScope.swift
//  Yattee
//
//  Resolves the Apple-account scope that Keychain credentials are keyed by.
//

import CloudKit
import Foundation

/// Resolves the identity scope that account credentials are namespaced under.
///
/// ### Why credentials are scoped at all
///
/// Apple documents that Keychain data may remain on device when a user signs
/// out of their Apple account and chooses to keep it, and Yattee's credential
/// managers query `kSecAttrSynchronizableAny`. An unscoped key would therefore
/// hand a credential retained from Apple account A to whoever signs in next —
/// and for migrated accounts that collision is *guaranteed*, because local
/// instances survive an Apple-account switch and the migrated account UUID is
/// deterministically the instance UUID.
///
/// Measured on iPadOS 27.0: a synchronizable item retained across a sign-out
/// keeps `kSecAttrSynchronizable = true` and still matches a strict
/// `== true` query with **no** Apple account signed in — so the attribute
/// cannot be used to tell "belongs to the current account" from "left over
/// from the previous one". Scoping the key is the only reliable defence, and
/// legacy items are never adopted automatically (see
/// ``AccountKeychainCredentials/adoptLegacyCredential(for:)``).
///
/// ### Why the CloudKit user record, not the ubiquity token
///
/// The scope has to be identical on every device signed in to the same Apple
/// account, or iCloud Keychain sync would stop working — each device would
/// write under a different key. `FileManager.ubiquityIdentityToken` carries no
/// such cross-device guarantee, so the CloudKit user record ID is the scope
/// value; the ubiquity token is used only as a synchronous, offline-capable
/// signal that the account *changed*.
@MainActor
@Observable
final class CredentialIdentityScope {
    /// Scope used when no Apple account is available — signed out, or a
    /// sideloaded build with no iCloud entitlement.
    static let localScope = CloudKitIdentity.localScope

    enum State: Equatable {
        /// Signed in, but the CloudKit user record hasn't been fetched yet.
        /// Credential access is refused in this state: writing under a guessed
        /// scope is exactly the mistake scoping exists to prevent.
        case unresolved
        case resolved(String)
    }

    private(set) var state: State = .unresolved

    /// Fingerprint of the Apple account the current state belongs to.
    /// A change here means the scope must be re-resolved.
    private(set) var fingerprint: String?

    private let defaults: UserDefaults
    private let resolveUserRecordID: @Sendable () async -> String?
    private let fingerprintProvider: @Sendable () -> String?
    private let accountAvailabilityProvider: @Sendable () async -> CloudKitIdentity.AccountAvailability
    /// Backoff between attempts. Injectable so tests don't pay real seconds.
    private let retryDelay: @Sendable (Int) async -> Void
    /// Written only on the main actor; read in `deinit`, which runs after the
    /// last reference is gone and so cannot race with it.
    private nonisolated(unsafe) var identityChangeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var cloudKitAccountObserver: NSObjectProtocol?

    private static let cacheKey = "credentialIdentityScopeCache"

    /// Attempts made for the Apple account currently being resolved. Reset
    /// whenever the identity changes.
    private var resolutionAttempts = 0
    private var isResolving = false
    /// Set when a resolution is requested while one is already running — the
    /// running one is for a now-stale identity and will bail on the fingerprint
    /// check, so the request has to be replayed rather than dropped.
    private var pendingResolve = false
    /// Whether the current scope was resolved with no ubiquity token behind it.
    ///
    /// Such a scope has no fingerprint to compare against, so an Apple-account
    /// switch produces no token change to observe — it has to be revalidated
    /// against CloudKit instead.
    private var resolvedWithoutToken = false
    /// Bumped on every observed Apple-account change.
    ///
    /// The fingerprint alone cannot order async results: with no ubiquity token
    /// it is `nil` before *and* after a switch, so comparing it would accept
    /// the previous account's in-flight lookup as current. Every async
    /// operation captures this and refuses to apply its result if it moved.
    private var identityGeneration = 0
    private static let maxResolutionAttempts = 4

    /// The resolved scope, or `nil` while unresolved.
    var current: String? {
        if case let .resolved(scope) = state { return scope }
        return nil
    }

    /// Assigns `state` and announces a genuine change of scope.
    ///
    /// Everything namespaced by identity — the account list, its outbox, cached
    /// per-account providers — has to be reloaded when this moves, or the
    /// previous Apple Account's data stays on screen under the new one.
    private func setState(_ newState: State) {
        let previous = current
        state = newState
        guard current != previous else { return }

        // Posted with the scope as the object: everything namespaced by identity
        // observes *its* scope, so an unrelated one resolving cannot make it
        // throw away state that never belonged to that scope.
        NotificationCenter.default.post(name: .credentialIdentityScopeDidChange, object: self)
    }

    var isResolved: Bool { current != nil }

    init(
        defaults: UserDefaults = .standard,
        fingerprintProvider: @escaping @Sendable () -> String? = { CloudKitIdentity.ubiquityFingerprint },
        resolveUserRecordID: @escaping @Sendable () async -> String? = { await CloudKitIdentity.userRecordID() },
        accountAvailabilityProvider: @escaping @Sendable () async -> CloudKitIdentity.AccountAvailability = {
            await CloudKitIdentity.accountAvailability()
        },
        retryDelay: @escaping @Sendable (Int) async -> Void = { attempt in
            try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
        }
    ) {
        self.defaults = defaults
        self.fingerprintProvider = fingerprintProvider
        self.resolveUserRecordID = resolveUserRecordID
        self.accountAvailabilityProvider = accountAvailabilityProvider
        self.retryDelay = retryDelay
        adoptCurrentIdentity()
        observeIdentityChanges()
    }

    deinit {
        if let identityChangeObserver {
            NotificationCenter.default.removeObserver(identityChangeObserver)
        }
        if let cloudKitAccountObserver {
            NotificationCenter.default.removeObserver(cloudKitAccountObserver)
        }
    }

    /// Re-scopes as soon as the Apple account changes under a running app.
    ///
    /// Without this the scope would stay pinned to whichever account was
    /// signed in at launch, and a sign-out or switch mid-session would let
    /// reads and writes reach the previous account's retained credentials —
    /// the exact leak scoping exists to prevent.
    private func observeIdentityChanges() {
        // Two signals, because neither covers the other. The ubiquity token
        // changes only when iCloud Drive is available; with it switched off the
        // token stays nil across a switch and only CloudKit notices.
        identityChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.identityDidChange(source: "ubiquity token") }
        }

        cloudKitAccountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.identityDidChange(source: "CloudKit account") }
        }
    }

    /// Handles an observed Apple-account change. Internal so tests can drive it
    /// deterministically instead of racing a notification.
    func identityDidChange(source: String) {
        LoggingService.shared.info(
            "Apple account changed (\(source)) — re-resolving the credential identity scope",
            category: .keychain
        )

        // Invalidates every in-flight lookup: results captured under the old
        // generation are refused even when the fingerprint looks unchanged.
        identityGeneration += 1

        // The budget belongs to the identity being resolved, so it resets on
        // every change — not only the tokenless branch below. A previous
        // identity that exhausted its attempts would otherwise leave the new
        // one with none, and its queued resolve() would do no work at all.
        resolutionAttempts = 0

        // A tokenless scope cannot be re-derived by `adoptCurrentIdentity()`
        // (there is no fingerprint to compare), so drop it outright: continuing
        // to serve it would hand the previous account's credentials to the new
        // one.
        if resolvedWithoutToken {
            setState(.unresolved)
            resolvedWithoutToken = false
        }

        adoptCurrentIdentity()
        Task { await resolve() }
    }

    /// Test seam: a scope pinned up front, never consulting CloudKit.
    /// `nil` pins the unresolved state.
    init(fixedScope: String?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fingerprintProvider = { nil }
        resolveUserRecordID = { nil }
        accountAvailabilityProvider = { .indeterminate }
        retryDelay = { _ in }
        fingerprint = nil
        state = fixedScope.map { State.resolved($0) } ?? .unresolved
    }

    // MARK: - Resolution

    /// Re-reads the Apple account and restores the cached scope if there is
    /// one. Synchronous and offline-capable, so it is safe at launch.
    ///
    /// Call again on `.accountChange`: a switch that happened while the app was
    /// closed shows up here, before any CloudKit request could report it.
    func adoptCurrentIdentity() {
        let current = fingerprintProvider()
        if current != fingerprint {
            resolutionAttempts = 0
            identityGeneration += 1
        }
        fingerprint = current

        guard CloudKitAvailability.isAvailable else {
            // No iCloud entitlement: nothing can sync, and there is no ambient
            // identity for a retained credential to leak to.
            resolvedWithoutToken = false
            setState(.resolved(Self.localScope))
            return
        }

        guard let current else {
            // A nil token does NOT establish sign-out — Foundation also returns
            // nil when iCloud Drive is unavailable or switched off, and Yattee
            // declares only the CloudKit service. Scoping to `local` here would
            // collapse two different signed-in Apple accounts into one
            // namespace, which is exactly the collision this class prevents.
            // CloudKit's account status settles it during resolution.
            setState(.unresolved)
            return
        }

        if let cached = cachedScope(for: current) {
            resolvedWithoutToken = false
            setState(.resolved(cached))
        } else {
            setState(.unresolved)
        }
    }

    /// Fetches the CloudKit user record and caches it against the current
    /// Apple account, so every later launch resolves synchronously.
    ///
    /// Only the first resolution for a given Apple account needs the network.
    /// While it is outstanding, credential access reports "can't tell yet"
    /// rather than "not signed in" — callers must not treat that as a missing
    /// credential.
    func resolve() async {
        guard !isResolved else { return }

        // A resolution already running is for whatever identity was current
        // when it started. If that is no longer this one it will bail on its
        // fingerprint check, so the request has to be replayed afterwards
        // rather than dropped — otherwise a switch mid-flight leaves the new
        // identity unresolved until a foreground transition or relaunch.
        guard !isResolving else {
            pendingResolve = true
            return
        }

        isResolving = true
        defer { isResolving = false }

        repeat {
            pendingResolve = false
            await performResolution()
        } while pendingResolve && !isResolved
    }

    private func performResolution() async {
        // Captured before the first await so a switch mid-flight can be
        // detected: a record ID fetched under account A must never be cached
        // for B.
        let requested = fingerprint
        let generation = identityGeneration

        // Labelled: an unqualified `break` inside the switch below would leave
        // only the switch and fall through to the user-record lookup, which
        // must not run when the account status is undetermined.
        attempts: while resolutionAttempts < Self.maxResolutionAttempts {
            resolutionAttempts += 1

            // With no ubiquity token, only CloudKit can distinguish "signed
            // out" (where `local` is correct) from "signed in but iCloud Drive
            // is off" (where `local` would be a cross-account collision).
            if requested == nil {
                switch await accountAvailabilityProvider() {
                case .noAccount:
                    guard identityGeneration == generation,
                          fingerprintProvider() == nil, fingerprint == nil else { return }
                    resolvedWithoutToken = true
                    setState(.resolved(Self.localScope))
                    LoggingService.shared.info(
                        "No Apple account — credentials scoped locally",
                        category: .keychain
                    )
                    return
                case .available:
                    break // fall through to the user-record lookup below
                case .indeterminate:
                    guard resolutionAttempts < Self.maxResolutionAttempts else { break attempts }
                    await retryDelay(resolutionAttempts)
                    guard identityGeneration == generation, fingerprint == requested else { return }
                    continue attempts
                }
            }

            if let recordID = await resolveUserRecordID() {
                guard identityGeneration == generation,
                      fingerprintProvider() == requested, fingerprint == requested else {
                    LoggingService.shared.info(
                        "Discarding credential scope resolved for a previous Apple account",
                        category: .keychain
                    )
                    return
                }

                // Only cacheable against a token. Without one there is no key
                // to cache under that could be trusted to mean this account,
                // so this lookup repeats each launch.
                if let requested {
                    cache(recordID, for: requested)
                }
                resolvedWithoutToken = requested == nil
                setState(.resolved(recordID))

                LoggingService.shared.info(
                    "Resolved credential identity scope",
                    category: .keychain,
                    details: "fingerprint=\(requested ?? "none (no ubiquity token)"), attempt=\(resolutionAttempts)"
                )
                return
            }

            guard resolutionAttempts < Self.maxResolutionAttempts else { break attempts }

            await retryDelay(resolutionAttempts)
            guard identityGeneration == generation, fingerprint == requested else { return }
        }

        // Every credential read is disabled until this succeeds, so failing
        // quietly would look exactly like "signed out". Foreground activation
        // retries via resolveIfNeeded().
        LoggingService.shared.warning(
            "Could not resolve the credential identity scope — credentials stay unavailable until it does",
            category: .keychain
        )
    }

    /// Retries a resolution that previously ran out of attempts.
    ///
    /// Called when the app returns to the foreground: a device that launched
    /// offline would otherwise keep credentials unavailable for the entire
    /// process lifetime, long after connectivity returned.
    func resolveIfNeeded() async {
        guard !isResolved else {
            await revalidateTokenlessScope()
            return
        }
        resolutionAttempts = 0
        await resolve()
    }

    /// Confirms that a tokenless scope still names the signed-in account.
    ///
    /// With iCloud Drive switched off the ubiquity token stays `nil` across an
    /// Apple-account switch, so nothing local changes and the notification may
    /// never arrive. Without this check the scope would keep pointing at the
    /// previous account until relaunch — and its retained credentials with it.
    ///
    /// The scope is dropped **before** the confirmation, not compared after it.
    /// Holding it live across the awaits would serve the previous account's
    /// credentials for the length of a CloudKit round trip — and indefinitely
    /// when the account status comes back undetermined. The cost is that a
    /// tokenless setup briefly reports "can't tell yet" on each activation,
    /// which the tri-state UI already handles; the alternative trades a real
    /// cross-account disclosure for that convenience.
    private func revalidateTokenlessScope() async {
        guard resolvedWithoutToken, fingerprintProvider() == nil else { return }

        setState(.unresolved)
        resolvedWithoutToken = false
        resolutionAttempts = 0

        // `resolve()` already encodes the whole decision: signed out scopes to
        // local, signed in resolves the user record, undetermined stays
        // unresolved and retries.
        await resolve()
    }

    // MARK: - Cache

    private func cachedScope(for fingerprint: String) -> String? {
        (defaults.dictionary(forKey: Self.cacheKey) as? [String: String])?[fingerprint]
    }

    private func cache(_ scope: String, for fingerprint: String) {
        var cache = (defaults.dictionary(forKey: Self.cacheKey) as? [String: String]) ?? [:]
        cache[fingerprint] = scope
        defaults.set(cache, forKey: Self.cacheKey)
    }
}

extension Notification.Name {
    /// Posted when the resolved credential identity scope changes.
    static let credentialIdentityScopeDidChange =
        Notification.Name("stream.yattee.credentialIdentityScopeDidChange")
}
