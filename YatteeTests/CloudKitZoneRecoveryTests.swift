//
//  CloudKitZoneRecoveryTests.swift
//  YatteeTests
//
//  Answering a record zone that was deleted on the server.
//

import CloudKit
import Foundation
import Testing
@testable import Yattee

@Suite("CloudKit Zone Recovery")
@MainActor
struct CloudKitZoneRecoveryTests {
    /// A defaults suite of its own per test, removed again when the test ends.
    ///
    /// A named suite outlives the process that made it, so leaving them behind
    /// accumulates one plist per test run in the simulator's preferences.
    private final class TemporaryDefaults {
        let suiteName = "yattee.tests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private let temporary = TemporaryDefaults()

    private func makeDefaults() -> UserDefaults { temporary.defaults }

    // MARK: - Reason → behaviour

    @Suite("Deletion reason")
    @MainActor
    struct DeletionReasonTests {
        @Test("Our own reset elsewhere re-seeds the zone")
        func appDeletionReseeds() {
            #expect(ZoneDeletionResponse(reason: .deleted) == .reseed)
        }

        @Test("A purge from iCloud settings is never resent")
        func purgeDiscards() {
            #expect(ZoneDeletionResponse(reason: .purged) == .discard)
        }

        @Test("An encrypted-data reset is never resent")
        func encryptedDataResetDiscards() {
            #expect(ZoneDeletionResponse(reason: .encryptedDataReset) == .discard)
        }

        @Test("A re-seed is redone until the engine has written it down")
        func reseedWaitsForPersistence() {
            #expect(ZoneDeletionResponse.reseed.retirement == .whenStatePersists)
        }

        @Test("A purge is done as soon as it has dropped what it owed")
        func discardRetiresImmediately() {
            // Replaying it later would drop work registered *after* the purge
            // was answered, which is not what a purge asked for.
            #expect(ZoneDeletionResponse.discard.retirement == .immediately)
        }
    }

    // MARK: - Re-seed composition

    @Suite("Re-seed order")
    @MainActor
    struct ReseedOrderTests {
        @Test("Accounts are registered before anything else")
        func accountsGoFirst() {
            #expect(ReseedCategory.reseedOrder.first == .accounts)
        }

        @Test("Every category is re-seeded, exactly once")
        func orderCoversEveryCategory() {
            #expect(Set(ReseedCategory.reseedOrder) == Set(ReseedCategory.allCases))
            #expect(ReseedCategory.reseedOrder.count == ReseedCategory.allCases.count)
        }
    }

    // MARK: - Delivery counter

    @Test("Deliveries are numbered from one, and never repeat")
    func deliveriesAreNumbered() {
        let counter = ZoneRecoveryDeliveryCounter()
        #expect(counter.current == 0)
        #expect(counter.next() == 1)
        #expect(counter.next() == 2)
        #expect(counter.current == 2)
    }

    // MARK: - Marker lifecycle

    @Test("Nothing is pending until a deletion is recorded")
    func noMarkerByDefault() {
        let marker = CloudKitZoneRecoveryMarker(defaults: makeDefaults())
        #expect(marker.pending == nil)
    }

    @Test("The marker is written before the work and outlives the process")
    func markerSurvivesRelaunch() {
        let defaults = makeDefaults()
        CloudKitZoneRecoveryMarker(defaults: defaults).begin(.reseed)

        // A new instance is what a relaunch sees.
        #expect(CloudKitZoneRecoveryMarker(defaults: defaults).pending == .reseed)
    }

    @Test("A state update retires the marker only once the work is registered")
    func markerClearsAfterStatePersists() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)

        marker.begin(.reseed)
        // The engine serializes its state for all sorts of reasons; one that
        // arrives before the re-seed is registered must leave the marker alone.
        marker.stateDidPersist(deliveredAt: 1)
        #expect(marker.pending == .reseed)

        marker.readyToClear(afterDelivery: 1)
        marker.stateDidPersist(deliveredAt: 2)
        #expect(marker.pending == nil)
    }

    @Test("A state update already on its way when the work was registered does not retire it")
    func stateUpdateInFlightDoesNotRetire() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)
        let deliveries = ZoneRecoveryDeliveryCounter()

        marker.begin(.reseed)

        // The engine hands over an update — its serialization is taken now,
        // before the recovery registers anything.
        let inFlight = deliveries.next()

        // The recovery registers its work and arms the marker. The update above
        // has still not reached the main actor.
        marker.readyToClear(afterDelivery: deliveries.current)

        // ...and now it does. It cannot possibly carry the work.
        marker.stateDidPersist(deliveredAt: inFlight)
        #expect(marker.pending == .reseed)

        // The next one can.
        marker.stateDidPersist(deliveredAt: deliveries.next())
        #expect(marker.pending == nil)
    }

    @Test("A recovery interrupted before it registered is still pending next launch")
    func interruptedRecoveryIsRetried() {
        let defaults = makeDefaults()
        let crashed = CloudKitZoneRecoveryMarker(defaults: defaults)
        crashed.begin(.reseed)
        // ...process dies here: nothing was registered, nothing was cleared.

        let relaunched = CloudKitZoneRecoveryMarker(defaults: defaults)
        #expect(relaunched.pending == .reseed)

        // A state update in the new process, before the recovery is redone,
        // must not retire the marker it inherited.
        relaunched.stateDidPersist(deliveredAt: 1)
        #expect(relaunched.pending == .reseed)

        relaunched.begin(.reseed)
        relaunched.readyToClear(afterDelivery: 1)
        relaunched.stateDidPersist(deliveredAt: 2)
        #expect(relaunched.pending == nil)
    }

    @Test("Retiring the marker twice is harmless")
    func clearingIsIdempotent() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)

        marker.begin(.reseed)
        marker.readyToClear(afterDelivery: 0)
        marker.stateDidPersist(deliveredAt: 1)
        marker.stateDidPersist(deliveredAt: 2)
        #expect(marker.pending == nil)
    }

    @Test("A purge is retired the moment it is answered, without waiting for the engine")
    func discardRetiresWithoutStatePersistence() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)

        marker.begin(.discard)
        marker.retireNow()

        // No state update was needed, and a relaunch finds nothing to replay —
        // which is the point: replaying it would drop whatever was registered
        // after the purge was answered.
        #expect(marker.pending == nil)
        #expect(CloudKitZoneRecoveryMarker(defaults: defaults).pending == nil)
    }

    @Test("Retiring a purge outright does not arm it for a later state update")
    func retiringNowLeavesNothingArmed() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)

        marker.begin(.reseed)
        marker.readyToClear(afterDelivery: 0)
        marker.retireNow()
        #expect(marker.pending == nil)

        // A second wipe, unanswered so far, must not be retired by a state
        // update that the first one armed.
        marker.begin(.discard)
        marker.stateDidPersist(deliveredAt: 99)
        #expect(marker.pending == .discard)
    }

    @Test("A fresh deletion is not retired by the previous one's state update")
    func newDeletionRearms() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)

        marker.begin(.reseed)
        marker.readyToClear(afterDelivery: 0)
        // A second wipe arrives before the first one's state was serialized.
        marker.begin(.discard)
        marker.stateDidPersist(deliveredAt: 1)

        #expect(marker.pending == .discard)
    }

    @Test("The marker is forgotten when the Apple account moves, not carried across")
    func forgettingDropsThePendingResponse() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)

        marker.begin(.discard)
        // What an iCloud account change does: the decision named the zone of
        // the identity being left, and answering it under the next one's
        // namespace would drop that identity's staged accounts and outbox.
        marker.forget()

        #expect(marker.pending == nil)
        #expect(CloudKitZoneRecoveryMarker(defaults: defaults).pending == nil)
    }

    @Test("A marker written by a build that meant something else is ignored")
    func unknownMarkerValueIsIgnored() {
        let defaults = makeDefaults()
        defaults.set("something-else", forKey: "cloudKitZoneNeedsReseed")

        #expect(CloudKitZoneRecoveryMarker(defaults: defaults).pending == nil)
    }

    // MARK: - Account side of a re-seed

    @Test("A re-seed re-primes the account outbox, a purge empties it")
    func accountOutboxFollowsTheResponse() {
        let defaults = makeDefaults()
        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            instancesManager: nil,
            defaults: defaults
        )
        let account = accounts.addAccount(instanceID: UUID(), displayName: "Main")
        accounts.confirmUpload(account.id)
        #expect(accounts.pendingUploads.isEmpty)

        // What a re-seed does: the server holds nothing, so everything is owed
        // again even though nothing changed locally.
        accounts.markAllRecordsForUpload()
        #expect(accounts.pendingUploads.contains(account.id))

        // What a purge does: the account stays, the intent to upload it does not.
        accounts.clearPendingUploads()
        #expect(accounts.pendingUploads.isEmpty)
        #expect(accounts.account(id: account.id) != nil)

        // And it is durable, so a relaunch does not resend what was purged.
        let relaunched = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            instancesManager: nil,
            defaults: defaults
        )
        #expect(relaunched.pendingUploads.isEmpty)
        #expect(relaunched.account(id: account.id) != nil)
    }

    // MARK: - The coordinator's half

    private struct CoordinatorHarness {
        let accounts: AccountsManager
        let store: AccountSyncStore
        let coordinator: AccountSyncCoordinator
        let namespace: String
    }

    /// A coordinator whose namespace may be steered away from the one the
    /// accounts were loaded under — the reload gap, which is the state both
    /// account-side fences exist for.
    private func makeCoordinatorHarness(
        namespace: String,
        loadedAs loaded: String = "identity-A"
    ) -> CoordinatorHarness {
        let defaults = makeDefaults()
        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: loaded),
            instancesManager: nil,
            defaults: defaults
        )
        let store = AccountSyncStore(defaults: defaults)
        store.markBootstrapCompleted(in: namespace)

        let coordinator = AccountSyncCoordinator(
            accountsManager: accounts,
            namespaceProvider: { namespace },
            store: store,
            isCategoryEnabled: { true }
        )
        coordinator.attach(database: nil) { _ in }

        return CoordinatorHarness(
            accounts: accounts,
            store: store,
            coordinator: coordinator,
            namespace: namespace
        )
    }

    private func makeStagedRecord(named name: String) -> CKRecord {
        CKRecord(
            recordType: RecordType.account,
            recordID: CKRecord.ID(recordName: name, zoneID: RecordType.createZone().zoneID)
        )
    }

    @Test("A purge answered during the reload gap destroys nothing")
    func discardIsFencedBeforeItDestroys() {
        // The identity moved but the accounts in memory are still the previous
        // one's — the outbox and the staging both belong to somebody else.
        let harness = makeCoordinatorHarness(namespace: "identity-B", loadedAs: "identity-A")
        harness.store.stage(
            records: [makeStagedRecord(named: "account-staged")],
            deletions: [],
            in: harness.namespace
        )
        let account = harness.accounts.addAccount(instanceID: UUID(), displayName: "Main")
        #expect(harness.accounts.pendingUploads.contains(account.id))

        #expect(harness.coordinator.discardWhatTheZoneHeld() == false)

        // Refused, and — the point of the fence order — refused before
        // anything was dropped.
        #expect(!harness.store.stagedChanges(in: harness.namespace).isEmpty)
        #expect(harness.accounts.pendingUploads.contains(account.id))
    }

    @Test("A purge answered with the accounts loaded drops the staging and the outbox")
    func discardClearsWhenTheAccountsAreReadable() {
        let harness = makeCoordinatorHarness(namespace: "identity-A", loadedAs: "identity-A")
        harness.store.stage(
            records: [makeStagedRecord(named: "account-staged")],
            deletions: [],
            in: harness.namespace
        )
        let account = harness.accounts.addAccount(instanceID: UUID(), displayName: "Main")

        #expect(harness.coordinator.discardWhatTheZoneHeld() == true)

        #expect(harness.store.stagedChanges(in: harness.namespace).isEmpty)
        #expect(harness.accounts.pendingUploads.isEmpty)
        // The account itself is this device's own, and stays.
        #expect(harness.accounts.account(id: account.id) != nil)
    }

    @Test("A re-seed refused during the reload gap says so")
    func uploadEverythingIsRefusedDuringTheReloadGap() {
        let harness = makeCoordinatorHarness(namespace: "identity-B", loadedAs: "identity-A")
        #expect(harness.coordinator.uploadEverything() == false)
    }

    @Test("The accounts becoming readable is announced, so a refused recovery can be retried")
    func readableAccountsAreAnnounced() {
        let harness = makeCoordinatorHarness(namespace: "identity-A", loadedAs: "identity-A")
        var announcements = 0
        harness.coordinator.onAccountsBecameReadable = { announcements += 1 }

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        // At least: the notification is global, and a test running beside this
        // one can post it too.
        #expect(announcements >= 1)
    }

    @Test("Nothing is announced while the accounts belong to another identity")
    func unreadableAccountsAreNotAnnounced() {
        let harness = makeCoordinatorHarness(namespace: "identity-B", loadedAs: "identity-A")
        var announcements = 0
        harness.coordinator.onAccountsBecameReadable = { announcements += 1 }

        NotificationCenter.default.post(name: .accountsDidChange, object: nil)
        #expect(announcements == 0)
    }
}
