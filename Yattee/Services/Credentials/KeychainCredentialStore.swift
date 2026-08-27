//
//  KeychainCredentialStore.swift
//  Yattee
//
//  Keychain read/write shared by the Invidious and Piped credential managers.
//

import Foundation
import Security

/// Generic-password Keychain access for one service name.
///
/// Both credential managers had a byte-for-byte copy of this logic keyed by
/// instance UUID; the account revamp adds identity scoping and username
/// entries on top, so it lives in one place now.
///
/// **tvOS:** `kSecAttrSynchronizable` is accepted but app Keychain items are
/// never synchronized through iCloud there. Writes still set the attribute (so
/// an item created on Apple TV syncs if Apple ever enables it), but an account
/// synced from another device stays credential-less on tvOS until the user
/// signs in locally — that is permanent, not a pending sync.
struct KeychainCredentialStore: Sendable {
    let service: String

    // MARK: - Key construction

    /// Identity-scoped credential key: `"<scope>|<accountID>"`.
    static func credentialKey(scope: String, accountID: UUID) -> String {
        "\(scope)|\(accountID.uuidString)"
    }

    /// Identity-scoped username key: `"<scope>|<accountID>#username"`.
    ///
    /// Scoped exactly like the credential, so a username retained from one
    /// Apple account never surfaces under another.
    static func usernameKey(scope: String, accountID: UUID) -> String {
        "\(credentialKey(scope: scope, accountID: accountID))#username"
    }

    /// The pre-revamp key: a bare instance UUID, with no identity scope.
    ///
    /// Only the adoption path may read this, and only when the user explicitly
    /// asks for it.
    static func legacyKey(instanceID: UUID) -> String {
        instanceID.uuidString
    }

    // MARK: - Access

    /// Reads a value, matching both synchronizable forms.
    ///
    /// `SynchronizableAny` is safe for scoped keys — the scope, not the sync
    /// flag, is what provides identity isolation.
    func value(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    /// Writes a value **only if the key is currently empty**, returning
    /// `errSecDuplicateItem` otherwise.
    ///
    /// Used by legacy adoption: between rendering the offer and the user
    /// tapping it, iCloud Keychain may deliver the real scoped credential, and
    /// a replacing write would silently overwrite it with the older secret.
    @discardableResult
    func addIfAbsent(_ value: String, forKey key: String, synchronizable: Bool) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: synchronizable,
            kSecValueData as String: Data(value.utf8)
        ]

        return SecItemAdd(query as CFDictionary, nil)
    }

    /// Whether the stored item is marked as syncing through iCloud Keychain.
    ///
    /// `nil` when there is no item under this key. The attribute records what
    /// was requested when the item was written — that is exactly the question
    /// here, and deliberately not "does this item belong to the current Apple
    /// account", which it cannot answer (measured).
    func isSynchronizable(key: String) -> Bool? {
        for synchronizable in [true, false] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecAttrSynchronizable as String: synchronizable,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
                return synchronizable
            }
        }

        return nil
    }

    /// Writes a value, replacing any existing item in either synchronizable form.
    @discardableResult
    func set(_ value: String, forKey key: String, synchronizable: Bool) -> OSStatus {
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: synchronizable,
            kSecValueData as String: Data(value.utf8)
        ]

        return SecItemAdd(query as CFDictionary, nil)
    }

    /// Deletes a value in both synchronizable forms.
    ///
    /// Deleting a synchronizable item propagates to every device signed in to
    /// the same Apple account — intended for a real sign-out, which is why the
    /// legacy item is never deleted as a side effect of adoption.
    @discardableResult
    func delete(key: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        return SecItemDelete(query as CFDictionary)
    }

    func describe(_ status: OSStatus) -> String {
        if status == errSecSuccess { return "success" }
        return (SecCopyErrorMessageString(status, nil) as String?) ?? "status \(status)"
    }
}
