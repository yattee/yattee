//
//  AccountSyncTests.swift
//  YatteeTests
//
//  CloudKit sync for accounts, migration markers, deletion tombstones and the
//  selected data context.
//

import CloudKit
import Foundation
import Testing
@testable import Yattee

@Suite("Account sync", .serialized)
@MainActor
struct AccountSyncTests {
    // MARK: - Fixtures

    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
    }

    private static func makeMapper() -> CloudKitRecordMapper {
        CloudKitRecordMapper(zone: RecordType.createZone())
    }

    /// Collects what the coordinator asks the engine to send.
    private final class Recorder {
        private(set) var changes: [CKSyncEngine.PendingRecordZoneChange] = []

        func record(_ new: [CKSyncEngine.PendingRecordZoneChange]) {
            changes.append(contentsOf: new)
        }

        func clear() { changes.removeAll() }

        var savedNames: [String] {
            changes.compactMap {
                if case let .saveRecord(id) = $0 { return id.recordName }
                return nil
            }
        }

        var deletedNames: [String] {
            changes.compactMap {
                if case let .deleteRecord(id) = $0 { return id.recordName }
                return nil
            }
        }
    }

    private final class CategorySwitch {
        var isEnabled: Bool
        init(_ isEnabled: Bool) { self.isEnabled = isEnabled }
    }

    private struct Harness {
        let defaults: UserDefaults
        let accounts: AccountsManager
        let store: AccountSyncStore
        let coordinator: AccountSyncCoordinator
        let recorder: Recorder
        let category: CategorySwitch
        let mapper: CloudKitRecordMapper
        let scope: String

        /// Confirms records the way the server does: what comes back is the
        /// copy the sending identity built, stamped with that identity.
        @MainActor
        func confirm(_ records: [CKRecord]) {
            for record in records {
                record[AccountRecordName.identityNamespaceField] = scope as CKRecordValue
            }
            coordinator.didSave(records: records)
        }
    }

    /// A coordinator with its bootstrap already satisfied.
    ///
    /// The bootstrap needs a live database, so tests that are about what happens
    /// *after* it record the flag directly; `bootstrapped: false` covers the
    /// gate itself.
    private static func makeHarness(
        defaults: UserDefaults? = nil,
        scope: String = "identity-A",
        categoryEnabled: Bool = true,
        bootstrapped: Bool = true,
        instances: InstancesManager? = nil
    ) -> Harness {
        let defaults = defaults ?? makeDefaults()
        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: scope),
            instancesManager: instances,
            defaults: defaults
        )
        let store = AccountSyncStore(defaults: defaults)
        if bootstrapped {
            store.markBootstrapCompleted(in: scope)
        }

        let category = CategorySwitch(categoryEnabled)
        let recorder = Recorder()
        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            identityScope: CredentialIdentityScope(fixedScope: scope),
            store: store,
            isCategoryEnabled: { category.isEnabled }
        )
        coordinator.attach(database: nil) { recorder.record($0) }

        return Harness(
            defaults: defaults,
            accounts: accounts,
            store: store,
            coordinator: coordinator,
            recorder: recorder,
            category: category,
            mapper: makeMapper(),
            scope: scope
        )
    }

    // MARK: - Record mapping

    @Suite("Record mapping", .serialized)
    @MainActor
    struct MappingTests {
        @Test("An account survives the record round-trip")
        func accountRoundTrip() throws {
            let mapper = AccountSyncTests.makeMapper()
            let account = Account(
                instanceID: UUID(),
                displayName: "Main",
                dateAdded: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            )

            let record = mapper.toCKRecord(account: account)
            #expect(record.recordType == RecordType.account)
            #expect(record.recordID.recordName == "account-\(account.id.uuidString)")

            let decoded = try mapper.toAccount(from: record)
            #expect(decoded == account)
        }

        @Test("The login identifier never enters the synced record")
        func recordCarriesNoLoginIdentifier() {
            let mapper = AccountSyncTests.makeMapper()
            let record = mapper.toCKRecord(account: Account(instanceID: UUID(), displayName: "Main"))

            // Only the user-set label syncs; the username lives in the Keychain
            // beside the credential.
            #expect(record["username"] == nil)
            #expect(record.allKeys().sorted() == ["accountID", "dateAdded", "displayName", "instanceID", "schemaVersion", "updatedAt"])
        }

        @Test("A record whose payload disagrees with its name is rejected")
        func mismatchedRecordNameIsRejected() {
            let mapper = AccountSyncTests.makeMapper()
            let record = mapper.toCKRecord(account: Account(instanceID: UUID()))

            // Every device derives the record name from the account ID, so a
            // record claiming a different ID would resolve conflicts against an
            // account other than the one it overwrites.
            record["accountID"] = UUID().uuidString as CKRecordValue

            #expect(throws: (any Error).self) { try mapper.toAccount(from: record) }
        }

        @Test("Migration markers and deletion tombstones round-trip")
        func writeOnceRecordsRoundTrip() throws {
            let mapper = AccountSyncTests.makeMapper()
            let instanceID = UUID()
            let accountID = UUID()

            let marker = mapper.toCKRecord(legacyMigrationInstanceID: instanceID)
            #expect(marker.recordID.recordName == "legacymigrated-\(instanceID.uuidString)")
            #expect(try mapper.toLegacyMigrationInstanceID(from: marker) == instanceID)

            let tombstone = mapper.toCKRecord(accountDeletionID: accountID)
            #expect(tombstone.recordID.recordName == "accountDeletion-\(accountID.uuidString)")
            #expect(try mapper.toAccountDeletionID(from: tombstone) == accountID)
        }

        @Test("Both context cases round-trip through the singleton record")
        func dataContextRoundTrip() throws {
            let mapper = AccountSyncTests.makeMapper()
            let accountID = UUID()

            let local = StoredDataContext(context: .local, changedAt: Date(timeIntervalSince1970: 10))
            let localRecord = mapper.toCKRecord(dataContext: local)
            #expect(localRecord.recordID.recordName == "datacontext-current")
            #expect(try mapper.toStoredDataContext(from: localRecord) == local)

            let account = StoredDataContext(context: .account(accountID), changedAt: Date(timeIntervalSince1970: 20))
            #expect(try mapper.toStoredDataContext(from: mapper.toCKRecord(dataContext: account)) == account)
        }

        @Test("An account record name is never mistaken for a deletion record")
        func recordNameParsingIsUnambiguous() {
            let id = UUID()

            #expect(AccountRecordName.parse("account-\(id.uuidString)") == .account(id))
            #expect(AccountRecordName.parse("accountDeletion-\(id.uuidString)") == .accountDeletion(accountID: id))
            #expect(AccountRecordName.parse("legacymigrated-\(id.uuidString)") == .legacyMigration(instanceID: id))
            #expect(AccountRecordName.parse("datacontext-current") == .dataContext)

            // Other categories must never be routed here.
            #expect(AccountRecordName.parse("sub-abc@global:youtube") == nil)
            #expect(!AccountRecordName.isAccountCategory("instance-\(id.uuidString)"))
        }
    }

    // MARK: - Conflict resolution

    @Suite("Conflict resolution", .serialized)
    @MainActor
    struct ConflictTests {
        @Test("An account resolves on the app-managed updatedAt")
        func accountResolvesByUpdatedAt() async {
            let mapper = AccountSyncTests.makeMapper()
            let resolver = CloudKitConflictResolver()
            let id = UUID()
            let instanceID = UUID()

            let older = mapper.toCKRecord(account: Account(
                id: id, instanceID: instanceID, displayName: "Old",
                updatedAt: Date(timeIntervalSince1970: 100)
            ))
            let newer = mapper.toCKRecord(account: Account(
                id: id, instanceID: instanceID, displayName: "New",
                updatedAt: Date(timeIntervalSince1970: 200)
            ))

            let localWins = await resolver.resolveAccountConflict(local: newer, server: older)
            #expect(localWins["displayName"] as? String == "New")

            let serverWins = await resolver.resolveAccountConflict(local: older, server: newer)
            #expect(serverWins["displayName"] as? String == "New")
        }

        @Test("A migrated account loses to any real edit")
        func migratedAccountLosesToRealEdit() async {
            let mapper = AccountSyncTests.makeMapper()
            let resolver = CloudKitConflictResolver()
            let instanceID = UUID()

            // Synthesized accounts are stamped at the epoch precisely so an
            // explicit edit outranks them whichever arrives first.
            let migrated = mapper.toCKRecord(account: .migrated(from: instanceID))
            let edited = mapper.toCKRecord(account: Account(
                id: instanceID, instanceID: instanceID, displayName: "Renamed",
                updatedAt: Date(timeIntervalSince1970: 1)
            ))

            let resolved = await resolver.resolveAccountConflict(local: migrated, server: edited)
            #expect(resolved["displayName"] as? String == "Renamed")
        }

        @Test("The context resolves on changedAt, not the record's write time")
        func contextResolvesByChangedAt() async throws {
            let mapper = AccountSyncTests.makeMapper()
            let resolver = CloudKitConflictResolver()
            let accountID = UUID()

            let older = mapper.toCKRecord(dataContext: StoredDataContext(
                context: .local, changedAt: Date(timeIntervalSince1970: 100)
            ))
            let newer = mapper.toCKRecord(dataContext: StoredDataContext(
                context: .account(accountID), changedAt: Date(timeIntervalSince1970: 200)
            ))

            let localWins = await resolver.resolveDataContextConflict(local: newer, server: older)
            #expect(try mapper.toStoredDataContext(from: localWins).context == .account(accountID))

            let serverWins = await resolver.resolveDataContextConflict(local: older, server: newer)
            #expect(try mapper.toStoredDataContext(from: serverWins).context == .account(accountID))
        }

        @Test("Two accounts edited in the same instant converge")
        func equalAccountTimestampsBreakTheTieTheSameWayEverywhere() async throws {
            let mapper = AccountSyncTests.makeMapper()
            let resolver = CloudKitConflictResolver()
            let id = UUID()
            let instanceID = UUID()
            let sameMoment = Date(timeIntervalSince1970: 500)

            let lower = Account(id: id, instanceID: instanceID, displayName: "A", updatedAt: sameMoment)
            let higher = Account(id: id, instanceID: instanceID, displayName: "B", updatedAt: sameMoment)

            #expect(lower.isOutranked(by: higher))
            #expect(!higher.isOutranked(by: lower))

            let resolved = await resolver.resolveAccountConflict(
                local: mapper.toCKRecord(account: higher),
                server: mapper.toCKRecord(account: lower)
            )
            #expect(try mapper.toAccount(from: resolved).displayName == "B")
        }

        @Test("Two migrated contexts converge instead of diverging")
        func equalTimestampsBreakTheTieTheSameWayEverywhere() async throws {
            let mapper = AccountSyncTests.makeMapper()
            let resolver = CloudKitConflictResolver()

            // Every migrated context is stamped at the epoch, so two devices
            // migrating different legacy selections tie exactly.
            let lower = StoredDataContext.migrated(.account(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
            let higher = StoredDataContext.migrated(.account(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!))

            #expect(lower.isOutranked(by: higher))
            #expect(!higher.isOutranked(by: lower))

            // The upload side has to reach the same verdict, or a record could
            // win the conflict and then be refused when it arrives.
            let resolved = await resolver.resolveDataContextConflict(
                local: mapper.toCKRecord(dataContext: higher),
                server: mapper.toCKRecord(dataContext: lower)
            )
            #expect(try mapper.toStoredDataContext(from: resolved).context == higher.context)
        }

        @Test("Write-once records resolve to the server copy")
        func writeOnceResolvesToServer() async {
            let mapper = AccountSyncTests.makeMapper()
            let resolver = CloudKitConflictResolver()
            let accountID = UUID()

            let local = mapper.toCKRecord(accountDeletionID: accountID, deletedAt: Date(timeIntervalSince1970: 1))
            let server = mapper.toCKRecord(accountDeletionID: accountID, deletedAt: Date(timeIntervalSince1970: 2))

            let resolved = await resolver.resolveWriteOnceConflict(local: local, server: server)
            #expect(resolved["deletedAt"] as? Date == Date(timeIntervalSince1970: 2))
        }
    }

    // MARK: - Staging

    @Suite("Fetch staging", .serialized)
    @MainActor
    struct StagingTests {
        @Test("Staged records survive a relaunch")
        func stagingIsDurable() {
            let defaults = AccountSyncTests.makeDefaults()
            let mapper = AccountSyncTests.makeMapper()
            let account = Account(instanceID: UUID())

            AccountSyncStore(defaults: defaults).stage(
                records: [mapper.toCKRecord(account: account)],
                deletions: [],
                in: "identity-A"
            )

            // A crash between the fetch event and its application must not lose
            // records the engine's change token has already moved past.
            let reopened = AccountSyncStore(defaults: defaults)
            let staged = reopened.stagedChanges(in: "identity-A")
            #expect(staged.count == 1)
            #expect(staged.first?.record()?.recordID.recordName == "account-\(account.id.uuidString)")
        }

        @Test("A later change to the same record replaces the earlier one")
        func stagingCollapsesByRecordName() {
            let store = AccountSyncStore(defaults: AccountSyncTests.makeDefaults())
            let mapper = AccountSyncTests.makeMapper()
            let account = Account(instanceID: UUID(), displayName: "First")

            store.stage(records: [mapper.toCKRecord(account: account)], deletions: [], in: "A")

            var renamed = account
            renamed.displayName = "Second"
            store.stage(records: [mapper.toCKRecord(account: renamed)], deletions: [], in: "A")

            let staged = store.stagedChanges(in: "A")
            #expect(staged.count == 1)
            #expect(staged.first?.record()?["displayName"] as? String == "Second")
        }

        @Test("Staging and the bootstrap flag are per identity")
        func stagingIsNamespaced() {
            let store = AccountSyncStore(defaults: AccountSyncTests.makeDefaults())
            let mapper = AccountSyncTests.makeMapper()

            store.stage(records: [mapper.toCKRecord(account: Account(instanceID: UUID()))], deletions: [], in: "A")
            store.markBootstrapCompleted(in: "A")

            // Each identity fetches, stages and bootstraps entirely on its own.
            #expect(store.stagedChanges(in: "B").isEmpty)
            #expect(!store.isBootstrapCompleted(in: "B"))
            #expect(store.isBootstrapCompleted(in: "A"))
        }
    }

    // MARK: - Activation

    @Test("A tombstone from a later event still beats the account from an earlier one")
    func tombstonesApplyBeforeAccounts() async {
        let harness = Self.makeHarness()
        let account = Account(instanceID: UUID())

        // CKSyncEngine emits several fetch events per fetch; the account can
        // land in the first and its deletion in the third.
        harness.coordinator.stageFetched(records: [harness.mapper.toCKRecord(account: account)], deletions: [])
        harness.coordinator.stageFetched(
            records: [harness.mapper.toCKRecord(accountDeletionID: account.id)],
            deletions: []
        )

        await harness.coordinator.activate()

        #expect(harness.accounts.account(id: account.id) == nil)
        #expect(harness.accounts.isDeleted(account.id))
    }

    @Test("Nothing is applied until the zone fetch has actually succeeded")
    func failedZoneFetchLeavesRecordsStaged() async {
        let harness = Self.makeHarness()
        let account = Account(instanceID: UUID())

        harness.coordinator.stageFetched(records: [harness.mapper.toCKRecord(account: account)], deletions: [])

        // didFetchChanges fires after failed zone fetches too, so the zone's own
        // result is the gate.
        await harness.coordinator.zoneFetchCompleted(
            zoneID: RecordType.createZone().zoneID,
            error: CKError(.networkFailure)
        )
        #expect(harness.accounts.account(id: account.id) == nil)
        #expect(!harness.store.stagedChanges(in: harness.scope).isEmpty)

        await harness.coordinator.zoneFetchCompleted(zoneID: RecordType.createZone().zoneID, error: nil)
        #expect(harness.accounts.account(id: account.id) != nil)
        #expect(harness.store.stagedChanges(in: harness.scope).isEmpty)
    }

    @Test("A disabled category defers records instead of discarding them")
    func disabledCategoryDefersRecords() async {
        let harness = Self.makeHarness(categoryEnabled: false)
        let account = Account(instanceID: UUID())

        harness.coordinator.stageFetched(records: [harness.mapper.toCKRecord(account: account)], deletions: [])
        await harness.coordinator.activate()

        #expect(harness.accounts.account(id: account.id) == nil)
        #expect(!harness.store.stagedChanges(in: harness.scope).isEmpty)
        #expect(harness.recorder.changes.isEmpty)

        // Re-enabling applies what was kept — no token reset, which would throw
        // away other categories' pending changes.
        harness.category.isEnabled = true
        await harness.coordinator.activate()

        #expect(harness.accounts.account(id: account.id) != nil)
    }

    @Test("Nothing activates or uploads before the identity has bootstrapped")
    func bootstrapGatesActivationAndUpload() async {
        let harness = Self.makeHarness(bootstrapped: false)
        let account = Account(instanceID: UUID())

        harness.coordinator.stageFetched(records: [harness.mapper.toCKRecord(account: account)], deletions: [])
        _ = harness.accounts.addAccount(instanceID: UUID())
        harness.recorder.clear()

        // No database is attached, so the bootstrap cannot complete.
        await harness.coordinator.activate()

        #expect(harness.accounts.account(id: account.id) == nil)
        #expect(harness.recorder.changes.isEmpty)
        #expect(harness.coordinator.recordToSave(named: "datacontext-current") == nil)
    }

    @Test("An account that outlives its tombstone is ignored and deleted again")
    func resurrectedAccountIsRepaired() async {
        let harness = Self.makeHarness()
        let account = Account(instanceID: UUID())

        harness.accounts.removeAccount(harness.accounts.addAccount(instanceID: account.instanceID).id)
        let deletedID = harness.accounts.deletedAccountIDs.first!

        // A device that never fetched the tombstone can recreate the record;
        // CloudKit enforces no relationship between the two.
        let resurrected = Account(id: deletedID, instanceID: account.instanceID, updatedAt: Date())
        harness.recorder.clear()
        harness.coordinator.stageFetched(records: [harness.mapper.toCKRecord(account: resurrected)], deletions: [])
        await harness.coordinator.activate()

        #expect(harness.accounts.account(id: deletedID) == nil)
        #expect(harness.recorder.deletedNames.contains("account-\(deletedID.uuidString)"))
    }

    @Test("An account record deletion removes the account and keeps a tombstone queued")
    func deletionEventPublishesItsOwnTombstone() async {
        let harness = Self.makeHarness()
        let account = Account(instanceID: UUID())

        harness.coordinator.stageFetched(records: [harness.mapper.toCKRecord(account: account)], deletions: [])
        await harness.coordinator.activate()
        #expect(harness.accounts.account(id: account.id) != nil)

        let recordID = CKRecord.ID(
            recordName: "account-\(account.id.uuidString)",
            zoneID: RecordType.createZone().zoneID
        )
        harness.coordinator.stageFetched(records: [], deletions: [recordID])
        harness.recorder.clear()
        await harness.coordinator.activate()

        #expect(harness.accounts.account(id: account.id) == nil)
        // A bare record deletion is not durable, so this device publishes the
        // tombstone that is.
        #expect(harness.accounts.pendingDeletions.contains(account.id))
        #expect(harness.recorder.savedNames.contains("accountDeletion-\(account.id.uuidString)"))
    }

    @Test("A local copy that is newer than the server's is pushed back")
    func staleServerRecordIsCorrected() async {
        let harness = Self.makeHarness()
        let account = harness.accounts.addAccount(instanceID: UUID(), displayName: "Local")
        harness.accounts.confirmUpload(account.id)

        var stale = account
        stale.displayName = "Stale"
        stale.updatedAt = account.updatedAt.addingTimeInterval(-60)

        harness.recorder.clear()
        harness.coordinator.stageFetched(records: [harness.mapper.toCKRecord(account: stale)], deletions: [])
        await harness.coordinator.activate()

        #expect(harness.accounts.account(id: account.id)?.displayName == "Local")
        #expect(harness.accounts.pendingUploads.contains(account.id))
        #expect(harness.recorder.savedNames.contains("account-\(account.id.uuidString)"))
    }

    // MARK: - Upload ordering

    @Test("A migration marker waits for the account it describes")
    func markerWaitsForItsAccount() async {
        let harness = Self.makeHarness()
        let instanceID = UUID()
        let account = harness.accounts.addAccount(instanceID: instanceID)

        #expect(harness.accounts.pendingMarkerUploads.contains(instanceID))
        #expect(!harness.accounts.canUploadMarker(instanceID: instanceID))
        #expect(harness.coordinator.recordToSave(named: "legacymigrated-\(instanceID.uuidString)") == nil)

        harness.recorder.clear()
        harness.confirm([harness.mapper.toCKRecord(account: account)])

        #expect(!harness.accounts.pendingUploads.contains(account.id))
        #expect(harness.recorder.savedNames.contains("legacymigrated-\(instanceID.uuidString)"))
        #expect(harness.coordinator.recordToSave(named: "legacymigrated-\(instanceID.uuidString)") != nil)
    }

    @Test("The context waits for the account it names")
    func contextWaitsForItsAccount() async {
        let harness = Self.makeHarness()
        let account = harness.accounts.addAccount(instanceID: UUID())
        harness.accounts.setContext(.account(account.id))

        // A fresh device could otherwise receive the selection, complete a
        // fetch that lacks the account, and read pending as removed.
        #expect(!harness.accounts.canUploadContext)
        #expect(harness.coordinator.recordToSave(named: "datacontext-current") == nil)

        harness.confirm([harness.mapper.toCKRecord(account: account)])
        #expect(harness.accounts.canUploadContext)
        #expect(harness.coordinator.recordToSave(named: "datacontext-current") != nil)
    }

    @Test("A deletion publishes its tombstone before removing the record")
    func deletionIsTombstoneFirst() async {
        let harness = Self.makeHarness()
        let account = harness.accounts.addAccount(instanceID: UUID())
        harness.accounts.confirmUpload(account.id)

        harness.recorder.clear()
        harness.accounts.removeAccount(account.id)
        harness.coordinator.enqueueDirtyRecords()

        #expect(harness.recorder.savedNames.contains("accountDeletion-\(account.id.uuidString)"))
        #expect(!harness.recorder.deletedNames.contains("account-\(account.id.uuidString)"))

        // The record deletion is registered only once the durable half landed.
        harness.recorder.clear()
        harness.confirm([harness.mapper.toCKRecord(accountDeletionID: account.id)])

        #expect(!harness.accounts.pendingDeletions.contains(account.id))
        #expect(harness.recorder.deletedNames.contains("account-\(account.id.uuidString)"))
    }

    @Test("A deleted account is never reinserted after unknownItem")
    func unknownItemNeverResurrectsADeletedAccount() {
        let harness = Self.makeHarness()
        let account = harness.accounts.addAccount(instanceID: UUID())

        #expect(harness.coordinator.shouldRetryAsInsert(recordName: "account-\(account.id.uuidString)"))

        harness.accounts.removeAccount(account.id)

        // Retrying as an insert is exactly how a queued offline edit brings a
        // deleted account back.
        #expect(!harness.coordinator.shouldRetryAsInsert(recordName: "account-\(account.id.uuidString)"))
        #expect(harness.coordinator.recordToSave(named: "account-\(account.id.uuidString)") == nil)
    }

    @Test("An edit made while an upload was in flight stays dirty")
    func editDuringUploadIsNotConfirmedAway() {
        let harness = Self.makeHarness()
        let account = harness.accounts.addAccount(instanceID: UUID())
        let sent = harness.mapper.toCKRecord(account: account)

        harness.accounts.updateDisplayName("Renamed", for: account.id)
        harness.confirm([sent])

        #expect(harness.accounts.pendingUploads.contains(account.id))
    }

    @Test("Seeding an empty zone re-registers every account record")
    func fullUploadIncludesTombstonesAndMarkers() {
        let harness = Self.makeHarness()
        let kept = harness.accounts.addAccount(instanceID: UUID())
        let removed = harness.accounts.addAccount(instanceID: UUID())
        harness.accounts.removeAccount(removed.id)
        harness.accounts.confirmUpload(kept.id)
        harness.accounts.confirmDeletion(removed.id)
        harness.accounts.confirmMarkerUpload(instanceID: kept.instanceID)

        harness.recorder.clear()
        harness.coordinator.uploadEverything()

        #expect(harness.recorder.savedNames.contains("account-\(kept.id.uuidString)"))
        // Without the tombstone, a device that still has the account could put
        // it back into the fresh zone.
        #expect(harness.recorder.savedNames.contains("accountDeletion-\(removed.id.uuidString)"))

        // The upload ordering still holds during a reseed: the marker follows
        // the account it describes rather than racing it.
        #expect(!harness.recorder.savedNames.contains("legacymigrated-\(kept.instanceID.uuidString)"))

        harness.recorder.clear()
        harness.confirm([harness.mapper.toCKRecord(account: kept)])
        #expect(harness.recorder.savedNames.contains("legacymigrated-\(kept.instanceID.uuidString)"))
    }

    // MARK: - Identity

    @Test("Records staged for one Apple account are invisible to another")
    func stagingNeverCrossesIdentities() async {
        let defaults = Self.makeDefaults()
        let account = Account(instanceID: UUID())

        let identityA = Self.makeHarness(defaults: defaults, scope: "identity-A")
        identityA.coordinator.stageFetched(
            records: [identityA.mapper.toCKRecord(account: account)],
            deletions: []
        )

        let identityB = Self.makeHarness(defaults: defaults, scope: "identity-B")
        await identityB.coordinator.activate()

        #expect(identityB.accounts.accounts.isEmpty)

        await identityA.coordinator.activate()
        #expect(identityA.accounts.account(id: account.id) != nil)
    }

    @Test("A context naming a deleted account is never adopted")
    func tombstoneDominatesASyncedContext() async {
        let harness = Self.makeHarness()
        let account = harness.accounts.addAccount(instanceID: UUID())
        harness.accounts.removeAccount(account.id)

        // An offline device can select an account another device has already
        // deleted, and publish that choice with a newer timestamp.
        let stale = StoredDataContext(
            context: .account(account.id),
            changedAt: Date().addingTimeInterval(3_600)
        )
        harness.coordinator.stageFetched(
            records: [harness.mapper.toCKRecord(dataContext: stale)],
            deletions: []
        )
        await harness.coordinator.activate()

        #expect(harness.accounts.currentContext == .local)
        // The choice's own timestamp is kept, so a later real selection still
        // outranks this repair on every device.
        #expect(harness.accounts.storedContext.changedAt == stale.changedAt)
    }

    @Test("A repair made mid-batch is never uploaded over the server's older context")
    func repairIsNotPublishedForAStaleServerContext() async {
        let instances = makeTestInstancesManager()
        let instance = Instance(type: .invidious, url: URL(string: "https://inv-\(UUID().uuidString).example.com")!)
        instances.add(instance)
        defer { instances.remove(instance) }

        let harness = Self.makeHarness(instances: instances)
        let selected = harness.accounts.addAccount(instanceID: instance.id)
        let sibling = harness.accounts.addAccount(instanceID: instance.id)
        harness.accounts.setStatus(.signedIn, for: sibling.id)
        // Both accounts are on the server already, so nothing holds the context
        // back for ordering reasons.
        harness.accounts.confirmUpload(selected.id)
        harness.accounts.confirmUpload(sibling.id)

        harness.accounts.setContext(.account(selected.id))
        let chosenAt = harness.accounts.storedContext.changedAt
        harness.accounts.confirmContextUpload(changedAt: chosenAt)

        // Tombstones are applied first, so the repair is in place — carrying the
        // deleted choice's timestamp — by the time the older context is weighed
        // against it.
        let older = StoredDataContext(context: .local, changedAt: chosenAt.addingTimeInterval(-60))
        harness.coordinator.stageFetched(
            records: [
                harness.mapper.toCKRecord(accountDeletionID: selected.id),
                harness.mapper.toCKRecord(dataContext: older)
            ],
            deletions: []
        )
        harness.recorder.clear()
        await harness.coordinator.activate()

        // The repair yields to the choice the server holds rather than pushing a
        // fallback nobody made over it — and yielding sends nothing either.
        #expect(harness.accounts.currentContext == .local)
        #expect(!harness.recorder.savedNames.contains("datacontext-current"))
        #expect(harness.coordinator.recordToSave(named: "datacontext-current") == nil)
    }

    @Test("An account discarded for its tombstone still repairs the context")
    func discardedAccountKeepsItsInstance() async {
        let instances = makeTestInstancesManager()
        let instance = Instance(type: .invidious, url: URL(string: "https://inv-\(UUID().uuidString).example.com")!)
        instances.add(instance)
        defer { instances.remove(instance) }

        let harness = Self.makeHarness(instances: instances)
        let sibling = harness.accounts.addAccount(instanceID: instance.id)
        harness.accounts.setStatus(.signedIn, for: sibling.id)

        // A fresh device meets all three at once: the tombstone runs first,
        // while the account it kills is still unknown here, and the record that
        // follows is the only thing that says which server it lived on.
        let deleted = Account(instanceID: instance.id)
        harness.coordinator.stageFetched(
            records: [
                harness.mapper.toCKRecord(accountDeletionID: deleted.id),
                harness.mapper.toCKRecord(account: deleted),
                harness.mapper.toCKRecord(
                    dataContext: StoredDataContext(context: .account(deleted.id), changedAt: Date())
                )
            ],
            deletions: []
        )
        await harness.coordinator.activate()

        #expect(harness.accounts.deletedAccountInstanceIDs[deleted.id] == instance.id)
        // Repaired onto the login the user can actually use, rather than falling
        // all the way back to local because the metadata was thrown away.
        #expect(harness.accounts.currentContext == .account(sibling.id))
    }

    @Test("A context fetched ahead of the records it depends on is still applied last")
    func stagedContextIsAppliedAfterTheAccountRecords() async {
        let instances = makeTestInstancesManager()
        let instance = Instance(type: .invidious, url: URL(string: "https://inv-\(UUID().uuidString).example.com")!)
        instances.add(instance)
        defer { instances.remove(instance) }

        let harness = Self.makeHarness(instances: instances)
        let sibling = harness.accounts.addAccount(instanceID: instance.id)
        harness.accounts.setStatus(.signedIn, for: sibling.id)

        // The order records come back in is CloudKit's, not ours: the same three
        // as above, with the context enumerated first. Applied in that order the
        // repair would run before anything knew the deleted account existed, let
        // alone which server it lived on, and land on local past the sibling.
        let deleted = Account(instanceID: instance.id)
        harness.coordinator.stageFetched(
            records: [
                harness.mapper.toCKRecord(
                    dataContext: StoredDataContext(context: .account(deleted.id), changedAt: Date())
                ),
                harness.mapper.toCKRecord(account: deleted),
                harness.mapper.toCKRecord(accountDeletionID: deleted.id)
            ],
            deletions: []
        )
        await harness.coordinator.activate()

        #expect(harness.accounts.deletedAccountInstanceIDs[deleted.id] == instance.id)
        #expect(harness.accounts.currentContext == .account(sibling.id))
    }

    @Test("Records fetched before the identity resolves are recovered by a bootstrap")
    func unresolvedIdentityForcesAnotherBootstrap() async {
        let defaults = Self.makeDefaults()
        let store = AccountSyncStore(defaults: defaults)
        store.markBootstrapCompleted(in: "identity-A")

        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: nil),
            defaults: defaults
        )
        let identity = Identity(nil)
        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { identity.value },
            store: store,
            isCategoryEnabled: { true }
        )

        // Staging under a guessed identity would apply — and later upload — one
        // Apple account's records under another's.
        coordinator.stageFetched(
            records: [AccountSyncTests.makeMapper().toCKRecord(account: Account(instanceID: UUID()))],
            deletions: []
        )
        #expect(store.stagedChanges(in: "identity-A").isEmpty)
        #expect(store.stagedChanges(in: "unresolved").isEmpty)

        // The engine's token has moved past those records, so the identity that
        // resolves has to fetch the zone in full again to see them. The
        // requirement is persisted, not held in memory: the token may already
        // have advanced, and a launch that lost it would neither replay nor
        // bootstrap.
        #expect(store.hasPendingIdentityRecovery)

        identity.value = "identity-A"
        let relaunched = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { identity.value },
            store: AccountSyncStore(defaults: defaults),
            isCategoryEnabled: { true }
        )
        await relaunched.activate()

        #expect(!store.isBootstrapCompleted(in: "identity-A"))
        #expect(!store.hasPendingIdentityRecovery)
    }

    @Test("A switch of Apple account never claims records dropped while unresolved")
    func switchedIdentityDoesNotClaimDroppedRecords() async {
        let defaults = Self.makeDefaults()
        let store = AccountSyncStore(defaults: defaults)
        store.markBootstrapCompleted(in: "identity-A")
        store.markBootstrapCompleted(in: "identity-B")

        let identity = Identity("identity-A")
        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            defaults: defaults
        )
        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { identity.value },
            store: store,
            isCategoryEnabled: { true }
        )

        // Signed out mid-session, then signed in as someone else. Records that
        // arrived in between could have come from either side.
        identity.value = nil
        coordinator.stageFetched(
            records: [AccountSyncTests.makeMapper().toCKRecord(account: Account(instanceID: UUID()))],
            deletions: []
        )
        identity.value = "identity-B"
        await coordinator.activate()

        // Neither identity is handed the other's records; both recover their
        // own from their own zone instead.
        #expect(store.stagedChanges(in: "identity-A").isEmpty)
        #expect(store.stagedChanges(in: "identity-B").isEmpty)
        #expect(!store.isBootstrapCompleted(in: "identity-A"))
        #expect(!store.isBootstrapCompleted(in: "identity-B"))
    }

    @Test("Nothing is uploaded from a snapshot loaded under another identity")
    func reloadGapBlocksUploads() {
        let defaults = Self.makeDefaults()
        let store = AccountSyncStore(defaults: defaults)
        store.markBootstrapCompleted(in: "identity-A")

        // The manager still holds what it loaded while the scope was
        // unresolved; the coordinator is already namespaced by the identity
        // that resolved. That is the window between the scope moving and the
        // manager's reload observer running, and engine callbacks land in it.
        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: nil),
            defaults: defaults
        )
        let account = accounts.addAccount(instanceID: UUID())
        accounts.setContext(.account(account.id))

        let recorder = Recorder()
        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { "identity-A" },
            store: store,
            isCategoryEnabled: { true }
        )
        coordinator.attach(database: nil) { recorder.record($0) }

        coordinator.enqueueDirtyRecords()
        #expect(recorder.changes.isEmpty)

        // Nothing is built at send time either — a change registered before the
        // scope moved is withdrawn rather than filled in from the wrong state.
        #expect(coordinator.recordToSave(named: "account-\(account.id.uuidString)") == nil)

        coordinator.uploadEverything()
        #expect(recorder.changes.isEmpty)

        // And the outbox of the identity that owns the namespace is untouched:
        // marking everything dirty would have committed another identity's list
        // to this one's zone.
        for name in ["accounts", "context", "hasContext", "pendingUploads", "pendingContextUpload"] {
            #expect(defaults.object(forKey: "accounts.identity-A.\(name)") == nil)
        }
    }

    @Test("Staged records are never applied to another identity's accounts")
    func reloadGapDefersStagedChanges() async throws {
        let defaults = Self.makeDefaults()
        let store = AccountSyncStore(defaults: defaults)
        store.markBootstrapCompleted(in: "identity-B")

        // identity-A's list, still in memory: one live account, and a tombstone
        // for another whose ID identity-B happens to reuse — migrated accounts
        // take their instance's UUID, so the collision is ordinary rather than
        // exotic.
        let scope = CredentialIdentityScope(fixedScope: "identity-A")
        let accounts = AccountsManager(identityScope: scope, defaults: defaults)
        let livingAccount = accounts.addAccount(instanceID: UUID())
        let sharedID = accounts.addAccount(instanceID: UUID()).id
        accounts.removeAccount(sharedID)

        // The scope moved; the reload that refills memory has not run yet.
        scope.setFixedScope("identity-B", announcing: false)

        let recorder = Recorder()
        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { scope.current },
            store: store,
            isCategoryEnabled: { true }
        )
        coordinator.attach(database: nil) { recorder.record($0) }

        var deletedAccounts: [(UUID, Account?)] = []
        coordinator.onAccountDeleted = { deletedAccounts.append(($0, $1)) }

        let mapper = Self.makeMapper()
        coordinator.stageFetched(
            records: [
                mapper.toCKRecord(accountDeletionID: livingAccount.id),
                mapper.toCKRecord(account: Account(id: sharedID, instanceID: UUID()))
            ],
            deletions: []
        )
        await coordinator.activate()

        // Nothing applied: identity-B's tombstone would have removed
        // identity-A's account and taken its credential with it, and
        // identity-B's account would have been read as a resurrection of
        // identity-A's tombstone and deleted from identity-B's zone.
        #expect(accounts.account(id: livingAccount.id) != nil)
        #expect(deletedAccounts.isEmpty)
        #expect(recorder.changes.isEmpty)
        #expect(!store.stagedChanges(in: "identity-B").isEmpty)

        // Deferred, not dropped. The reload announces itself, and that is what
        // releases them — against the right list this time.
        accounts.reloadForCurrentIdentity()
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.stagedChanges(in: "identity-B").isEmpty)
        #expect(accounts.account(id: sharedID) != nil)
        #expect(!recorder.deletedNames.contains("account-\(sharedID.uuidString)"))
        // The tombstone applies to identity-B, which never had that account —
        // so the credential removal it triggers carries no account of
        // identity-A's.
        #expect(deletedAccounts.map(\.0) == [livingAccount.id])
        #expect(deletedAccounts.first?.1 == nil)
    }

    @Test("A confirmation from the previous identity clears nothing")
    func confirmationsAreTiedToTheIdentityThatSentThem() async throws {
        let defaults = Self.makeDefaults()
        let store = AccountSyncStore(defaults: defaults)
        store.markBootstrapCompleted(in: "identity-A")
        store.markBootstrapCompleted(in: "identity-B")

        let scope = CredentialIdentityScope(fixedScope: "identity-A")
        let accounts = AccountsManager(identityScope: scope, defaults: defaults)
        let identity = Identity("identity-A")

        let recorder = Recorder()
        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { identity.value },
            store: store,
            isCategoryEnabled: { true }
        )
        coordinator.attach(database: nil) { recorder.record($0) }

        // A deletion built and sent under identity-A, in flight when the Apple
        // account changes.
        let sharedID = accounts.addAccount(instanceID: UUID()).id
        accounts.removeAccount(sharedID)
        coordinator.enqueueDirtyRecords()
        #expect(recorder.savedNames.contains("accountDeletion-\(sharedID.uuidString)"))
        let sentByA = try #require(coordinator.recordToSave(named: "accountDeletion-\(sharedID.uuidString)"))

        scope.setFixedScope("identity-B")
        try await Task.sleep(for: .milliseconds(200))
        identity.value = "identity-B"

        // identity-B owes the same record name — the IDs are deterministic — and
        // has had no answer from the server about it. It even builds and sends
        // its own copy, which is what makes anything kept *beside* the record,
        // keyed by that shared name, unable to tell the two apart.
        accounts.applySyncedAccount(Account(id: sharedID, instanceID: UUID()))
        accounts.removeAccount(sharedID)
        let sentByB = try #require(coordinator.recordToSave(named: "accountDeletion-\(sharedID.uuidString)"))
        recorder.clear()

        coordinator.didSave(records: [sentByA])

        // Still owed, and no deletion was registered off the back of it:
        // releasing the account record's deletion here would delete identity-B's
        // record on the strength of identity-A's confirmation.
        #expect(accounts.pendingDeletions.contains(sharedID))
        #expect(recorder.deletedNames.isEmpty)

        // identity-B's own copy is its own confirmation.
        recorder.clear()
        coordinator.didSave(records: [sentByB])

        #expect(!accounts.pendingDeletions.contains(sharedID))
        #expect(recorder.deletedNames.contains("account-\(sharedID.uuidString)"))
    }

    @Test("A skipped confirmation puts back what the current identity still owes")
    func skippedConfirmationRestoresTheOutbox() async throws {
        let defaults = Self.makeDefaults()
        let store = AccountSyncStore(defaults: defaults)
        store.markBootstrapCompleted(in: "identity-A")
        store.markBootstrapCompleted(in: "identity-B")

        let scope = CredentialIdentityScope(fixedScope: "identity-A")
        let accounts = AccountsManager(identityScope: scope, defaults: defaults)
        let identity = Identity("identity-A")

        let recorder = Recorder()
        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { identity.value },
            store: store,
            isCategoryEnabled: { true }
        )
        coordinator.attach(database: nil) { recorder.record($0) }

        let accountID = accounts.addAccount(instanceID: UUID()).id
        let sentByA = try #require(coordinator.recordToSave(named: "account-\(accountID.uuidString)"))

        scope.setFixedScope("identity-B")
        try await Task.sleep(for: .milliseconds(200))
        identity.value = "identity-B"

        // identity-B's own upload, registered by the reload that has already
        // happened. identity-A's send consumed the engine's pending change for
        // that record name, so after its confirmation is skipped nothing else
        // is left to re-register the debt.
        let owed = accounts.addAccount(instanceID: UUID()).id
        recorder.clear()

        coordinator.didSave(records: [sentByA])

        #expect(accounts.pendingUploads.contains(owed))
        #expect(recorder.savedNames.contains("account-\(owed.uuidString)"))
        #expect(recorder.deletedNames.isEmpty)
    }

    @Test("A change of identity invalidates the records the engine cached")
    func identityChangeDropsCachedRecords() throws {
        let defaults = Self.makeDefaults()
        let store = AccountSyncStore(defaults: defaults)
        store.markBootstrapCompleted(in: "identity-A")

        let scope = CredentialIdentityScope(fixedScope: "identity-A")
        let accounts = AccountsManager(identityScope: scope, defaults: defaults)
        let identity = Identity("identity-A")

        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { identity.value },
            store: store,
            isCategoryEnabled: { true }
        )

        var didDiscardCachedRecords = false
        coordinator.attach(
            database: nil,
            discardingCachedRecords: { didDiscardCachedRecords = true }
        ) { _ in }

        // The engine serves conflict-resolved records ahead of anything the
        // coordinator builds, and that cache is keyed by record name alone —
        // which every identity shares. The record's own stamp is what tells them
        // apart.
        let accountID = accounts.addAccount(instanceID: UUID()).id
        let builtByA = try #require(coordinator.recordToSave(named: "account-\(accountID.uuidString)"))
        #expect(coordinator.belongsToCurrentIdentity(builtByA))

        identity.value = "identity-B"
        #expect(!coordinator.belongsToCurrentIdentity(builtByA))

        // And an unstamped record — one this build never sent — is nobody's.
        #expect(!coordinator.belongsToCurrentIdentity(Self.makeMapper().toCKRecord(account: Account(instanceID: UUID()))))

        coordinator.identityDidChange()
        #expect(didDiscardCachedRecords)
    }

    /// A mutable identity, for driving scope changes deterministically.
    private final class Identity {
        var value: String?
        init(_ value: String?) { self.value = value }
    }
}
