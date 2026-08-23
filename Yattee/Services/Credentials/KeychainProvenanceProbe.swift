//
//  KeychainProvenanceProbe.swift
//  Yattee
//
//  Debug-only diagnostic that settles one open question in the accounts
//  revamp: can a Keychain query prove which Apple account a stored credential
//  came from?
//

#if DEBUG
import Foundation
import Security

/// Empirical probe for the credential-adoption question in the accounts
/// revamp (design decision D3).
///
/// Yattee 2 stores instance credentials under an *unscoped* key
/// (`kSecAttrAccount = instance.id.uuidString`) and reads them back with
/// `kSecAttrSynchronizableAny`. The revamp re-keys them per Apple account
/// (`"<userRecordID|local>|<accountID>"`) so that a credential retained on
/// device across an Apple-account switch can never be served to the new
/// account. That leaves one thing to decide: on upgrade, may the app adopt the
/// existing unscoped item automatically, or must every user tap an explicit
/// "use saved login from this device" action?
///
/// Adopting automatically is only safe with *provenance of the secret itself*.
/// The candidate discriminator is a **strict `kSecAttrSynchronizable == true`**
/// query: the hypothesis is that an item actively served from the *current*
/// account's iCloud Keychain matches it, while a credential retained after
/// signing out of a *previous* account survives only as a local copy and does
/// not. Nothing in Apple's documentation states this either way, so it has to
/// be measured on a real device across a real account switch.
///
/// This probe writes to its own Keychain service and therefore can never read,
/// modify, or delete a real Yattee credential.
///
/// Everything else mirrors the production managers exactly — same item class,
/// same delete-then-add write, same attribute set — so the measured behaviour
/// transfers to `InvidiousCredentialsManager` / `PipedCredentialsManager`.
enum KeychainProvenanceProbe {
    /// Dedicated service name: isolates the probe from `com.yattee.invidious`
    /// and `com.yattee.piped`.
    static let service = "com.yattee.keychain-provenance-experiment"

    /// Stands in for the legacy credential: written with
    /// `kSecAttrSynchronizable = true`, exactly like a real logged-in instance
    /// while iCloud sync is on.
    static let synchronizableAccount = "probe-synchronizable"

    /// Control item written with `kSecAttrSynchronizable = false` — never
    /// eligible for iCloud Keychain, so it isolates "survived the account
    /// switch" from "was synced".
    static let localAccount = "probe-local"

    // MARK: - Queries

    /// The three ways the app can ask for an item, and the question each answers.
    enum SyncMatch: String, CaseIterable, Identifiable {
        /// The candidate discriminator.
        case synchronizableTrue
        /// Catches items whose synchronizable flag was cleared on sign-out.
        case synchronizableFalse
        /// What the production managers use today — matches either form.
        case any

        var id: String { rawValue }

        var queryValue: Any {
            switch self {
            case .synchronizableTrue: kCFBooleanTrue as Any
            case .synchronizableFalse: kCFBooleanFalse as Any
            case .any: kSecAttrSynchronizableAny as Any
            }
        }

        var label: String {
            switch self {
            case .synchronizableTrue: "kSecAttrSynchronizable == true   (candidate discriminator)"
            case .synchronizableFalse: "kSecAttrSynchronizable == false"
            case .any: "kSecAttrSynchronizableAny        (what Yattee queries today)"
            }
        }
    }

    /// A single matched Keychain item, flattened for reporting.
    struct ItemDump: Identifiable, Sendable {
        let id = UUID()
        let account: String
        /// The attribute as stored — not as queried. The interesting column
        /// after an account switch.
        let synchronizable: Bool?
        let accessible: String?
        let creationDate: Date?
        let modificationDate: Date?
        /// Records which identity wrote the item, so a retained item can be
        /// attributed to the previous Apple account after a switch.
        let payload: String?
    }

    struct QueryResult: Identifiable, Sendable {
        var id: String { match.rawValue }
        let match: SyncMatch
        let status: OSStatus
        let items: [ItemDump]
    }

    // MARK: - Write

    /// Writes a probe item, mirroring the production delete-then-add pattern.
    ///
    /// The delete leg spans both synchronizable forms, exactly like
    /// `InvidiousCredentialsManager.setSID(_:for:)` — which means calling this
    /// destroys a retained item from a previous account. Only call it when the
    /// protocol step says to.
    @discardableResult
    static func write(account: String, synchronizable: Bool, payload: String) -> OSStatus {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
            kSecValueData as String: Data(payload.utf8)
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        LoggingService.shared.info(
            "Keychain provenance probe written",
            category: .keychain,
            details: "account=\(account), synchronizable=\(synchronizable), status=\(describe(status))"
        )

        return status
    }

    /// Deletes every probe item in both synchronizable forms.
    ///
    /// Deleting a synchronizable item propagates through iCloud Keychain to
    /// every device signed in to the same Apple account — intended here, since
    /// this is how the experiment is reset between runs.
    @discardableResult
    static func deleteAll() -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)

        LoggingService.shared.info(
            "Keychain provenance probes deleted",
            category: .keychain,
            details: "status=\(describe(status))"
        )

        return status
    }

    // MARK: - Read

    /// Runs one query and returns every matching item with its stored attributes.
    static func query(_ match: SyncMatch) -> QueryResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: match.queryValue,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let attributes = result as? [[String: Any]] ?? []

        return QueryResult(
            match: match,
            status: status,
            items: attributes.map(dump).sorted { $0.account < $1.account }
        )
    }

    /// All three queries, in reporting order.
    static func queryAll() -> [QueryResult] {
        SyncMatch.allCases.map(query)
    }

    private static func dump(_ attributes: [String: Any]) -> ItemDump {
        ItemDump(
            account: attributes[kSecAttrAccount as String] as? String ?? "<none>",
            synchronizable: (attributes[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue,
            accessible: attributes[kSecAttrAccessible as String] as? String,
            creationDate: attributes[kSecAttrCreationDate as String] as? Date,
            modificationDate: attributes[kSecAttrModificationDate as String] as? Date,
            payload: (attributes[kSecValueData as String] as? Data)
                .flatMap { String(data: $0, encoding: .utf8) }
        )
    }

    // MARK: - Status

    static func describe(_ status: OSStatus) -> String {
        if status == errSecSuccess { return "success (0)" }
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        return "\(message) (\(status))"
    }
}
#endif
