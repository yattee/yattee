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
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
    }

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
        marker.stateDidPersist()
        #expect(marker.pending == .reseed)

        marker.readyToClear()
        marker.stateDidPersist()
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
        relaunched.stateDidPersist()
        #expect(relaunched.pending == .reseed)

        relaunched.begin(.reseed)
        relaunched.readyToClear()
        relaunched.stateDidPersist()
        #expect(relaunched.pending == nil)
    }

    @Test("Retiring the marker twice is harmless")
    func clearingIsIdempotent() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)

        marker.begin(.discard)
        marker.readyToClear()
        marker.stateDidPersist()
        marker.stateDidPersist()
        #expect(marker.pending == nil)
    }

    @Test("A fresh deletion is not retired by the previous one's state update")
    func newDeletionRearms() {
        let defaults = makeDefaults()
        let marker = CloudKitZoneRecoveryMarker(defaults: defaults)

        marker.begin(.reseed)
        marker.readyToClear()
        // A second wipe arrives before the first one's state was serialized.
        marker.begin(.discard)
        marker.stateDidPersist()

        #expect(marker.pending == .discard)
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
}
