//
//  AccountSyncStore.swift
//  Yattee
//
//  Durable, identity-namespaced staging for fetched account-category records.
//

import CloudKit
import Foundation

/// One fetched account-category change, held until it may be applied.
struct StagedAccountChange: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case save
        case delete
    }

    /// Arrival order. Two changes to the same record collapse to the later one;
    /// changes to *different* records keep their order, which is what lets a
    /// tombstone be applied ahead of an account record it dominates.
    let sequence: Int
    let recordName: String
    let kind: Kind

    /// Archived `CKRecord`. `nil` for deletions, which carry only a record ID.
    let recordData: Data?

    func record() -> CKRecord? {
        guard let recordData else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: recordData)
    }
}

/// Storage for everything account sync has to survive a relaunch with.
///
/// ### Why staging is persisted at all
///
/// `CKSyncEngine` emits several `fetchedRecordZoneChanges` events between
/// `willFetchChanges` and `didFetchChanges`, and may persist its change token
/// after any of them. Applying records as they arrive would expose an account
/// delivered in the first event before the tombstone that deletes it arrives in
/// the third; holding them only in memory would lose them to a crash while the
/// engine's token had already moved past them. So each event's records are
/// written here before the delegate returns, and applied as a set once the zone
/// fetch has actually succeeded.
///
/// Durability rests on the same mechanism the engine's own token does: both are
/// `UserDefaults` writes, and they are ordered, so any crash that preserved the
/// token also preserved the staging written before it.
///
/// ### Why everything is namespaced
///
/// Every value here belongs to one Apple account. Sharing storage across
/// identities would let a fetch begun under one account be applied under the
/// next, which is precisely the disclosure that scoping accounts prevents.
@MainActor
final class AccountSyncStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ name: String, in namespace: String) -> String {
        "accountSync.\(namespace).\(name)"
    }

    // MARK: - Staging

    func stagedChanges(in namespace: String) -> [StagedAccountChange] {
        guard let data = defaults.data(forKey: key("staged", in: namespace)),
              let decoded = try? JSONDecoder().decode([StagedAccountChange].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.sequence < $1.sequence }
    }

    /// Stages fetched changes, replacing any earlier change to the same record.
    ///
    /// Records that fail to archive are dropped rather than silently staged as
    /// deletions — losing a record is recoverable by a later fetch or bootstrap,
    /// but a phantom deletion is not.
    func stage(records: [CKRecord], deletions: [CKRecord.ID], in namespace: String) {
        guard !records.isEmpty || !deletions.isEmpty else { return }

        var byName: [String: StagedAccountChange] = [:]
        for change in stagedChanges(in: namespace) {
            byName[change.recordName] = change
        }

        var sequence = byName.values.map(\.sequence).max().map { $0 + 1 } ?? 0

        for record in records {
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: record,
                requiringSecureCoding: true
            ) else {
                LoggingService.shared.logCloudKitError(
                    "Could not archive account record \(record.recordID.recordName) for staging",
                    error: CloudKitError.recordNotFound
                )
                continue
            }

            byName[record.recordID.recordName] = StagedAccountChange(
                sequence: sequence,
                recordName: record.recordID.recordName,
                kind: .save,
                recordData: data
            )
            sequence += 1
        }

        for recordID in deletions {
            byName[recordID.recordName] = StagedAccountChange(
                sequence: sequence,
                recordName: recordID.recordName,
                kind: .delete,
                recordData: nil
            )
            sequence += 1
        }

        let ordered = byName.values.sorted { $0.sequence < $1.sequence }
        guard let data = try? JSONEncoder().encode(ordered) else {
            LoggingService.shared.logCloudKit("Could not persist staged account changes")
            return
        }
        defaults.set(data, forKey: key("staged", in: namespace))
    }

    func clearStagedChanges(in namespace: String) {
        defaults.removeObject(forKey: key("staged", in: namespace))
    }

    // MARK: - Schema bootstrap

    /// Whether this identity has run the one-time full-zone fetch that picks up
    /// account records a previous app version consumed without understanding.
    func isBootstrapCompleted(in namespace: String) -> Bool {
        defaults.integer(forKey: key("schemaVersion", in: namespace)) >= AccountSyncStore.schemaVersion
    }

    func markBootstrapCompleted(in namespace: String) {
        defaults.set(AccountSyncStore.schemaVersion, forKey: key("schemaVersion", in: namespace))
    }

    /// Forces the bootstrap to run again for this identity.
    ///
    /// Used when account records had to be dropped because the identity they
    /// belonged to could not be established at the time — the engine's token has
    /// moved past them, so only a full-zone fetch can recover them.
    func clearBootstrapCompletion(in namespace: String) {
        defaults.removeObject(forKey: key("schemaVersion", in: namespace))
    }

    /// The account-category schema this build understands. Raising it makes
    /// every identity bootstrap once more, which is how a future release picks
    /// up record types this one ignores.
    static let schemaVersion = 1
}
