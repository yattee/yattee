//
//  CloudKitConflictResolver.swift
//  Yattee
//
//  Handles conflict resolution when local and remote records differ.
//

import CloudKit
import Foundation

/// Resolves conflicts between local and remote CloudKit records.
actor CloudKitConflictResolver {
    // MARK: - Subscription Conflict Resolution
    
    /// Resolves a conflict between local and server subscription records.
    ///
    /// Strategy:
    /// - Keep record with most recent `lastUpdatedAt`
    /// - EXCEPT: always preserve local `notificationsEnabled` preference
    func resolveSubscriptionConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localDate = (local["lastUpdatedAt"] as? Date) ?? Date.distantPast
        let serverDate = (server["lastUpdatedAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        // This is required for CloudKit to accept the update
        let resolved = server
        
        // If local is newer, copy its fields to server record
        if localDate > serverDate {
            resolved["name"] = local["name"]
            resolved["channelDescription"] = local["channelDescription"]
            resolved["subscriberCount"] = local["subscriberCount"]
            resolved["avatarURLString"] = local["avatarURLString"]
            resolved["bannerURLString"] = local["bannerURLString"]
            resolved["isVerified"] = local["isVerified"]
            resolved["lastUpdatedAt"] = local["lastUpdatedAt"]
            resolved["providerName"] = local["providerName"]
        }
        
        // But always preserve local notification preference
        // (user's device-specific setting should not be overwritten by other devices)
        if let localNotifications = local["notificationsEnabled"] {
            resolved["notificationsEnabled"] = localNotifications
        }
        
        return resolved
    }
    
    // MARK: - WatchEntry Conflict Resolution
    
    /// Resolves a conflict between local and server watch entry records.
    ///
    /// Strategy:
    /// - Use most recent updatedAt for watch progress (respects "mark as unwatched")
    /// - Use most recent updatedAt for metadata fields
    /// - Preserve finishedAt from whichever record marked it finished
    func resolveWatchEntryConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localSeconds = (local["watchedSeconds"] as? Double) ?? 0
        let serverSeconds = (server["watchedSeconds"] as? Double) ?? 0
        
        let localFinished = ((local["isFinished"] as? Int64) ?? 0) == 1
        let serverFinished = ((server["isFinished"] as? Int64) ?? 0) == 1
        
        let localUpdated = (local["updatedAt"] as? Date) ?? Date.distantPast
        let serverUpdated = (server["updatedAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        // This is required for CloudKit to accept the update
        let resolved = server
        
        // Copy metadata from local if it's newer
        if localUpdated > serverUpdated {
            resolved["title"] = local["title"]
            resolved["authorName"] = local["authorName"]
            resolved["authorID"] = local["authorID"]
            resolved["duration"] = local["duration"]
            resolved["thumbnailURLString"] = local["thumbnailURLString"]
        }
        
        // Use watch progress from the most recently updated record
        // This respects user intent - if they marked as unwatched, that action wins
        if localUpdated > serverUpdated {
            resolved["watchedSeconds"] = localSeconds as CKRecordValue
            resolved["isFinished"] = (localFinished ? 1 : 0) as CKRecordValue
            resolved["finishedAt"] = local["finishedAt"]
        } else {
            resolved["watchedSeconds"] = serverSeconds as CKRecordValue
            resolved["isFinished"] = (serverFinished ? 1 : 0) as CKRecordValue
            resolved["finishedAt"] = server["finishedAt"]
        }
        
        // Use most recent updatedAt
        resolved["updatedAt"] = max(localUpdated, serverUpdated) as CKRecordValue
        
        return resolved
    }
    
    // MARK: - Bookmark Conflict Resolution
    
    /// Resolves a conflict between local and server bookmark records.
    ///
    /// Strategy:
    /// - Keep most recent createdAt (newest wins)
    /// - Preserve local note if it exists
    /// - Keep local sortOrder (user's manual ordering)
    func resolveBookmarkConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localCreated = (local["createdAt"] as? Date) ?? Date.distantPast
        let serverCreated = (server["createdAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        let resolved = server
        
        // If local is newer, copy its metadata to server record
        if localCreated > serverCreated {
            resolved["title"] = local["title"]
            resolved["authorName"] = local["authorName"]
            resolved["authorID"] = local["authorID"]
            resolved["duration"] = local["duration"]
            resolved["thumbnailURLString"] = local["thumbnailURLString"]
            resolved["isLive"] = local["isLive"]
            resolved["viewCount"] = local["viewCount"]
            resolved["publishedAt"] = local["publishedAt"]
            resolved["publishedText"] = local["publishedText"]
            resolved["createdAt"] = local["createdAt"]
        }
        
        // Resolve note based on timestamp (most recent wins)
        let localNoteModified = local["noteModifiedAt"] as? Date ?? Date.distantPast
        let serverNoteModified = server["noteModifiedAt"] as? Date ?? Date.distantPast
        
        if localNoteModified >= serverNoteModified {
            // Local note is newer or equal - use local
            resolved["note"] = local["note"]
            resolved["noteModifiedAt"] = local["noteModifiedAt"]
        } else {
            // Server note is newer - use server (already in resolved)
            // No need to set, already using server record
        }
        
        // Resolve tags based on timestamp (most recent wins)
        let localTagsModified = local["tagsModifiedAt"] as? Date ?? Date.distantPast
        let serverTagsModified = server["tagsModifiedAt"] as? Date ?? Date.distantPast
        
        if localTagsModified >= serverTagsModified {
            // Local tags are newer or equal - use local
            resolved["tags"] = local["tags"]
            resolved["tagsModifiedAt"] = local["tagsModifiedAt"]
        } else {
            // Server tags are newer - use server (already in resolved)
            // No need to set, already using server record
        }
        
        // Always preserve local sortOrder (user's manual ordering)
        if let localSortOrder = local["sortOrder"] {
            resolved["sortOrder"] = localSortOrder
        }
        
        return resolved
    }
    
    // MARK: - Playlist Conflict Resolution
    
    /// Resolves a conflict between local and server playlist records.
    ///
    /// Strategy:
    /// - Keep most recent updatedAt for metadata (title, description)
    /// - Preserve server recordChangeTag
    func resolveLocalPlaylistConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localUpdated = (local["updatedAt"] as? Date) ?? Date.distantPast
        let serverUpdated = (server["updatedAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        let resolved = server
        
        // If local is newer, copy its metadata to server record
        if localUpdated > serverUpdated {
            resolved["title"] = local["title"]
            resolved["playlistDescription"] = local["playlistDescription"]
            resolved["updatedAt"] = local["updatedAt"]
        }
        
        return resolved
    }
    
    /// Resolves a conflict between local and server playlist item records.
    ///
    /// Strategy:
    /// - Keep most recent addedAt for metadata
    /// - Preserve local sortOrder (user's ordering)
    func resolveLocalPlaylistItemConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localAdded = (local["addedAt"] as? Date) ?? Date.distantPast
        let serverAdded = (server["addedAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        let resolved = server
        
        // If local is newer, copy its metadata to server record
        if localAdded > serverAdded {
            resolved["title"] = local["title"]
            resolved["authorName"] = local["authorName"]
            resolved["authorID"] = local["authorID"]
            resolved["duration"] = local["duration"]
            resolved["thumbnailURLString"] = local["thumbnailURLString"]
            resolved["isLive"] = local["isLive"]
        }
        
        // Always preserve local sortOrder (user's manual ordering)
        if let localSortOrder = local["sortOrder"] {
            resolved["sortOrder"] = localSortOrder
        }
        
        return resolved
    }
    
    // MARK: - SearchHistory Conflict Resolution
    
    /// Resolves a conflict between local and server search history records.
    ///
    /// Strategy:
    /// - Keep most recent searchedAt (newest wins)
    /// - Preserve server recordChangeTag
    func resolveSearchHistoryConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localSearched = (local["searchedAt"] as? Date) ?? Date.distantPast
        let serverSearched = (server["searchedAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        let resolved = server
        
        // If local is newer, copy its fields to server record
        if localSearched > serverSearched {
            resolved["query"] = local["query"]
            resolved["searchedAt"] = local["searchedAt"]
        }
        
        return resolved
    }
    
    // MARK: - RecentChannel Conflict Resolution
    
    /// Resolves a conflict between local and server recent channel records.
    ///
    /// Strategy:
    /// - Keep most recent visitedAt (newest wins)
    /// - Preserve server recordChangeTag
    func resolveRecentChannelConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localVisited = (local["visitedAt"] as? Date) ?? Date.distantPast
        let serverVisited = (server["visitedAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        let resolved = server
        
        // If local is newer, copy its fields to server record
        if localVisited > serverVisited {
            resolved["name"] = local["name"]
            resolved["avatarURLString"] = local["avatarURLString"]
            resolved["providerName"] = local["providerName"]
            resolved["visitedAt"] = local["visitedAt"]
        }
        
        return resolved
    }
    
    // MARK: - RecentPlaylist Conflict Resolution
    
    /// Resolves a conflict between local and server recent playlist records.
    ///
    /// Strategy:
    /// - Keep most recent visitedAt (newest wins)
    /// - Preserve server recordChangeTag
    func resolveRecentPlaylistConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localVisited = (local["visitedAt"] as? Date) ?? Date.distantPast
        let serverVisited = (server["visitedAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        let resolved = server
        
        // If local is newer, copy its fields to server record
        if localVisited > serverVisited {
            resolved["title"] = local["title"]
            resolved["authorName"] = local["authorName"]
            resolved["authorID"] = local["authorID"]
            resolved["thumbnailURLString"] = local["thumbnailURLString"]
            resolved["videoCount"] = local["videoCount"]
            resolved["providerName"] = local["providerName"]
            resolved["visitedAt"] = local["visitedAt"]
        }
        
        return resolved
    }
    
    // MARK: - LayoutPreset Conflict Resolution
    
    /// Resolves a conflict between local and server layout preset records.
    ///
    /// Strategy:
    /// - Last write wins based on updatedAt timestamp
    /// - Preserve server recordChangeTag
    func resolveLayoutPresetConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        let localUpdated = (local["updatedAt"] as? Date) ?? Date.distantPast
        let serverUpdated = (server["updatedAt"] as? Date) ?? Date.distantPast
        
        // IMPORTANT: Always start with server record to preserve recordChangeTag
        let resolved = server
        
        // If local is newer, copy its fields to server record
        if localUpdated > serverUpdated {
            resolved["name"] = local["name"]
            resolved["updatedAt"] = local["updatedAt"]
            resolved["layoutJSON"] = local["layoutJSON"]
        }
        
        return resolved
    }
}
