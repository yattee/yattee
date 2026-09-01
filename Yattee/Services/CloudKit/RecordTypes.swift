//
//  RecordTypes.swift
//  Yattee
//
//  CloudKit record type constants and zone configuration.
//

import CloudKit
import Foundation

/// CloudKit record type names and constants.
enum RecordType {
    static let subscription = "Subscription"
    static let watchEntry = "WatchEntry"
    static let bookmark = "Bookmark"
    static let localPlaylist = "LocalPlaylist"
    static let localPlaylistItem = "LocalPlaylistItem"
    static let searchHistory = "SearchHistory"
    static let recentChannel = "RecentChannel"
    static let recentPlaylist = "RecentPlaylist"
    static let appSettings = "AppSettings"
    static let instance = "Instance"
    static let mediaSource = "MediaSource"
    static let channelNotificationSettings = "ChannelNotificationSettings"
    static let controlsPreset = "ControlsPreset"

    // MARK: - Account category

    /// A sign-in on a backend instance (`Account`).
    static let account = "Account"

    /// Permanent marker recording that a device turned an instance's legacy
    /// single login into an account. Never deleted: `Instance.usesAccountLogin`
    /// stays true forever, so the marker — not the account's existence — is what
    /// stops a deliberately deleted account from being synthesized again.
    static let legacyAccountMigration = "LegacyAccountMigration"

    /// Singleton record holding the selected `DataContext`.
    static let dataContext = "DataContext"

    /// Permanent tombstone for a deleted account. A CloudKit record deletion is
    /// not durable evidence — a device that never fetched the deletion can
    /// recreate the record from a queued offline edit — so deletions are
    /// recorded as records of their own.
    static let accountDeletion = "AccountDeletion"

    /// Every record type in the account category, in the order a fetch applies
    /// them: tombstones dominate accounts, and markers gate synthesis.
    static let accountCategory = [accountDeletion, legacyAccountMigration, account, dataContext]

    /// CloudKit zone name for all user data.
    static let zoneName = "UserData"
    
    /// CloudKit zone for all synced records.
    static func createZone() -> CKRecordZone {
        CKRecordZone(zoneName: zoneName)
    }
}

/// Generates source-scoped suffixes for CloudKit record names to prevent cross-source collisions.
struct SourceScope: Sendable {
    let sourceRawValue: String
    let provider: String?
    let instanceHost: String?
    let extractor: String?

    var recordNameSuffix: String {
        switch sourceRawValue {
        case "federated": "@federated:\(instanceHost ?? "unknown")"
        case "extracted": "@extracted:\(extractor ?? "unknown")"
        default:          "@global:\(provider ?? "youtube")"
        }
    }

    static func from(
        sourceRawValue: String,
        globalProvider: String?,
        instanceURLString: String?,
        externalExtractor: String?
    ) -> SourceScope {
        let host: String? = instanceURLString.flatMap { URL(string: $0)?.host }
        return SourceScope(
            sourceRawValue: sourceRawValue,
            provider: globalProvider,
            instanceHost: host,
            extractor: externalExtractor
        )
    }
}

/// Represents a syncable record type with its identifier strategy.
enum SyncableRecordType: Sendable {
    case subscription(channelID: String, scope: SourceScope)
    case watchEntry(videoID: String, scope: SourceScope)
    case bookmark(videoID: String, scope: SourceScope)
    case localPlaylist(id: UUID)
    case localPlaylistItem(id: UUID)
    case searchHistory(id: UUID)
    case recentChannel(channelID: String, scope: SourceScope)
    case recentPlaylist(playlistID: String, scope: SourceScope)
    case appSettings
    case instance(id: UUID)
    case mediaSource(id: UUID)
    case channelNotificationSettings(channelID: String, scope: SourceScope)
    case controlsPreset(id: UUID)
    case account(id: UUID)
    case legacyAccountMigration(instanceID: UUID)
    case dataContext
    case accountDeletion(accountID: UUID)

    /// The CloudKit record type name.
    var recordTypeName: String {
        switch self {
        case .subscription: RecordType.subscription
        case .watchEntry: RecordType.watchEntry
        case .bookmark: RecordType.bookmark
        case .localPlaylist: RecordType.localPlaylist
        case .localPlaylistItem: RecordType.localPlaylistItem
        case .searchHistory: RecordType.searchHistory
        case .recentChannel: RecordType.recentChannel
        case .recentPlaylist: RecordType.recentPlaylist
        case .appSettings: RecordType.appSettings
        case .instance: RecordType.instance
        case .mediaSource: RecordType.mediaSource
        case .channelNotificationSettings: RecordType.channelNotificationSettings
        case .controlsPreset: RecordType.controlsPreset
        case .account: RecordType.account
        case .legacyAccountMigration: RecordType.legacyAccountMigration
        case .dataContext: RecordType.dataContext
        case .accountDeletion: RecordType.accountDeletion
        }
    }

    /// Extracts the bare ID from a record name by stripping the scope suffix.
    static func extractBareID(from value: String) -> String {
        for prefix in ["@global:", "@federated:", "@extracted:"] {
            if let range = value.range(of: prefix) {
                return String(value[value.startIndex..<range.lowerBound])
            }
        }
        return value
    }
    
    /// The CloudKit record ID for this entity.
    func recordID(in zone: CKRecordZone) -> CKRecord.ID {
        let recordName: String

        switch self {
        case .subscription(let channelID, let scope):
            recordName = "sub-\(channelID)\(scope.recordNameSuffix)"
        case .watchEntry(let videoID, let scope):
            recordName = "watch-\(videoID)\(scope.recordNameSuffix)"
        case .bookmark(let videoID, let scope):
            recordName = "bookmark-\(videoID)\(scope.recordNameSuffix)"
        case .localPlaylist(let id):
            recordName = "playlist-\(id.uuidString)"
        case .localPlaylistItem(let id):
            recordName = "item-\(id.uuidString)"
        case .searchHistory(let id):
            recordName = "search-\(id.uuidString)"
        case .recentChannel(let channelID, let scope):
            recordName = "recent-channel-\(channelID)\(scope.recordNameSuffix)"
        case .recentPlaylist(let playlistID, let scope):
            recordName = "recent-playlist-\(playlistID)\(scope.recordNameSuffix)"
        case .appSettings:
            recordName = "settings-singleton"
        case .instance(let id):
            recordName = "instance-\(id.uuidString)"
        case .mediaSource(let id):
            recordName = "source-\(id.uuidString)"
        case .channelNotificationSettings(let channelID, let scope):
            recordName = "channel-notif-\(channelID)\(scope.recordNameSuffix)"
        case .controlsPreset(let id):
            recordName = "controls-\(id.uuidString)"
        case .account(let id):
            recordName = AccountRecordName.account(id)
        case .legacyAccountMigration(let instanceID):
            recordName = AccountRecordName.legacyMigration(instanceID)
        case .dataContext:
            recordName = AccountRecordName.dataContext
        case .accountDeletion(let accountID):
            recordName = AccountRecordName.accountDeletion(accountID)
        }

        return CKRecord.ID(recordName: recordName, zoneID: zone.zoneID)
    }
}

/// Record names for the account category, and the parsing that recognises them.
///
/// Account records are identified by name rather than by fetched record type so
/// that a *deletion* — which carries only a record ID — can be routed to the
/// same handler as a modification.
enum AccountRecordName {
    static let accountPrefix = "account-"
    static let legacyMigrationPrefix = "legacymigrated-"
    static let accountDeletionPrefix = "accountDeletion-"
    static let dataContext = "datacontext-current"

    /// The field every outbound account-category record carries, naming the
    /// identity that built it.
    ///
    /// Record names here are deterministic, so they are identical under every
    /// Apple account and prove nothing about whose record this is — provenance
    /// has to travel inside the record itself. Written and read only by the
    /// account sync coordinator for that comparison; the mappers never look at
    /// it, so it cannot reach the `Account` model.
    static let identityNamespaceField = "identityNamespace"

    static func account(_ id: UUID) -> String { accountPrefix + id.uuidString }
    static func legacyMigration(_ instanceID: UUID) -> String { legacyMigrationPrefix + instanceID.uuidString }
    static func accountDeletion(_ accountID: UUID) -> String { accountDeletionPrefix + accountID.uuidString }

    /// What a record name in the account category refers to.
    enum Parsed: Hashable, Sendable {
        case account(UUID)
        case legacyMigration(instanceID: UUID)
        case dataContext
        case accountDeletion(accountID: UUID)
    }

    /// `nil` for any name outside the account category.
    ///
    /// The deletion prefix is tested first only for readability — `"account-"`
    /// cannot match `"accountDeletion-…"`, whose eighth character is `D` — but
    /// the ordering makes the intent explicit rather than relying on that.
    static func parse(_ recordName: String) -> Parsed? {
        if recordName == dataContext { return .dataContext }

        if recordName.hasPrefix(accountDeletionPrefix) {
            guard let id = UUID(uuidString: String(recordName.dropFirst(accountDeletionPrefix.count))) else { return nil }
            return .accountDeletion(accountID: id)
        }
        if recordName.hasPrefix(legacyMigrationPrefix) {
            guard let id = UUID(uuidString: String(recordName.dropFirst(legacyMigrationPrefix.count))) else { return nil }
            return .legacyMigration(instanceID: id)
        }
        if recordName.hasPrefix(accountPrefix) {
            guard let id = UUID(uuidString: String(recordName.dropFirst(accountPrefix.count))) else { return nil }
            return .account(id)
        }
        return nil
    }

    /// Whether a record name belongs to the account category at all, including
    /// names whose UUID does not parse — those must still be kept away from the
    /// other categories' handlers, which would misread them.
    static func isAccountCategory(_ recordName: String) -> Bool {
        recordName == dataContext
            || recordName.hasPrefix(accountDeletionPrefix)
            || recordName.hasPrefix(legacyMigrationPrefix)
            || recordName.hasPrefix(accountPrefix)
    }
}

/// Sync operation type.
enum SyncOperation: Sendable {
    case save
    case delete
}

/// Pending sync change to be uploaded to CloudKit.
struct PendingSyncChange: Sendable {
    let recordType: SyncableRecordType
    let operation: SyncOperation
    let timestamp: Date
    
    init(recordType: SyncableRecordType, operation: SyncOperation) {
        self.recordType = recordType
        self.operation = operation
        self.timestamp = Date()
    }
}
