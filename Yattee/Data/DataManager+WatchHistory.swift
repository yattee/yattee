//
//  DataManager+WatchHistory.swift
//  Yattee
//
//  Watch history operations for DataManager.
//

import Foundation
import SwiftData

extension DataManager {
    // MARK: - Watch History

    /// Records or updates watch progress locally without triggering iCloud sync.
    /// Use this for frequent updates during playback to avoid unnecessary sync overhead.
    func updateWatchProgressLocal(for video: Video, seconds: TimeInterval, duration: TimeInterval? = nil) {
        let videoID = video.id.videoID
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.videoID == videoID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            if let existingEntry = existing.first {
                existingEntry.updateProgress(seconds: seconds, duration: duration)
                save()
            } else {
                let newEntry = WatchEntry.from(video: video)
                newEntry.watchedSeconds = seconds
                if let duration, duration > 0, newEntry.duration == 0 {
                    newEntry.duration = duration
                }
                modelContext.insert(newEntry)
                save()
                // Notify HomeView when a new entry is inserted (not on every progress update)
                NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
            }
            // Note: No CloudKit queueing - use updateWatchProgress() when sync is needed
        } catch {
            LoggingService.shared.logCloudKitError("Failed to update watch progress locally", error: error)
        }
    }

    /// Records or updates watch progress for a video and queues for iCloud sync.
    /// Use this when video closes or switches to sync the final progress.
    func updateWatchProgress(for video: Video, seconds: TimeInterval, duration: TimeInterval? = nil) {
        // Find existing entry or create new one
        let videoID = video.id.videoID
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.videoID == videoID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            let entry: WatchEntry
            if let existingEntry = existing.first {
                existingEntry.updateProgress(seconds: seconds, duration: duration)
                entry = existingEntry
            } else {
                let newEntry = WatchEntry.from(video: video)
                newEntry.watchedSeconds = seconds
                if let duration, duration > 0, newEntry.duration == 0 {
                    newEntry.duration = duration
                }
                modelContext.insert(newEntry)
                entry = newEntry
            }
            save()

            // Queue for CloudKit sync
            cloudKitSync?.queueWatchEntrySave(entry)
            TopShelfSnapshotWriter.writeContinueWatching(dataManager: self)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to update watch progress", error: error)
        }
    }

    /// Gets the watch progress for a video.
    func watchProgress(for videoID: String) -> TimeInterval? {
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.videoID == videoID }
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            return entries.first?.watchedSeconds
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch watch progress", error: error)
            return nil
        }
    }

    /// Gets all watch history entries, most recent first.
    func watchHistory(limit: Int = 100) -> [WatchEntry] {
        var descriptor = FetchDescriptor<WatchEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch watch history", error: error)
            return []
        }
    }

    /// Returns a dictionary of video ID to WatchEntry for efficient bulk lookup.
    func watchEntriesMap() -> [String: WatchEntry] {
        let entries = watchHistory(limit: 10000)
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.videoID, $0) })
    }

    /// Gets the total count of watch history entries.
    func watchHistoryCount() -> Int {
        let descriptor = FetchDescriptor<WatchEntry>()
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            return 0
        }
    }

    /// Gets the watch entry for a specific video ID.
    func watchEntry(for videoID: String) -> WatchEntry? {
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.videoID == videoID }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Inserts a watch entry into the database.
    /// Used by CloudKitSyncEngine for applying remote watch history.
    func insertWatchEntry(_ watchEntry: WatchEntry) {
        // Check for duplicates
        let videoID = watchEntry.videoID
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.videoID == videoID }
        )
        
        do {
            let existing = try modelContext.fetch(descriptor)
            if existing.isEmpty {
                modelContext.insert(watchEntry)
                save()
            }
        } catch {
            // Insert anyway if we can't check
            modelContext.insert(watchEntry)
            save()
        }
        TopShelfSnapshotWriter.writeContinueWatching(dataManager: self)
    }

    /// Clears all watch history.
    func clearWatchHistory() {
        let descriptor = FetchDescriptor<WatchEntry>()

        do {
            let entries = try modelContext.fetch(descriptor)
            guard !entries.isEmpty else { return }

            // Capture IDs and scopes before deleting
            let deleteInfo: [(videoID: String, scope: SourceScope)] = entries.map { entry in
                (entry.videoID, SourceScope.from(
                    sourceRawValue: entry.sourceRawValue,
                    globalProvider: entry.globalProvider,
                    instanceURLString: entry.instanceURLString,
                    externalExtractor: entry.externalExtractor
                ))
            }

            entries.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueWatchEntryDelete(videoID: info.videoID, scope: info.scope)
            }

            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
            LoggingService.shared.logCloudKit("Watch history cleared, queued \(deleteInfo.count) CloudKit deletions")
        } catch {
            LoggingService.shared.logCloudKitError("Failed to clear watch history", error: error)
        }
    }

    /// Clears watch history entries updated after a given date.
    /// Used for time-based clearing (e.g., "clear last hour").
    func clearWatchHistory(since date: Date) {
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.updatedAt >= date }
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            guard !entries.isEmpty else { return }

            // Capture IDs and scopes before deleting
            let deleteInfo: [(videoID: String, scope: SourceScope)] = entries.map { entry in
                (entry.videoID, SourceScope.from(
                    sourceRawValue: entry.sourceRawValue,
                    globalProvider: entry.globalProvider,
                    instanceURLString: entry.instanceURLString,
                    externalExtractor: entry.externalExtractor
                ))
            }

            entries.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueWatchEntryDelete(videoID: info.videoID, scope: info.scope)
            }

            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
            LoggingService.shared.logCloudKit("Watch history cleared since \(date), queued \(deleteInfo.count) CloudKit deletions")
        } catch {
            LoggingService.shared.logCloudKitError("Failed to clear watch history since date", error: error)
        }
    }

    /// Clears watch history entries older than a given date.
    /// Used for auto-cleanup of old history.
    func clearWatchHistory(olderThan date: Date) {
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.updatedAt < date }
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            guard !entries.isEmpty else { return }

            // Capture IDs and scopes before deleting
            let deleteInfo: [(videoID: String, scope: SourceScope)] = entries.map { entry in
                (entry.videoID, SourceScope.from(
                    sourceRawValue: entry.sourceRawValue,
                    globalProvider: entry.globalProvider,
                    instanceURLString: entry.instanceURLString,
                    externalExtractor: entry.externalExtractor
                ))
            }

            entries.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueWatchEntryDelete(videoID: info.videoID, scope: info.scope)
            }

            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
            LoggingService.shared.logCloudKit("Watch history cleared older than \(date), queued \(deleteInfo.count) CloudKit deletions")
        } catch {
            LoggingService.shared.logCloudKitError("Failed to clear old watch history", error: error)
        }
    }

    /// Removes a specific watch entry.
    func removeFromHistory(videoID: String) {
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.videoID == videoID }
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            guard !entries.isEmpty else { return }

            // Capture scopes before deleting
            let scopes = entries.map {
                SourceScope.from(
                    sourceRawValue: $0.sourceRawValue,
                    globalProvider: $0.globalProvider,
                    instanceURLString: $0.instanceURLString,
                    externalExtractor: $0.externalExtractor
                )
            }

            entries.forEach { modelContext.delete($0) }
            save()

            // Queue scoped CloudKit deletions
            for scope in scopes {
                cloudKitSync?.queueWatchEntryDelete(videoID: videoID, scope: scope)
            }

            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to remove from history", error: error)
        }
    }

    /// Marks a video as watched by creating or updating a WatchEntry with isFinished = true.
    func markAsWatched(video: Video) {
        let videoID = video.id.videoID
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { $0.videoID == videoID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            let entry: WatchEntry
            if let existingEntry = existing.first {
                existingEntry.isFinished = true
                existingEntry.updatedAt = Date()
                // Set watchedSeconds to duration for 100% progress
                if existingEntry.duration > 0 {
                    existingEntry.watchedSeconds = existingEntry.duration
                } else if video.duration > 0 {
                    existingEntry.duration = video.duration
                    existingEntry.watchedSeconds = video.duration
                }
                entry = existingEntry
            } else {
                let newEntry = WatchEntry.from(video: video)
                newEntry.isFinished = true
                // Set watchedSeconds to duration for 100% progress
                if video.duration > 0 {
                    newEntry.duration = video.duration
                    newEntry.watchedSeconds = video.duration
                }
                modelContext.insert(newEntry)
                entry = newEntry
            }
            save()

            // Queue for CloudKit sync
            cloudKitSync?.queueWatchEntrySave(entry)

            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to mark as watched", error: error)
        }
    }

    /// Marks a video as unwatched by removing the watch history entry entirely.
    func markAsUnwatched(videoID: String) {
        removeFromHistory(videoID: videoID)
    }

    /// Clears all in-progress (not finished, watched > 10 seconds) watch entries.
    func clearInProgressHistory() {
        let descriptor = FetchDescriptor<WatchEntry>(
            predicate: #Predicate { !$0.isFinished && $0.watchedSeconds > 10 }
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            guard !entries.isEmpty else { return }

            // Capture video IDs and scopes before deleting
            let deleteInfo: [(videoID: String, scope: SourceScope)] = entries.map { entry in
                (entry.videoID, SourceScope.from(
                    sourceRawValue: entry.sourceRawValue,
                    globalProvider: entry.globalProvider,
                    instanceURLString: entry.instanceURLString,
                    externalExtractor: entry.externalExtractor
                ))
            }

            // Delete all entries
            entries.forEach { modelContext.delete($0) }
            save()

            // Queue scoped CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueWatchEntryDelete(videoID: info.videoID, scope: info.scope)
            }

            // Post single notification
            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
            LoggingService.shared.logCloudKit("Cleared \(entries.count) in-progress watch entries")
        } catch {
            LoggingService.shared.logCloudKitError("Failed to clear in-progress history", error: error)
        }
    }
}
