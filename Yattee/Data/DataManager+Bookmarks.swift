//
//  DataManager+Bookmarks.swift
//  Yattee
//
//  Bookmark operations for DataManager.
//

import Foundation
import SwiftData

extension DataManager {
    // MARK: - Bookmarks

    /// Adds a video to bookmarks.
    func addBookmark(for video: Video) {
        // Check if already bookmarked
        let videoID = video.id.videoID
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.videoID == videoID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            guard existing.isEmpty else {
                return
            }

            // Get max sort order
            let allBookmarks = try modelContext.fetch(FetchDescriptor<Bookmark>())
            let maxOrder = allBookmarks.map(\.sortOrder).max() ?? -1

            let bookmark = Bookmark.from(video: video, sortOrder: maxOrder + 1)
            modelContext.insert(bookmark)
            save()
            
            // Update cache immediately for fast lookup
            cachedBookmarkedVideoIDs.insert(videoID)
            
            // Queue for CloudKit sync
            cloudKitSync?.queueBookmarkSave(bookmark)
            
            NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to add bookmark", error: error)
        }
    }

    /// Removes a video from bookmarks.
    func removeBookmark(for videoID: String) {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.videoID == videoID }
        )

        do {
            let bookmarks = try modelContext.fetch(descriptor)
            guard !bookmarks.isEmpty else { return }

            // Capture scopes before deleting
            let scopes = bookmarks.map {
                SourceScope.from(
                    sourceRawValue: $0.sourceRawValue,
                    globalProvider: $0.globalProvider,
                    instanceURLString: $0.instanceURLString,
                    externalExtractor: $0.externalExtractor
                )
            }

            bookmarks.forEach { modelContext.delete($0) }
            save()

            // Update cache immediately for fast lookup
            cachedBookmarkedVideoIDs.remove(videoID)

            // Queue scoped CloudKit deletions
            for scope in scopes {
                cloudKitSync?.queueBookmarkDelete(videoID: videoID, scope: scope)
            }

            NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to remove bookmark", error: error)
        }
    }

    /// Checks if a video is bookmarked using cached Set for O(1) lookup.
    func isBookmarked(videoID: String) -> Bool {
        cachedBookmarkedVideoIDs.contains(videoID)
    }

    /// Gets all bookmarks, most recent first.
    func bookmarks(limit: Int = 100) -> [Bookmark] {
        var descriptor = FetchDescriptor<Bookmark>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch bookmarks", error: error)
            return []
        }
    }

    /// Gets the total count of bookmarks.
    func bookmarksCount() -> Int {
        let descriptor = FetchDescriptor<Bookmark>()
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            return 0
        }
    }
    
    /// Gets a bookmark for a specific video ID.
    func bookmark(for videoID: String) -> Bookmark? {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.videoID == videoID }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Inserts a bookmark into the database.
    /// Used by CloudKitSyncEngine for applying remote bookmarks.
    func insertBookmark(_ bookmark: Bookmark) {
        // Check for duplicates
        let videoID = bookmark.videoID
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.videoID == videoID }
        )
        
        do {
            let existing = try modelContext.fetch(descriptor)
            if existing.isEmpty {
                modelContext.insert(bookmark)
                save()
            }
        } catch {
            // Insert anyway if we can't check
            modelContext.insert(bookmark)
            save()
        }
    }
    
    /// Updates bookmark tags and note for a video.
    func updateBookmark(videoID: String, tags: [String], note: String?) {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.videoID == videoID }
        )
        
        do {
            guard let bookmark = try modelContext.fetch(descriptor).first else {
                LoggingService.shared.logCloudKitError("Failed to update bookmark: not found", error: nil)
                return
            }
            
            let now = Date()
            
            // Update tags and timestamp if changed
            if bookmark.tags != tags {
                bookmark.tags = tags
                bookmark.tagsModifiedAt = now
            }
            
            // Update note and timestamp if changed
            if bookmark.note != note {
                bookmark.note = note
                bookmark.noteModifiedAt = now
            }
            
            save()
            
            // Queue for CloudKit sync
            cloudKitSync?.queueBookmarkSave(bookmark)
            
            NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to update bookmark", error: error)
        }
    }
}
