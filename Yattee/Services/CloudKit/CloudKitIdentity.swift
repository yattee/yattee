//
//  CloudKitIdentity.swift
//  Yattee
//
//  Resolves the Apple account identity that account-scoped local state is
//  namespaced by (Keychain items, the account cache, the sync outbox).
//

import CloudKit
import CryptoKit
import Foundation

/// The identity that account-scoped local state is keyed by.
///
/// Two different values serve two different purposes:
///
/// - `ubiquityFingerprint` is derived from `FileManager.ubiquityIdentityToken`:
///   synchronous and offline-capable, so launch-time gating can decide whether
///   the persisted namespace still belongs to the signed-in account *before*
///   any CloudKit request could complete.
/// - `userRecordID()` is the CloudKit user record name — the durable scope
///   value persisted state is namespaced by. It requires the network, so it is
///   resolved once the account is reachable.
enum CloudKitIdentity {
    /// Scope used when no Apple account is available (signed out, or a
    /// sideloaded build with no iCloud entitlement).
    static let localScope = "local"

    /// Short, stable fingerprint of the currently signed-in Apple account.
    ///
    /// `nil` when no Apple account is signed in. The value is opaque and
    /// carries no account information — it only supports equality comparison
    /// against a previously persisted fingerprint.
    static var ubiquityFingerprint: String? {
        guard let token = FileManager.default.ubiquityIdentityToken,
              let data = try? NSKeyedArchiver.archivedData(
                  withRootObject: token,
                  requiringSecureCoding: true
              )
        else { return nil }

        return shortDigest(of: data)
    }

    /// Whether an Apple account is signed in, as distinct from unreachable.
    ///
    /// `ubiquityIdentityToken` alone cannot answer this: Foundation returns
    /// `nil` both when the user is signed out *and* when iCloud Drive is
    /// unavailable or switched off, and Yattee declares only the CloudKit
    /// service (no ubiquity container), so the token's availability tracks
    /// system iCloud Drive state rather than the account. Treating a nil token
    /// as "signed out" would collapse two different Apple accounts into the
    /// same `local` credential scope.
    enum AccountAvailability {
        /// No Apple account — the `local` scope is genuinely correct.
        case noAccount
        /// Signed in; the user record can be fetched.
        case available
        /// Unreachable, restricted, or undetermined. Never assume either way.
        case indeterminate
    }

    static func accountAvailability() async -> AccountAvailability {
        guard CloudKitAvailability.isAvailable else { return .noAccount }

        do {
            let container = CKContainer(identifier: AppIdentifiers.iCloudContainer)
            switch try await container.accountStatus() {
            case .noAccount: return .noAccount
            case .available: return .available
            default: return .indeterminate
            }
        } catch {
            LoggingService.shared.debug(
                "Could not determine CloudKit account status",
                category: .cloudKit,
                details: "\(error)"
            )
            return .indeterminate
        }
    }

    /// The CloudKit user record name for the current identity.
    ///
    /// Returns `nil` when CloudKit is unavailable (sideloaded build), when no
    /// Apple account is signed in, or when the container cannot be reached —
    /// callers must fall back to ``localScope`` rather than treating `nil` as
    /// an error state.
    static func userRecordID() async -> String? {
        guard CloudKitAvailability.isAvailable else { return nil }

        do {
            let container = CKContainer(identifier: AppIdentifiers.iCloudContainer)
            return try await container.userRecordID().recordName
        } catch {
            LoggingService.shared.debug(
                "Could not resolve CloudKit user record ID",
                category: .cloudKit,
                details: "\(error)"
            )
            return nil
        }
    }

    /// First 8 bytes of the SHA-256 digest, hex encoded — short enough to read
    /// in a log line, wide enough that collisions are not a practical concern.
    static func shortDigest(of data: Data) -> String {
        SHA256.hash(data: data)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
