//
//  CredentialAdoptionMarker.swift
//  Yattee
//
//  Records which legacy Keychain items this device has adopted, and for whom.
//

import CryptoKit
import Foundation

/// Records that a legacy (unscoped) Keychain item was copied into an
/// identity-scoped key on this device.
///
/// The marker is bound to the *secret*, not just the account: it is written
/// only after the scoped copy reads back, and it carries a fingerprint of the
/// credential value that was adopted. That binding is what lets an account
/// deletion clean up the legacy item without ever destroying someone else's
/// login — see ``CredentialAdoptionMarkerStore/canDeleteLegacyItem(...)``.
struct CredentialAdoptionMarker: Codable, Hashable, Sendable {
    /// The identity scope that adopted the item. Apple account A's marker must
    /// never authorize anything under account B.
    let identityScope: String
    /// Keychain service the adopted item lives in. The Invidious and Piped
    /// managers keep separate services but share this store, and an instance
    /// UUID can outlive a change of backend — without this, adopting one
    /// backend's credential would suppress the other's offer and point
    /// deletion at the wrong secret.
    let service: String
    let instanceID: UUID
    let accountID: UUID
    /// Salted, truncated digest of the adopted credential — non-secret, and
    /// device-local (the salt never leaves this device).
    let secretFingerprint: String
    let adoptedAt: Date
}

/// Device-local store of adoption markers.
///
/// Deliberately never synced: it describes what happened to *this* device's
/// Keychain, which differs per device during a staggered rollout.
@MainActor
final class CredentialAdoptionMarkerStore {
    private static let markersKey = "credentialAdoptionMarkers"
    private static let saltKey = "credentialAdoptionFingerprintSalt"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Markers

    func markers() -> [CredentialAdoptionMarker] {
        guard let data = defaults.data(forKey: Self.markersKey),
              let markers = try? JSONDecoder().decode([CredentialAdoptionMarker].self, from: data)
        else { return [] }
        return markers
    }

    /// Whether this identity has already adopted the legacy item for an instance.
    ///
    /// Once true, the app stops adopting and stops reading the legacy key
    /// entirely for that account. Cleared when the user signs in again: the
    /// credential is then one they proved they hold, and nothing about the
    /// adopted copy applies to it any more.
    func hasAdopted(service: String, instanceID: UUID, scope: String) -> Bool {
        marker(service: service, instanceID: instanceID, scope: scope) != nil
    }

    /// The accounts whose credential on this device came from a legacy item.
    ///
    /// Their copies are deliberately device-local, so anything that rewrites
    /// stored credentials to follow the sync setting has to leave them out.
    func adoptedAccountIDs(service: String, scope: String) -> Set<UUID> {
        Set(
            markers()
                .filter { $0.service == service && $0.identityScope == scope }
                .map(\.accountID)
        )
    }

    private func marker(service: String, instanceID: UUID, scope: String) -> CredentialAdoptionMarker? {
        markers().first {
            $0.service == service && $0.instanceID == instanceID && $0.identityScope == scope
        }
    }

    func record(
        service: String,
        instanceID: UUID,
        accountID: UUID,
        scope: String,
        secret: String
    ) {
        var all = markers().filter {
            !($0.service == service && $0.instanceID == instanceID && $0.identityScope == scope)
        }
        all.append(
            CredentialAdoptionMarker(
                identityScope: scope,
                service: service,
                instanceID: instanceID,
                accountID: accountID,
                secretFingerprint: fingerprint(of: secret),
                adoptedAt: Date()
            )
        )
        save(all)
    }

    /// Retires the marker for one account.
    ///
    /// Scoped to `accountID` as well as the instance: an instance can hold
    /// several logins, and only the account that actually adopted the legacy
    /// secret may retire its marker. Matching on the instance alone let a
    /// *sibling* sign-in clear it, which silently withdrew the migrated
    /// account's claim on the unscoped item — after that its deletion could
    /// no longer retire the legacy secret, and it could re-adopt it.
    func removeMarker(service: String, instanceID: UUID, accountID: UUID, scope: String) {
        save(markers().filter {
            !($0.service == service
                && $0.instanceID == instanceID
                && $0.accountID == accountID
                && $0.identityScope == scope)
        })
    }

    // MARK: - Legacy deletion authority

    /// Whether deleting an account may also delete the **unscoped** legacy item.
    ///
    /// Four conditions, all required:
    ///
    /// 1. This device has a marker for the instance — no marker means this
    ///    device never adopted anything, so the legacy item is not ours to touch.
    ///    Since adoption became automatic this proves only that the device took
    ///    the secret, not that the identity signed in now originally owned it.
    ///    Deleting anyway is deliberate: the user is removing this login from
    ///    this device, which is exactly what the pre-revamp release did to the
    ///    same item on logout. Condition 4 is what carries the real weight now.
    /// 2. The marker belongs to the current identity — Apple account A's marker
    ///    cannot authorize a deletion while B is signed in.
    /// 3. The marker belongs to the account being deleted. An instance can hold
    ///    several accounts, and only the one that actually adopted the legacy
    ///    secret may retire it — deleting a *sibling* account must leave it
    ///    alone.
    /// 4. The legacy item still holds the exact secret that was adopted — if it
    ///    has since been replaced (someone signed in again on an older release,
    ///    and that release rewrote the unscoped key), it is a live login of
    ///    theirs and must survive.
    ///
    /// Deleting a synchronizable item propagates everywhere, so a wrong answer
    /// here logs other devices out.
    func canDeleteLegacyItem(
        service: String,
        instanceID: UUID,
        accountID: UUID,
        scope: String,
        currentLegacyValue: String?
    ) -> Bool {
        guard let marker = marker(service: service, instanceID: instanceID, scope: scope) else {
            return false
        }

        guard marker.accountID == accountID else { return false }
        guard let currentLegacyValue else { return false }

        return fingerprint(of: currentLegacyValue) == marker.secretFingerprint
    }

    // MARK: - Fingerprinting

    /// Salted, truncated digest of a credential.
    ///
    /// Salted so the stored marker is not a rainbow-tableable hash of the
    /// secret; truncated because it only ever needs to answer "is this still
    /// the same value". The salt is generated once per device and never synced.
    func fingerprint(of secret: String) -> String {
        var input = Data(salt())
        input.append(Data(secret.utf8))
        return CloudKitIdentity.shortDigest(of: input)
    }

    private func salt() -> [UInt8] {
        if let existing = defaults.data(forKey: Self.saltKey), existing.count == 32 {
            return [UInt8](existing)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        defaults.set(Data(bytes), forKey: Self.saltKey)
        return bytes
    }

    private func save(_ markers: [CredentialAdoptionMarker]) {
        guard let data = try? JSONEncoder().encode(markers) else { return }
        defaults.set(data, forKey: Self.markersKey)
    }
}
