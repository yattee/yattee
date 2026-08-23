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

    private static let cacheKey = "credentialIdentityScopeCache"

    /// The resolved scope, or `nil` while unresolved.
    var current: String? {
        if case let .resolved(scope) = state { return scope }
        return nil
    }

    var isResolved: Bool { current != nil }

    init(
        defaults: UserDefaults = .standard,
        resolveUserRecordID: @escaping @Sendable () async -> String? = { await CloudKitIdentity.userRecordID() }
    ) {
        self.defaults = defaults
        self.resolveUserRecordID = resolveUserRecordID
        adoptCurrentIdentity()
    }

    /// Test seam: a scope pinned up front, never consulting CloudKit.
    /// `nil` pins the unresolved state.
    init(fixedScope: String?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        resolveUserRecordID = { nil }
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
        let current = CloudKitIdentity.ubiquityFingerprint
        fingerprint = current

        guard CloudKitAvailability.isAvailable else {
            // No iCloud entitlement: nothing can sync, and there is no ambient
            // identity for a retained credential to leak to.
            state = .resolved(Self.localScope)
            return
        }

        guard let current else {
            // Signed out. Local scope is correct *and* isolating: items written
            // here never collide with a signed-in account's keys.
            state = .resolved(Self.localScope)
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

        // Captured before the await so a switch mid-flight can be detected:
        // a record ID fetched under account A must never be cached for B.
        let requested = fingerprint

        guard let recordID = await resolveUserRecordID() else { return }

        guard CloudKitIdentity.ubiquityFingerprint == requested, fingerprint == requested else {
            LoggingService.shared.info(
                "Discarding credential scope resolved for a previous Apple account",
                category: .keychain
            )
            return
        }

        if let requested {
            cache(recordID, for: requested)
        }
        state = .resolved(recordID)

        LoggingService.shared.info(
            "Resolved credential identity scope",
            category: .keychain,
            details: "fingerprint=\(requested ?? "none")"
        )
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
