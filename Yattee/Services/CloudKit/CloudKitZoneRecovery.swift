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

    /// Says the recovery is fully registered with the engine, so the next
    /// serialization of that state may retire the marker.
    ///
    /// Deliberately separate from `begin`: a recovery that could not register
    /// everything — accounts belonging to an identity that has not loaded yet —
    /// keeps its marker and is redone on the next launch.
    func readyToClear() {
        awaitingStatePersistence = true
    }

    /// Retires the marker once the engine has persisted the state the recovery
    /// registered, and only then.
    ///
    /// State updates arrive for every other reason too, and one of those must
    /// not retire a marker whose work has not been redone — that is exactly the
    /// state a relaunch after an interrupted recovery starts in.
    func stateDidPersist() {
        guard awaitingStatePersistence else { return }
        awaitingStatePersistence = false
        defaults.removeObject(forKey: key)
    }
}
