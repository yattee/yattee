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
        }

        return CKRecord.ID(recordName: recordName, zoneID: zone.zoneID)
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
