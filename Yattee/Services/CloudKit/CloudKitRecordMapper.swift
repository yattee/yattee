//
//  CloudKitRecordMapper.swift
//  Yattee
//
//  Maps SwiftData models to/from CloudKit CKRecords.
//

import CloudKit
import Foundation

/// Maps SwiftData models to CloudKit records and vice versa.
actor CloudKitRecordMapper {
    private let zone: CKRecordZone

    /// Current schema version for CloudKit records.
    /// Increment this when record structure changes.
    private let currentSchemaVersion: Int64 = 2

    init(zone: CKRecordZone) {
        self.zone = zone
    }
    
    // MARK: - Subscription Mapping
    
    /// Converts a Subscription to a CKRecord.
    func toCKRecord(subscription: Subscription) -> CKRecord {
        let scope = SourceScope.from(
            sourceRawValue: subscription.sourceRawValue,
            globalProvider: subscription.providerName,
            instanceURLString: subscription.instanceURLString,
            externalExtractor: nil
        )
        let recordID = SyncableRecordType.subscription(channelID: subscription.channelID, scope: scope).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.subscription, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        // Channel Identity
        record["channelID"] = subscription.channelID as CKRecordValue
        record["sourceRawValue"] = subscription.sourceRawValue as CKRecordValue
        record["instanceURLString"] = subscription.instanceURLString as CKRecordValue?

        // Channel Metadata
        record["name"] = subscription.name as CKRecordValue
        record["channelDescription"] = subscription.channelDescription as CKRecordValue?
        record["subscriberCount"] = subscription.subscriberCount.map { Int64($0) } as CKRecordValue?
        record["avatarURLString"] = subscription.avatarURLString as CKRecordValue?
        record["bannerURLString"] = subscription.bannerURLString as CKRecordValue?
        record["isVerified"] = (subscription.isVerified ? 1 : 0) as CKRecordValue

        // Subscription Metadata
        record["subscribedAt"] = subscription.subscribedAt as CKRecordValue
        record["lastUpdatedAt"] = subscription.lastUpdatedAt as CKRecordValue
        record["providerName"] = subscription.providerName as CKRecordValue?

        return record
    }
    
    /// Creates a Subscription from a CKRecord.
    func toSubscription(from record: CKRecord) throws -> Subscription {
        let recordType = RecordType.subscription
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let channelID = record["channelID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "channelID", recordType: recordType)
        }
        guard let sourceRawValue = record["sourceRawValue"] as? String else {
            throw CloudKitError.missingRequiredField(field: "sourceRawValue", recordType: recordType)
        }
        guard let name = record["name"] as? String else {
            throw CloudKitError.missingRequiredField(field: "name", recordType: recordType)
        }
        guard let subscribedAt = record["subscribedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "subscribedAt", recordType: recordType)
        }
        guard let lastUpdatedAt = record["lastUpdatedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "lastUpdatedAt", recordType: recordType)
        }

        // Create subscription
        let subscription = Subscription(
            channelID: channelID,
            sourceRawValue: sourceRawValue,
            instanceURLString: record["instanceURLString"] as? String,
            name: name,
            channelDescription: record["channelDescription"] as? String,
            subscriberCount: (record["subscriberCount"] as? Int64).map(Int.init),
            avatarURLString: record["avatarURLString"] as? String,
            bannerURLString: record["bannerURLString"] as? String,
            isVerified: (record["isVerified"] as? Int64) == 1
        )

        // Set timestamps
        subscription.subscribedAt = subscribedAt
        subscription.lastUpdatedAt = lastUpdatedAt
        subscription.providerName = record["providerName"] as? String

        return subscription
    }
    
    // MARK: - WatchEntry Mapping
    
    /// Converts a WatchEntry to a CKRecord.
    func toCKRecord(watchEntry: WatchEntry) -> CKRecord {
        let scope = SourceScope.from(
            sourceRawValue: watchEntry.sourceRawValue,
            globalProvider: watchEntry.globalProvider,
            instanceURLString: watchEntry.instanceURLString,
            externalExtractor: watchEntry.externalExtractor
        )
        let recordID = SyncableRecordType.watchEntry(videoID: watchEntry.videoID, scope: scope).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.watchEntry, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        // Video Identity
        record["videoID"] = watchEntry.videoID as CKRecordValue
        record["sourceRawValue"] = watchEntry.sourceRawValue as CKRecordValue
        record["globalProvider"] = watchEntry.globalProvider as CKRecordValue?
        record["instanceURLString"] = watchEntry.instanceURLString as CKRecordValue?
        record["peertubeUUID"] = watchEntry.peertubeUUID as CKRecordValue?
        record["externalExtractor"] = watchEntry.externalExtractor as CKRecordValue?
        record["externalURLString"] = watchEntry.externalURLString as CKRecordValue?

        // Video Metadata (cached)
        record["title"] = watchEntry.title as CKRecordValue
        record["authorName"] = watchEntry.authorName as CKRecordValue
        record["authorID"] = watchEntry.authorID as CKRecordValue
        record["duration"] = watchEntry.duration as CKRecordValue
        record["thumbnailURLString"] = watchEntry.thumbnailURLString as CKRecordValue?

        // Watch Progress
        record["watchedSeconds"] = watchEntry.watchedSeconds as CKRecordValue
        record["isFinished"] = (watchEntry.isFinished ? 1 : 0) as CKRecordValue
        record["finishedAt"] = watchEntry.finishedAt as CKRecordValue?

        // Timestamps
        record["createdAt"] = watchEntry.createdAt as CKRecordValue
        record["updatedAt"] = watchEntry.updatedAt as CKRecordValue

        return record
    }
    
    /// Creates a WatchEntry from a CKRecord.
    func toWatchEntry(from record: CKRecord) throws -> WatchEntry {
        let recordType = RecordType.watchEntry
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let videoID = record["videoID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "videoID", recordType: recordType)
        }
        guard let sourceRawValue = record["sourceRawValue"] as? String else {
            throw CloudKitError.missingRequiredField(field: "sourceRawValue", recordType: recordType)
        }
        guard let title = record["title"] as? String else {
            throw CloudKitError.missingRequiredField(field: "title", recordType: recordType)
        }
        guard let authorName = record["authorName"] as? String else {
            throw CloudKitError.missingRequiredField(field: "authorName", recordType: recordType)
        }
        guard let authorID = record["authorID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "authorID", recordType: recordType)
        }
        guard let duration = record["duration"] as? Double else {
            throw CloudKitError.missingRequiredField(field: "duration", recordType: recordType)
        }
        guard let watchedSeconds = record["watchedSeconds"] as? Double else {
            throw CloudKitError.missingRequiredField(field: "watchedSeconds", recordType: recordType)
        }
        guard let isFinishedInt = record["isFinished"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "isFinished", recordType: recordType)
        }
        guard let createdAt = record["createdAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "createdAt", recordType: recordType)
        }
        guard let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "updatedAt", recordType: recordType)
        }

        // Create watch entry
        let watchEntry = WatchEntry(
            videoID: videoID,
            sourceRawValue: sourceRawValue,
            globalProvider: record["globalProvider"] as? String,
            instanceURLString: record["instanceURLString"] as? String,
            peertubeUUID: record["peertubeUUID"] as? String,
            externalExtractor: record["externalExtractor"] as? String,
            externalURLString: record["externalURLString"] as? String,
            title: title,
            authorName: authorName,
            authorID: authorID,
            duration: duration,
            thumbnailURLString: record["thumbnailURLString"] as? String,
            watchedSeconds: watchedSeconds,
            isFinished: isFinishedInt == 1
        )

        // Set timestamps
        watchEntry.createdAt = createdAt
        watchEntry.updatedAt = updatedAt
        watchEntry.finishedAt = record["finishedAt"] as? Date

        return watchEntry
    }
    
    // MARK: - Bookmark Mapping
    
    /// Converts a Bookmark to a CKRecord.
    func toCKRecord(bookmark: Bookmark) -> CKRecord {
        let scope = SourceScope.from(
            sourceRawValue: bookmark.sourceRawValue,
            globalProvider: bookmark.globalProvider,
            instanceURLString: bookmark.instanceURLString,
            externalExtractor: bookmark.externalExtractor
        )
        let recordID = SyncableRecordType.bookmark(videoID: bookmark.videoID, scope: scope).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.bookmark, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        // Video Identity
        record["videoID"] = bookmark.videoID as CKRecordValue
        record["sourceRawValue"] = bookmark.sourceRawValue as CKRecordValue
        record["globalProvider"] = bookmark.globalProvider as CKRecordValue?
        record["instanceURLString"] = bookmark.instanceURLString as CKRecordValue?
        record["peertubeUUID"] = bookmark.peertubeUUID as CKRecordValue?
        record["externalExtractor"] = bookmark.externalExtractor as CKRecordValue?
        record["externalURLString"] = bookmark.externalURLString as CKRecordValue?

        // Video Metadata (cached)
        record["title"] = bookmark.title as CKRecordValue
        record["authorName"] = bookmark.authorName as CKRecordValue
        record["authorID"] = bookmark.authorID as CKRecordValue
        record["duration"] = bookmark.duration as CKRecordValue
        record["thumbnailURLString"] = bookmark.thumbnailURLString as CKRecordValue?
        record["isLive"] = (bookmark.isLive ? 1 : 0) as CKRecordValue
        record["viewCount"] = bookmark.viewCount.map { Int64($0) } as CKRecordValue?
        record["publishedAt"] = bookmark.publishedAt as CKRecordValue?
        record["publishedText"] = bookmark.publishedText as CKRecordValue?

        // Bookmark Metadata
        record["createdAt"] = bookmark.createdAt as CKRecordValue
        record["note"] = bookmark.note as CKRecordValue?
        record["noteModifiedAt"] = bookmark.noteModifiedAt as CKRecordValue?
        record["tags"] = bookmark.tags as CKRecordValue
        record["tagsModifiedAt"] = bookmark.tagsModifiedAt as CKRecordValue?
        record["sortOrder"] = Int64(bookmark.sortOrder) as CKRecordValue

        return record
    }
    
    /// Creates a Bookmark from a CKRecord.
    func toBookmark(from record: CKRecord) throws -> Bookmark {
        let recordType = RecordType.bookmark
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let videoID = record["videoID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "videoID", recordType: recordType)
        }
        guard let sourceRawValue = record["sourceRawValue"] as? String else {
            throw CloudKitError.missingRequiredField(field: "sourceRawValue", recordType: recordType)
        }
        guard let title = record["title"] as? String else {
            throw CloudKitError.missingRequiredField(field: "title", recordType: recordType)
        }
        guard let authorName = record["authorName"] as? String else {
            throw CloudKitError.missingRequiredField(field: "authorName", recordType: recordType)
        }
        guard let authorID = record["authorID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "authorID", recordType: recordType)
        }
        guard let duration = record["duration"] as? Double else {
            throw CloudKitError.missingRequiredField(field: "duration", recordType: recordType)
        }
        guard let isLiveInt = record["isLive"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "isLive", recordType: recordType)
        }
        guard let createdAt = record["createdAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "createdAt", recordType: recordType)
        }
        guard let sortOrderInt = record["sortOrder"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "sortOrder", recordType: recordType)
        }

        // Create bookmark
        let bookmark = Bookmark(
            videoID: videoID,
            sourceRawValue: sourceRawValue,
            globalProvider: record["globalProvider"] as? String,
            instanceURLString: record["instanceURLString"] as? String,
            peertubeUUID: record["peertubeUUID"] as? String,
            externalExtractor: record["externalExtractor"] as? String,
            externalURLString: record["externalURLString"] as? String,
            title: title,
            authorName: authorName,
            authorID: authorID,
            duration: duration,
            thumbnailURLString: record["thumbnailURLString"] as? String,
            isLive: isLiveInt == 1,
            viewCount: (record["viewCount"] as? Int64).map(Int.init),
            publishedAt: record["publishedAt"] as? Date,
            publishedText: record["publishedText"] as? String,
            note: record["note"] as? String,
            noteModifiedAt: record["noteModifiedAt"] as? Date,
            tags: record["tags"] as? [String] ?? [],
            tagsModifiedAt: record["tagsModifiedAt"] as? Date,
            sortOrder: Int(sortOrderInt)
        )

        // Set timestamp
        bookmark.createdAt = createdAt

        return bookmark
    }
    
    // MARK: - LocalPlaylist Mapping
    
    /// Converts a LocalPlaylist to a CKRecord.
    func toCKRecord(playlist: LocalPlaylist) -> CKRecord {
        let recordID = SyncableRecordType.localPlaylist(id: playlist.id).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.localPlaylist, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        // Playlist Metadata
        record["playlistID"] = playlist.id.uuidString as CKRecordValue
        record["title"] = playlist.title as CKRecordValue
        record["playlistDescription"] = playlist.playlistDescription as CKRecordValue?
        record["createdAt"] = playlist.createdAt as CKRecordValue
        record["updatedAt"] = playlist.updatedAt as CKRecordValue

        return record
    }
    
    /// Creates a LocalPlaylist from a CKRecord.
    func toLocalPlaylist(from record: CKRecord) throws -> LocalPlaylist {
        let recordType = RecordType.localPlaylist
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let playlistIDString = record["playlistID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "playlistID", recordType: recordType)
        }
        guard let playlistID = UUID(uuidString: playlistIDString) else {
            throw CloudKitError.typeMismatch(field: "playlistID", recordType: recordType, expected: "valid UUID string")
        }
        guard let title = record["title"] as? String else {
            throw CloudKitError.missingRequiredField(field: "title", recordType: recordType)
        }
        guard let createdAt = record["createdAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "createdAt", recordType: recordType)
        }
        guard let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "updatedAt", recordType: recordType)
        }

        // Create playlist
        let playlist = LocalPlaylist(
            id: playlistID,
            title: title,
            description: record["playlistDescription"] as? String
        )

        // Set timestamps
        playlist.createdAt = createdAt
        playlist.updatedAt = updatedAt

        return playlist
    }
    
    // MARK: - LocalPlaylistItem Mapping
    
    /// Converts a LocalPlaylistItem to a CKRecord.
    func toCKRecord(playlistItem: LocalPlaylistItem) -> CKRecord {
        let recordID = SyncableRecordType.localPlaylistItem(id: playlistItem.id).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.localPlaylistItem, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        // Item Identity
        record["itemID"] = playlistItem.id.uuidString as CKRecordValue
        record["playlistID"] = playlistItem.playlist?.id.uuidString as CKRecordValue?
        record["sortOrder"] = Int64(playlistItem.sortOrder) as CKRecordValue

        // Video Identity
        record["videoID"] = playlistItem.videoID as CKRecordValue
        record["sourceRawValue"] = playlistItem.sourceRawValue as CKRecordValue
        record["globalProvider"] = playlistItem.globalProvider as CKRecordValue?
        record["instanceURLString"] = playlistItem.instanceURLString as CKRecordValue?
        record["peertubeUUID"] = playlistItem.peertubeUUID as CKRecordValue?
        record["externalExtractor"] = playlistItem.externalExtractor as CKRecordValue?
        record["externalURLString"] = playlistItem.externalURLString as CKRecordValue?

        // Video Metadata
        record["title"] = playlistItem.title as CKRecordValue
        record["authorName"] = playlistItem.authorName as CKRecordValue
        record["authorID"] = playlistItem.authorID as CKRecordValue
        record["duration"] = playlistItem.duration as CKRecordValue
        record["thumbnailURLString"] = playlistItem.thumbnailURLString as CKRecordValue?
        record["isLive"] = (playlistItem.isLive ? 1 : 0) as CKRecordValue
        record["addedAt"] = playlistItem.addedAt as CKRecordValue

        return record
    }
    
    /// Creates a LocalPlaylistItem from a CKRecord.
    func toLocalPlaylistItem(from record: CKRecord) throws -> (item: LocalPlaylistItem, playlistID: UUID?) {
        let recordType = RecordType.localPlaylistItem
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let itemIDString = record["itemID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "itemID", recordType: recordType)
        }
        guard let itemID = UUID(uuidString: itemIDString) else {
            throw CloudKitError.typeMismatch(field: "itemID", recordType: recordType, expected: "valid UUID string")
        }
        guard let sortOrderInt = record["sortOrder"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "sortOrder", recordType: recordType)
        }
        guard let videoID = record["videoID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "videoID", recordType: recordType)
        }
        guard let sourceRawValue = record["sourceRawValue"] as? String else {
            throw CloudKitError.missingRequiredField(field: "sourceRawValue", recordType: recordType)
        }
        guard let title = record["title"] as? String else {
            throw CloudKitError.missingRequiredField(field: "title", recordType: recordType)
        }
        guard let authorName = record["authorName"] as? String else {
            throw CloudKitError.missingRequiredField(field: "authorName", recordType: recordType)
        }
        guard let authorID = record["authorID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "authorID", recordType: recordType)
        }
        guard let duration = record["duration"] as? Double else {
            throw CloudKitError.missingRequiredField(field: "duration", recordType: recordType)
        }
        guard let isLiveInt = record["isLive"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "isLive", recordType: recordType)
        }
        guard let addedAt = record["addedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "addedAt", recordType: recordType)
        }

        // Extract playlist ID
        let playlistID: UUID?
        if let playlistIDString = record["playlistID"] as? String {
            playlistID = UUID(uuidString: playlistIDString)
        } else {
            playlistID = nil
        }

        // Create playlist item
        let item = LocalPlaylistItem(
            id: itemID,
            sortOrder: Int(sortOrderInt),
            videoID: videoID,
            sourceRawValue: sourceRawValue,
            globalProvider: record["globalProvider"] as? String,
            instanceURLString: record["instanceURLString"] as? String,
            peertubeUUID: record["peertubeUUID"] as? String,
            externalExtractor: record["externalExtractor"] as? String,
            externalURLString: record["externalURLString"] as? String,
            title: title,
            authorName: authorName,
            authorID: authorID,
            duration: duration,
            thumbnailURLString: record["thumbnailURLString"] as? String,
            isLive: isLiveInt == 1
        )

        // Set timestamp
        item.addedAt = addedAt

        return (item, playlistID)
    }
    
    // MARK: - SearchHistory Mapping
    
    /// Converts a SearchHistory to a CKRecord.
    func toCKRecord(searchHistory: SearchHistory) -> CKRecord {
        let recordID = SyncableRecordType.searchHistory(id: searchHistory.id).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.searchHistory, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        record["searchID"] = searchHistory.id.uuidString as CKRecordValue
        record["query"] = searchHistory.query as CKRecordValue
        record["searchedAt"] = searchHistory.searchedAt as CKRecordValue

        return record
    }
    
    /// Creates a SearchHistory from a CKRecord.
    func toSearchHistory(from record: CKRecord) throws -> SearchHistory {
        let recordType = RecordType.searchHistory
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let searchIDString = record["searchID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "searchID", recordType: recordType)
        }
        guard let searchID = UUID(uuidString: searchIDString) else {
            throw CloudKitError.typeMismatch(field: "searchID", recordType: recordType, expected: "valid UUID string")
        }
        guard let query = record["query"] as? String else {
            throw CloudKitError.missingRequiredField(field: "query", recordType: recordType)
        }
        guard let searchedAt = record["searchedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "searchedAt", recordType: recordType)
        }

        return SearchHistory(id: searchID, query: query, searchedAt: searchedAt)
    }
    
    // MARK: - RecentChannel Mapping
    
    /// Converts a RecentChannel to a CKRecord.
    func toCKRecord(recentChannel: RecentChannel) -> CKRecord {
        let scope = SourceScope.from(
            sourceRawValue: recentChannel.sourceRawValue,
            globalProvider: nil,
            instanceURLString: recentChannel.instanceURLString,
            externalExtractor: nil
        )
        let recordID = SyncableRecordType.recentChannel(channelID: recentChannel.channelID, scope: scope).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.recentChannel, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        record["recentID"] = recentChannel.id.uuidString as CKRecordValue
        record["channelID"] = recentChannel.channelID as CKRecordValue
        record["sourceRawValue"] = recentChannel.sourceRawValue as CKRecordValue
        record["instanceURLString"] = recentChannel.instanceURLString as CKRecordValue?
        record["name"] = recentChannel.name as CKRecordValue
        record["thumbnailURLString"] = recentChannel.thumbnailURLString as CKRecordValue?
        record["subscriberCount"] = recentChannel.subscriberCount.map { Int64($0) } as CKRecordValue?
        record["isVerified"] = (recentChannel.isVerified ? 1 : 0) as CKRecordValue
        record["visitedAt"] = recentChannel.visitedAt as CKRecordValue

        return record
    }
    
    /// Creates a RecentChannel from a CKRecord.
    func toRecentChannel(from record: CKRecord) throws -> RecentChannel {
        let recordType = RecordType.recentChannel
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let recentIDString = record["recentID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "recentID", recordType: recordType)
        }
        guard let recentID = UUID(uuidString: recentIDString) else {
            throw CloudKitError.typeMismatch(field: "recentID", recordType: recordType, expected: "valid UUID string")
        }
        guard let channelID = record["channelID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "channelID", recordType: recordType)
        }
        guard let sourceRawValue = record["sourceRawValue"] as? String else {
            throw CloudKitError.missingRequiredField(field: "sourceRawValue", recordType: recordType)
        }
        guard let name = record["name"] as? String else {
            throw CloudKitError.missingRequiredField(field: "name", recordType: recordType)
        }
        guard let isVerifiedInt = record["isVerified"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "isVerified", recordType: recordType)
        }
        guard let visitedAt = record["visitedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "visitedAt", recordType: recordType)
        }

        return RecentChannel(
            id: recentID,
            channelID: channelID,
            sourceRawValue: sourceRawValue,
            instanceURLString: record["instanceURLString"] as? String,
            name: name,
            thumbnailURLString: record["thumbnailURLString"] as? String,
            subscriberCount: (record["subscriberCount"] as? Int64).map(Int.init),
            isVerified: isVerifiedInt == 1,
            visitedAt: visitedAt
        )
    }
    
    // MARK: - RecentPlaylist Mapping
    
    /// Converts a RecentPlaylist to a CKRecord.
    func toCKRecord(recentPlaylist: RecentPlaylist) -> CKRecord {
        let scope = SourceScope.from(
            sourceRawValue: recentPlaylist.sourceRawValue,
            globalProvider: nil,
            instanceURLString: recentPlaylist.instanceURLString,
            externalExtractor: nil
        )
        let recordID = SyncableRecordType.recentPlaylist(playlistID: recentPlaylist.playlistID, scope: scope).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.recentPlaylist, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        record["recentID"] = recentPlaylist.id.uuidString as CKRecordValue
        record["playlistID"] = recentPlaylist.playlistID as CKRecordValue
        record["sourceRawValue"] = recentPlaylist.sourceRawValue as CKRecordValue
        record["instanceURLString"] = recentPlaylist.instanceURLString as CKRecordValue?
        record["title"] = recentPlaylist.title as CKRecordValue
        record["authorName"] = recentPlaylist.authorName as CKRecordValue
        record["videoCount"] = Int64(recentPlaylist.videoCount) as CKRecordValue
        record["thumbnailURLString"] = recentPlaylist.thumbnailURLString as CKRecordValue?
        record["visitedAt"] = recentPlaylist.visitedAt as CKRecordValue

        return record
    }
    
    /// Creates a RecentPlaylist from a CKRecord.
    func toRecentPlaylist(from record: CKRecord) throws -> RecentPlaylist {
        let recordType = RecordType.recentPlaylist
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let recentIDString = record["recentID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "recentID", recordType: recordType)
        }
        guard let recentID = UUID(uuidString: recentIDString) else {
            throw CloudKitError.typeMismatch(field: "recentID", recordType: recordType, expected: "valid UUID string")
        }
        guard let playlistID = record["playlistID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "playlistID", recordType: recordType)
        }
        guard let sourceRawValue = record["sourceRawValue"] as? String else {
            throw CloudKitError.missingRequiredField(field: "sourceRawValue", recordType: recordType)
        }
        guard let title = record["title"] as? String else {
            throw CloudKitError.missingRequiredField(field: "title", recordType: recordType)
        }
        guard let authorName = record["authorName"] as? String else {
            throw CloudKitError.missingRequiredField(field: "authorName", recordType: recordType)
        }
        guard let videoCountInt = record["videoCount"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "videoCount", recordType: recordType)
        }
        guard let visitedAt = record["visitedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "visitedAt", recordType: recordType)
        }

        return RecentPlaylist(
            id: recentID,
            playlistID: playlistID,
            sourceRawValue: sourceRawValue,
            instanceURLString: record["instanceURLString"] as? String,
            title: title,
            authorName: authorName,
            videoCount: Int(videoCountInt),
            thumbnailURLString: record["thumbnailURLString"] as? String,
            visitedAt: visitedAt
        )
    }
    
    // MARK: - ChannelNotificationSettings Mapping
    
    /// Converts a ChannelNotificationSettings to a CKRecord.
    func toCKRecord(channelNotificationSettings settings: ChannelNotificationSettings) -> CKRecord {
        let scope = SourceScope.from(
            sourceRawValue: settings.sourceRawValue,
            globalProvider: settings.globalProvider,
            instanceURLString: settings.instanceURLString,
            externalExtractor: nil
        )
        let recordID = SyncableRecordType.channelNotificationSettings(channelID: settings.channelID, scope: scope).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.channelNotificationSettings, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        record["channelID"] = settings.channelID as CKRecordValue
        record["notificationsEnabled"] = (settings.notificationsEnabled ? 1 : 0) as CKRecordValue
        record["updatedAt"] = settings.updatedAt as CKRecordValue
        record["sourceRawValue"] = settings.sourceRawValue as CKRecordValue
        record["instanceURLString"] = settings.instanceURLString as CKRecordValue?
        record["globalProvider"] = settings.globalProvider as CKRecordValue?

        return record
    }
    
    /// Creates a ChannelNotificationSettings from a CKRecord.
    func toChannelNotificationSettings(from record: CKRecord) throws -> ChannelNotificationSettings {
        let recordType = RecordType.channelNotificationSettings
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let channelID = record["channelID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "channelID", recordType: recordType)
        }
        guard let notificationsEnabledInt = record["notificationsEnabled"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "notificationsEnabled", recordType: recordType)
        }
        guard let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "updatedAt", recordType: recordType)
        }

        let settings = ChannelNotificationSettings(
            channelID: channelID,
            notificationsEnabled: notificationsEnabledInt == 1,
            sourceRawValue: (record["sourceRawValue"] as? String) ?? "global",
            instanceURLString: record["instanceURLString"] as? String,
            globalProvider: record["globalProvider"] as? String
        )
        settings.updatedAt = updatedAt

        return settings
    }
    
    // MARK: - LayoutPreset Mapping
    
    /// Converts a LayoutPreset to a CKRecord.
    func toCKRecord(preset: LayoutPreset) throws -> CKRecord {
        let recordID = SyncableRecordType.controlsPreset(id: preset.id).recordID(in: zone)
        let record = CKRecord(recordType: RecordType.controlsPreset, recordID: recordID)

        // Schema version
        record["schemaVersion"] = currentSchemaVersion as CKRecordValue

        // Preset metadata
        record["presetID"] = preset.id.uuidString as CKRecordValue
        record["name"] = preset.name as CKRecordValue
        record["createdAt"] = preset.createdAt as CKRecordValue
        record["updatedAt"] = preset.updatedAt as CKRecordValue
        record["isBuiltIn"] = (preset.isBuiltIn ? 1 : 0) as CKRecordValue
        record["deviceClass"] = preset.deviceClass.rawValue as CKRecordValue

        // Encode layout as JSON string
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let layoutData = try encoder.encode(preset.layout)
        let layoutJSON = String(data: layoutData, encoding: .utf8) ?? "{}"
        record["layoutJSON"] = layoutJSON as CKRecordValue

        return record
    }
    
    /// Creates a LayoutPreset from a CKRecord.
    func toLayoutPreset(from record: CKRecord) throws -> LayoutPreset {
        let recordType = RecordType.controlsPreset
        guard record.recordType == recordType else {
            throw CloudKitError.recordNotFound
        }

        // Version check - treat missing version as v1 (first versioned release)
        let version = (record["schemaVersion"] as? Int64) ?? 1
        guard version <= currentSchemaVersion else {
            throw CloudKitError.unsupportedSchemaVersion(version: version, recordType: recordType)
        }

        // Required fields with specific error messages
        guard let presetIDString = record["presetID"] as? String else {
            throw CloudKitError.missingRequiredField(field: "presetID", recordType: recordType)
        }
        guard let presetID = UUID(uuidString: presetIDString) else {
            throw CloudKitError.typeMismatch(field: "presetID", recordType: recordType, expected: "valid UUID string")
        }
        guard let name = record["name"] as? String else {
            throw CloudKitError.missingRequiredField(field: "name", recordType: recordType)
        }
        guard let createdAt = record["createdAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "createdAt", recordType: recordType)
        }
        guard let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.missingRequiredField(field: "updatedAt", recordType: recordType)
        }
        guard let isBuiltInInt = record["isBuiltIn"] as? Int64 else {
            throw CloudKitError.missingRequiredField(field: "isBuiltIn", recordType: recordType)
        }
        guard let deviceClassRaw = record["deviceClass"] as? String else {
            throw CloudKitError.missingRequiredField(field: "deviceClass", recordType: recordType)
        }
        guard let deviceClass = DeviceClass(rawValue: deviceClassRaw) else {
            throw CloudKitError.typeMismatch(field: "deviceClass", recordType: recordType, expected: "valid DeviceClass value")
        }
        guard let layoutJSON = record["layoutJSON"] as? String else {
            throw CloudKitError.missingRequiredField(field: "layoutJSON", recordType: recordType)
        }
        guard let layoutData = layoutJSON.data(using: .utf8) else {
            throw CloudKitError.typeMismatch(field: "layoutJSON", recordType: recordType, expected: "valid UTF-8 JSON string")
        }

        // Decode layout
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let layout = try decoder.decode(PlayerControlsLayout.self, from: layoutData)

        return LayoutPreset(
            id: presetID,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isBuiltIn: isBuiltInInt == 1,
            deviceClass: deviceClass,
            layout: layout
        )
    }
}
