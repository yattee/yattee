//
//  CredentialIdentityScope.swift
//  Yattee
//
//  Resolves the Apple-account scope that Keychain credentials are keyed by.
//

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

    private static let cacheKey = "credentialIdentityScopeCache"

    /// Attempts made for the Apple account currently being resolved. Reset
    /// whenever the identity changes.
    private var resolutionAttempts = 0
    private var isResolving = false
    /// Set when a resolution is requested while one is already running — the
    /// running one is for a now-stale identity and will bail on the fingerprint
    /// check, so the request has to be replayed rather than dropped.
    private var pendingResolve = false
    private static let maxResolutionAttempts = 4

    /// The resolved scope, or `nil` while unresolved.
    var current: String? {
        if case let .resolved(scope) = state { return scope }
        return nil
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
    }

    /// Re-scopes as soon as the Apple account changes under a running app.
    ///
    /// Without this the scope would stay pinned to whichever account was
    /// signed in at launch, and a sign-out or switch mid-session would let
    /// reads and writes reach the previous account's retained credentials —
    /// the exact leak scoping exists to prevent.
    private func observeIdentityChanges() {
        identityChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                LoggingService.shared.info(
                    "Apple account changed — re-resolving the credential identity scope",
                    category: .keychain
                )
                self.adoptCurrentIdentity()
                Task { await self.resolve() }
            }
        }
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
        }
        fingerprint = current

        guard CloudKitAvailability.isAvailable else {
            // No iCloud entitlement: nothing can sync, and there is no ambient
            // identity for a retained credential to leak to.
            state = .resolved(Self.localScope)
            return
        }

        guard let current else {
            // A nil token does NOT establish sign-out — Foundation also returns
            // nil when iCloud Drive is unavailable or switched off, and Yattee
            // declares only the CloudKit service. Scoping to `local` here would
            // collapse two different signed-in Apple accounts into one
            // namespace, which is exactly the collision this class prevents.
            // CloudKit's account status settles it during resolution.
            state = .unresolved
            return
        }

        if let cached = cachedScope(for: current) {
            state = .resolved(cached)
        } else {
            state = .unresolved
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
                    guard fingerprintProvider() == nil, fingerprint == nil else { return }
                    state = .resolved(Self.localScope)
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
                    guard fingerprint == requested else { return }
                    continue attempts
                }
            }

            if let recordID = await resolveUserRecordID() {
                guard fingerprintProvider() == requested, fingerprint == requested else {
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
                state = .resolved(recordID)

                LoggingService.shared.info(
                    "Resolved credential identity scope",
                    category: .keychain,
                    details: "fingerprint=\(requested ?? "none (no ubiquity token)"), attempt=\(resolutionAttempts)"
                )
                return
            }

            guard resolutionAttempts < Self.maxResolutionAttempts else { break attempts }

            await retryDelay(resolutionAttempts)
            guard fingerprint == requested else { return }
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
        guard !isResolved else { return }
        resolutionAttempts = 0
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
