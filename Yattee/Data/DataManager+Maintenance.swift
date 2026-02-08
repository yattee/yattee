//
//  DataManager+Maintenance.swift
//  Yattee
//
//  Media source cleanup and deduplication operations for DataManager.
//

import Foundation
import SwiftData

extension DataManager {
    // MARK: - Media Source Cleanup

    /// Removes all watch history entries for videos from a specific media source.
    func removeHistoryForMediaSource(sourceID: UUID) {
        let prefix = sourceID.uuidString + ":"
        let descriptor = FetchDescriptor<WatchEntry>()

        do {
            let allEntries = try modelContext.fetch(descriptor)
            let toDelete = allEntries.filter { $0.videoID.hasPrefix(prefix) }
            guard !toDelete.isEmpty else { return }

            // Capture IDs and scopes before deleting
            let deleteInfo: [(videoID: String, scope: SourceScope)] = toDelete.map { entry in
                (entry.videoID, SourceScope.from(
                    sourceRawValue: entry.sourceRawValue,
                    globalProvider: entry.globalProvider,
                    instanceURLString: entry.instanceURLString,
                    externalExtractor: entry.externalExtractor
                ))
            }

            toDelete.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueWatchEntryDelete(videoID: info.videoID, scope: info.scope)
            }

            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
            LoggingService.shared.debug("Removed \(toDelete.count) history entries for media source \(sourceID)", category: .general)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to remove history for media source", error: error)
        }
    }

    /// Removes all bookmarks for videos from a specific media source.
    func removeBookmarksForMediaSource(sourceID: UUID) {
        let prefix = sourceID.uuidString + ":"
        let descriptor = FetchDescriptor<Bookmark>()

        do {
            let allBookmarks = try modelContext.fetch(descriptor)
            let toDelete = allBookmarks.filter { $0.videoID.hasPrefix(prefix) }
            guard !toDelete.isEmpty else { return }

            // Capture IDs and scopes before deleting
            let deleteInfo: [(videoID: String, scope: SourceScope)] = toDelete.map { bookmark in
                (bookmark.videoID, SourceScope.from(
                    sourceRawValue: bookmark.sourceRawValue,
                    globalProvider: bookmark.globalProvider,
                    instanceURLString: bookmark.instanceURLString,
                    externalExtractor: bookmark.externalExtractor
                ))
            }

            toDelete.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueBookmarkDelete(videoID: info.videoID, scope: info.scope)
            }

            NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
            LoggingService.shared.debug("Removed \(toDelete.count) bookmarks for media source \(sourceID)", category: .general)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to remove bookmarks for media source", error: error)
        }
    }

    /// Removes all playlist items for videos from a specific media source.
    func removePlaylistItemsForMediaSource(sourceID: UUID) {
        let prefix = sourceID.uuidString + ":"
        let descriptor = FetchDescriptor<LocalPlaylistItem>()

        do {
            let allItems = try modelContext.fetch(descriptor)
            let toDelete = allItems.filter { $0.videoID.hasPrefix(prefix) }
            guard !toDelete.isEmpty else { return }

            // Capture IDs before deleting
            let itemIDs = toDelete.map { $0.id }

            toDelete.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for itemID in itemIDs {
                cloudKitSync?.queuePlaylistItemDelete(itemID: itemID)
            }

            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
            LoggingService.shared.debug("Removed \(toDelete.count) playlist items for media source \(sourceID)", category: .general)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to remove playlist items for media source", error: error)
        }
    }

    /// Removes all data associated with a media source (history, bookmarks, playlist items).
    func removeAllDataForMediaSource(sourceID: UUID) {
        removeHistoryForMediaSource(sourceID: sourceID)
        removeBookmarksForMediaSource(sourceID: sourceID)
        removePlaylistItemsForMediaSource(sourceID: sourceID)
    }

    // MARK: - Deduplication

    /// Results from a deduplication operation.
    struct DeduplicationResult {
        var subscriptionsRemoved: Int = 0
        var bookmarksRemoved: Int = 0
        var historyEntriesRemoved: Int = 0
        var playlistsRemoved: Int = 0
        var playlistItemsRemoved: Int = 0

        var totalRemoved: Int {
            subscriptionsRemoved + bookmarksRemoved + historyEntriesRemoved + playlistsRemoved + playlistItemsRemoved
        }

        var summary: String {
            var parts: [String] = []
            if subscriptionsRemoved > 0 { parts.append("\(subscriptionsRemoved) subscriptions") }
            if bookmarksRemoved > 0 { parts.append("\(bookmarksRemoved) bookmarks") }
            if historyEntriesRemoved > 0 { parts.append("\(historyEntriesRemoved) history entries") }
            if playlistsRemoved > 0 { parts.append("\(playlistsRemoved) playlists") }
            if playlistItemsRemoved > 0 { parts.append("\(playlistItemsRemoved) playlist items") }
            return parts.isEmpty ? "No duplicates found" : "Removed: " + parts.joined(separator: ", ")
        }
    }

    /// Removes all duplicate entries from subscriptions, bookmarks, history, and playlists.
    func deduplicateAllData() -> DeduplicationResult {
        var result = DeduplicationResult()

        result.subscriptionsRemoved = deduplicateSubscriptions()
        result.bookmarksRemoved = deduplicateBookmarks()
        result.historyEntriesRemoved = deduplicateWatchHistory()
        let (playlists, items) = deduplicatePlaylists()
        result.playlistsRemoved = playlists
        result.playlistItemsRemoved = items

        LoggingService.shared.logCloudKit("Deduplication completed: \(result.summary)")
        return result
    }

    /// Removes duplicate subscriptions, keeping the oldest one.
    func deduplicateSubscriptions() -> Int {
        let allSubscriptions = subscriptions()
        var seenChannelIDs = Set<String>()
        var duplicates: [Subscription] = []

        // Sort by subscribedAt to keep the oldest
        let sorted = allSubscriptions.sorted { $0.subscribedAt < $1.subscribedAt }

        for subscription in sorted {
            if seenChannelIDs.contains(subscription.channelID) {
                duplicates.append(subscription)
                LoggingService.shared.logCloudKit("Found duplicate subscription: \(subscription.name) (\(subscription.channelID))")
            } else {
                seenChannelIDs.insert(subscription.channelID)
            }
        }

        for duplicate in duplicates {
            modelContext.delete(duplicate)
        }

        if !duplicates.isEmpty {
            save()
            SubscriptionFeedCache.shared.invalidate()
        }

        return duplicates.count
    }

    /// Removes duplicate bookmarks, keeping the oldest one.
    func deduplicateBookmarks() -> Int {
        let allBookmarks = bookmarks(limit: 10000)
        var seenVideoIDs = Set<String>()
        var duplicates: [Bookmark] = []

        // Sort by createdAt to keep the oldest
        let sorted = allBookmarks.sorted { $0.createdAt < $1.createdAt }

        for bookmark in sorted {
            if seenVideoIDs.contains(bookmark.videoID) {
                duplicates.append(bookmark)
                LoggingService.shared.logCloudKit("Found duplicate bookmark: \(bookmark.title) (\(bookmark.videoID))")
            } else {
                seenVideoIDs.insert(bookmark.videoID)
            }
        }

        for duplicate in duplicates {
            modelContext.delete(duplicate)
        }

        if !duplicates.isEmpty {
            save()
        }

        return duplicates.count
    }

    /// Removes duplicate watch history entries, keeping the one with most progress.
    func deduplicateWatchHistory() -> Int {
        let allEntries = watchHistory(limit: 10000)
        var bestByVideoID = [String: WatchEntry]()
        var duplicates: [WatchEntry] = []

        for entry in allEntries {
            if let existing = bestByVideoID[entry.videoID] {
                // Keep the one with more progress, or mark finished if either is
                if entry.watchedSeconds > existing.watchedSeconds {
                    duplicates.append(existing)
                    bestByVideoID[entry.videoID] = entry
                    LoggingService.shared.logCloudKit("Found duplicate history (keeping newer progress): \(entry.title) (\(entry.videoID))")
                } else {
                    duplicates.append(entry)
                    LoggingService.shared.logCloudKit("Found duplicate history (keeping existing progress): \(entry.title) (\(entry.videoID))")
                }
            } else {
                bestByVideoID[entry.videoID] = entry
            }
        }

        for duplicate in duplicates {
            modelContext.delete(duplicate)
        }

        if !duplicates.isEmpty {
            save()
        }

        return duplicates.count
    }

    /// Removes duplicate playlists and playlist items.
    func deduplicatePlaylists() -> (playlists: Int, items: Int) {
        let allPlaylists = playlists()
        var seenPlaylistIDs = Set<UUID>()
        var duplicatePlaylists: [LocalPlaylist] = []
        var totalDuplicateItems = 0

        // Sort by createdAt to keep the oldest
        let sorted = allPlaylists.sorted { $0.createdAt < $1.createdAt }

        for playlist in sorted {
            if seenPlaylistIDs.contains(playlist.id) {
                duplicatePlaylists.append(playlist)
                LoggingService.shared.logCloudKit("Found duplicate playlist: \(playlist.title) (\(playlist.id))")
            } else {
                seenPlaylistIDs.insert(playlist.id)

                // Also deduplicate items within the playlist
                var seenItemVideoIDs = Set<String>()
                var duplicateItems: [LocalPlaylistItem] = []

                let sortedItems = playlist.sortedItems

                for item in sortedItems {
                    if seenItemVideoIDs.contains(item.videoID) {
                        duplicateItems.append(item)
                        LoggingService.shared.logCloudKit("Found duplicate playlist item: \(item.title) in playlist \(playlist.title)")
                    } else {
                        seenItemVideoIDs.insert(item.videoID)
                    }
                }

                for duplicateItem in duplicateItems {
                    modelContext.delete(duplicateItem)
                }
                totalDuplicateItems += duplicateItems.count
            }
        }

        for duplicate in duplicatePlaylists {
            modelContext.delete(duplicate)
        }

        if !duplicatePlaylists.isEmpty || totalDuplicateItems > 0 {
            save()
        }

        return (duplicatePlaylists.count, totalDuplicateItems)
    }
}
