//
//  CloudKitZoneRecovery.swift
//  Yattee
//
//  Deciding — and remembering — what to do when the record zone is deleted out
//  from under this device.
//

import CloudKit
import Foundation

/// What a remote deletion of the app's record zone requires of this device.
enum ZoneDeletionResponse: String, Sendable {
    /// Recreate the zone and register every local record for upload again.
    ///
    /// The zone was deleted by this app — "Reset iCloud Sync Data" on another
    /// device — so local data is still the truth and iCloud is the copy that
    /// went missing.
    case reseed

    /// Drop what the zone held, and never send it back.
    ///
    /// The account owner asked iCloud to forget this app's data (Settings →
    /// iCloud → Manage Storage) or reset their encrypted data. CloudKit is
    /// explicit that data deleted for either reason must not be resent, so
    /// nothing is republished and everything still queued from before the
    /// deletion is dropped. Local data is left alone: it is this app's own
    /// store, not a cache of the zone.
    case discard

    /// The response CloudKit's deletion reason calls for.
    ///
    /// A reason this build does not recognise is answered as a purge:
    /// republishing data the server deliberately dropped is the one mistake
    /// here that cannot be taken back.
    init(reason: CKDatabase.DatabaseChange.Deletion.Reason) {
        switch reason {
        case .deleted:
            self = .reseed
        case .purged, .encryptedDataReset:
            self = .discard
        @unknown default:
            self = .discard
        }
    }
}

/// When the marker for a recovery may be retired.
enum ZoneRecoveryRetirement: Sendable {
    /// Only once the engine has serialized the state the recovery registered,
    /// so anything interrupted in between is redone on the next launch.
    case whenStatePersists

    /// As soon as the recovery's own durable half has been done.
    case immediately
}

extension ZoneDeletionResponse {
    /// The lifecycle this response's marker follows.
    ///
    /// The two do not share one, because being redone does not cost them the
    /// same thing.
    ///
    /// A re-seed only adds: registering the same records twice collapses in the
    /// engine's state, and marking the account outbox dirty is a set union. It
    /// can therefore afford to be held until the engine has actually written
    /// the work down, and to be repeated for as long as it has not.
    ///
    /// A discard removes, and a replay removes more than it was asked to: it
    /// drops every pending change the engine holds *now*, including work
    /// registered after the purge was answered — an account added while the app
    /// kept running, a category switched back on, a re-run of `setupSyncEngine`.
    /// Its durable half — this identity's staged records and its account outbox
    /// — is the answer the purge actually needs, and it is complete the moment
    /// that half succeeds. So the marker goes then, and the engine-state
    /// clearing beside it is one-shot.
    var retirement: ZoneRecoveryRetirement {
        switch self {
        case .reseed: .whenStatePersists
        case .discard: .immediately
        }
    }
}

/// Counts sync-engine state updates as they are delivered, off the main actor.
///
/// A state update is handed to the delegate on the engine's own thread and only
/// then hops to the main actor. An update delivered *before* a recovery
/// registered its work can still run its main-actor body after — the recovery
/// holds the main actor while it registers — and the serialization it carries
/// predates that work entirely. Retiring a marker on one of those would forget
/// work the engine has not written down. Counting at delivery is what tells the
/// two apart.
final class ZoneRecoveryDeliveryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: UInt64 = 0

    /// Records a delivery and returns its sequence number.
    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    /// How many deliveries have happened so far.
    var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// One category of local data a re-seed publishes.
enum ReseedCategory: String, CaseIterable, Sendable {
    case accounts
    case subscriptions
    case watchHistory
    case bookmarks
    case playlists
    case searchHistory
    case recentChannels
    case recentPlaylists
    case channelNotificationSettings
    case controlsPresets

    /// The order a re-seed registers categories in.
    ///
    /// Accounts lead. They carry the logins, the deletion tombstones and the
    /// selected context — the records every other category is read through —
    /// and a re-seed can be cut short at any point by the same backgrounding,
    /// sign-out or crash that interrupts any other upload. Going last, as the
    /// initial upload used to, is how a wipe took the accounts with it.
    static let reseedOrder: [ReseedCategory] = [
        .accounts,
        .subscriptions,
        .watchHistory,
        .bookmarks,
        .playlists,
        .searchHistory,
        .recentChannels,
        .recentPlaylists,
        .channelNotificationSettings,
        .controlsPresets
    ]
}

/// Remembers that the zone was wiped, until the answer to it is durably queued.
///
/// Answering a wipe takes several steps — recreate the zone, re-register every
/// local record — and the process can die between any two of them. Without a
/// marker written *before* the first step, a relaunch finds a zone that exists
/// again and no local sign that anything was lost, and the wipe is invisible
/// for good.
///
/// Durability rests on what the engine's own change token rests on: both are
/// `UserDefaults` writes, so a crash that preserved the token preserved a
/// marker written before it too.
@MainActor
final class CloudKitZoneRecoveryMarker {
    private let defaults: UserDefaults
    private let key: String

    /// Whether the work this marker stands for is registered with the engine
    /// and only waiting for the engine to serialize its state.
    private var awaitingStatePersistence = false

    /// How many state updates the engine had delivered when the work was
    /// registered. Only a later one can carry it.
    private var armedAfterDelivery: UInt64 = 0

    init(defaults: UserDefaults = .standard, key: String = "cloudKitZoneNeedsReseed") {
        self.defaults = defaults
        self.key = key
    }

    /// The response a run recorded and may not have finished.
    var pending: ZoneDeletionResponse? {
        defaults.string(forKey: key).flatMap(ZoneDeletionResponse.init(rawValue:))
    }

    /// Records what has to happen — before any of it does.
    func begin(_ response: ZoneDeletionResponse) {
        defaults.set(response.rawValue, forKey: key)
        awaitingStatePersistence = false
    }

    /// Says the recovery is fully registered with the engine, so a *later*
    /// serialization of that state may retire the marker.
    ///
    /// Deliberately separate from `begin`: a recovery that could not register
    /// everything — accounts belonging to an identity that has not loaded yet —
    /// keeps its marker and is redone on the next launch.
    ///
    /// - Parameter sequence: the number of state updates delivered so far. An
    ///   update already delivered when this is called was serialized before the
    ///   work was registered, however late its main-actor half runs.
    func readyToClear(afterDelivery sequence: UInt64) {
        awaitingStatePersistence = true
        armedAfterDelivery = sequence
    }

    /// Retires the marker now, without waiting for the engine to write anything
    /// down.
    ///
    /// For the response whose answer is its own durable half — see
    /// ``ZoneRecoveryRetirement``. Redoing that one would destroy work that was
    /// registered after it, so it is not held open for a redo.
    func retireNow() {
        clear()
    }

    /// Retires the marker once the engine has persisted the state the recovery
    /// registered, and only then.
    ///
    /// State updates arrive for every other reason too, and one of those must
    /// not retire a marker whose work has not been redone — that is exactly the
    /// state a relaunch after an interrupted recovery starts in. Nor may one
    /// that was already on its way when the work was registered: it is carrying
    /// a serialization taken before any of it existed.
    ///
    /// - Parameter sequence: the delivery number of the state update being
    ///   handled, taken when the engine handed it over.
    func stateDidPersist(deliveredAt sequence: UInt64) {
        guard awaitingStatePersistence, sequence > armedAfterDelivery else { return }
        clear()
    }

    /// Forgets the marker entirely, without treating its work as done.
    ///
    /// For the Apple account moving underneath us: the marker names a decision
    /// about *that* identity's zone, and replaying it against the next one's
    /// namespace answers a wipe that never happened there.
    func forget() {
        clear()
    }

    private func clear() {
        awaitingStatePersistence = false
        armedAfterDelivery = 0
        defaults.removeObject(forKey: key)
    }
}
