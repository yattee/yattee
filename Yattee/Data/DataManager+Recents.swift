//
//  DataManager+Recents.swift
//  Yattee
//
//  Search history, recent channels, and recent playlists operations for DataManager.
//

import Foundation
import SwiftData

extension DataManager {
    // MARK: - Search History
    
    /// Adds a search query to history. If query already exists (case-insensitive),
    /// updates its timestamp and moves to top. Enforces user-configured limit.
    func addSearchQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        let lowercased = trimmed.lowercased()
        
        // Check for existing query (case-insensitive)
        let fetchDescriptor = FetchDescriptor<SearchHistory>()
        let savedEntry: SearchHistory
        if let existing = (try? modelContext.fetch(fetchDescriptor))?.first(where: {
            $0.query.lowercased() == lowercased
        }) {
            // Update timestamp to move to top
            existing.searchedAt = Date()
            savedEntry = existing
        } else {
            // Create new entry
            let newHistory = SearchHistory(query: trimmed, searchedAt: Date())
            modelContext.insert(newHistory)
            savedEntry = newHistory
        }
        
        // Enforce limit
        enforceSearchHistoryLimit()
        
        save()
        
        // Queue for CloudKit sync
        cloudKitSync?.queueSearchHistorySave(savedEntry)
        
        NotificationCenter.default.post(name: .searchHistoryDidChange, object: nil)
    }
    
    /// Fetches search history ordered by most recent first.
    func fetchSearchHistory(limit: Int) -> [SearchHistory] {
        // Process pending changes to ensure we fetch fresh data
        modelContext.processPendingChanges()
        
        var fetchDescriptor = FetchDescriptor<SearchHistory>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        fetchDescriptor.fetchLimit = limit
        return (try? modelContext.fetch(fetchDescriptor)) ?? []
    }
    
    /// Deletes a specific search history entry.
    func deleteSearchQuery(_ history: SearchHistory) {
        let historyID = history.id
        modelContext.delete(history)
        save()
        
        // Queue for CloudKit sync
        cloudKitSync?.queueSearchHistoryDelete(id: historyID)
        
        NotificationCenter.default.post(name: .searchHistoryDidChange, object: nil)
    }
    
    /// Clears all search history.
    func clearSearchHistory() {
        let fetchDescriptor = FetchDescriptor<SearchHistory>()
        if let allHistory = try? modelContext.fetch(fetchDescriptor) {
            guard !allHistory.isEmpty else { return }

            // Capture IDs before deleting
            let ids = allHistory.map { $0.id }

            allHistory.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for id in ids {
                cloudKitSync?.queueSearchHistoryDelete(id: id)
            }

            NotificationCenter.default.post(name: .searchHistoryDidChange, object: nil)
        }
    }
    
    /// Enforces the user-configured search history limit by deleting oldest entries.
    func enforceSearchHistoryLimit() {
        // Get limit from settings (injected or default to 25)
        let limit = settingsManager?.searchHistoryLimit ?? 25
        guard limit > 0 else { return }

        let fetchDescriptor = FetchDescriptor<SearchHistory>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )

        guard let allHistory = try? modelContext.fetch(fetchDescriptor),
              allHistory.count > limit else { return }

        // Delete oldest entries beyond limit
        let toDelete = allHistory.dropFirst(limit)

        // Capture IDs before deleting
        let ids = toDelete.map { $0.id }

        toDelete.forEach { modelContext.delete($0) }

        // Queue CloudKit deletions
        for id in ids {
            cloudKitSync?.queueSearchHistoryDelete(id: id)
        }
    }
    
    /// Gets all search history (for CloudKit sync).
    func allSearchHistory() -> [SearchHistory] {
        let descriptor = FetchDescriptor<SearchHistory>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch search history", error: error)
            return []
        }
    }
    
    /// Gets a search history entry by ID (for CloudKit sync).
    func searchHistoryEntry(forID id: UUID) -> SearchHistory? {
        let descriptor = FetchDescriptor<SearchHistory>(
            predicate: #Predicate { $0.id == id }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Inserts a search history entry (for CloudKit sync).
    func insertSearchHistory(_ searchHistory: SearchHistory) {
        // Check for duplicates by ID
        if searchHistoryEntry(forID: searchHistory.id) == nil {
            modelContext.insert(searchHistory)
            save()
        }
    }

    // MARK: - Recent Channels

    /// Adds a channel to recent history. If channel already exists,
    /// updates its timestamp and moves to top. Enforces same limit as search history.
    func addRecentChannel(_ channel: Channel) {
        let channelID = channel.id.channelID
        
        // Check for existing entry
        let fetchDescriptor = FetchDescriptor<RecentChannel>(
            predicate: #Predicate { $0.channelID == channelID }
        )
        
        let savedEntry: RecentChannel
        if let existing = (try? modelContext.fetch(fetchDescriptor))?.first {
            // Update timestamp to move to top
            existing.visitedAt = Date()
            // Also update metadata in case channel info changed
            existing.name = channel.name
            existing.thumbnailURLString = channel.thumbnailURL?.absoluteString
            existing.subscriberCount = channel.subscriberCount
            existing.isVerified = channel.isVerified
            savedEntry = existing
        } else {
            // Create new entry
            let recentChannel = RecentChannel.from(channel: channel)
            modelContext.insert(recentChannel)
            savedEntry = recentChannel
        }
        
        // Enforce limit
        enforceRecentChannelsLimit()
        
        save()
        
        // Queue for CloudKit sync
        cloudKitSync?.queueRecentChannelSave(savedEntry)
        
        NotificationCenter.default.post(name: .recentChannelsDidChange, object: nil)
    }

    /// Fetches recent channels ordered by most recent first.
    func fetchRecentChannels(limit: Int) -> [RecentChannel] {
        // Process pending changes to ensure we fetch fresh data
        modelContext.processPendingChanges()
        
        var fetchDescriptor = FetchDescriptor<RecentChannel>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        fetchDescriptor.fetchLimit = limit
        return (try? modelContext.fetch(fetchDescriptor)) ?? []
    }

    /// Deletes a specific recent channel entry.
    func deleteRecentChannel(_ channel: RecentChannel) {
        let channelID = channel.channelID
        let scope = SourceScope.from(
            sourceRawValue: channel.sourceRawValue,
            globalProvider: nil,
            instanceURLString: channel.instanceURLString,
            externalExtractor: nil
        )
        modelContext.delete(channel)
        save()

        // Queue scoped CloudKit deletion
        cloudKitSync?.queueRecentChannelDelete(channelID: channelID, scope: scope)

        NotificationCenter.default.post(name: .recentChannelsDidChange, object: nil)
    }

    /// Clears all recent channels.
    func clearRecentChannels() {
        let fetchDescriptor = FetchDescriptor<RecentChannel>()
        if let allChannels = try? modelContext.fetch(fetchDescriptor) {
            guard !allChannels.isEmpty else { return }

            // Capture IDs and scopes before deleting
            let deleteInfo: [(channelID: String, scope: SourceScope)] = allChannels.map { channel in
                (channel.channelID, SourceScope.from(
                    sourceRawValue: channel.sourceRawValue,
                    globalProvider: nil,
                    instanceURLString: channel.instanceURLString,
                    externalExtractor: nil
                ))
            }

            allChannels.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueRecentChannelDelete(channelID: info.channelID, scope: info.scope)
            }

            NotificationCenter.default.post(name: .recentChannelsDidChange, object: nil)
        }
    }

    /// Enforces the user-configured limit by deleting oldest entries.
    func enforceRecentChannelsLimit() {
        let limit = settingsManager?.searchHistoryLimit ?? 25
        guard limit > 0 else { return }

        let fetchDescriptor = FetchDescriptor<RecentChannel>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )

        guard let allChannels = try? modelContext.fetch(fetchDescriptor),
              allChannels.count > limit else { return }

        // Delete oldest entries beyond limit
        let toDelete = allChannels.dropFirst(limit)

        // Capture IDs and scopes before deleting
        let deleteInfo: [(channelID: String, scope: SourceScope)] = toDelete.map { channel in
            (channel.channelID, SourceScope.from(
                sourceRawValue: channel.sourceRawValue,
                globalProvider: nil,
                instanceURLString: channel.instanceURLString,
                externalExtractor: nil
            ))
        }

        toDelete.forEach { modelContext.delete($0) }

        // Queue CloudKit deletions
        for info in deleteInfo {
            cloudKitSync?.queueRecentChannelDelete(channelID: info.channelID, scope: info.scope)
        }
    }
    
    /// Gets all recent channels (for CloudKit sync).
    func allRecentChannels() -> [RecentChannel] {
        let descriptor = FetchDescriptor<RecentChannel>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch recent channels", error: error)
            return []
        }
    }
    
    /// Gets a recent channel by channelID (for CloudKit sync).
    func recentChannelEntry(forChannelID channelID: String) -> RecentChannel? {
        let descriptor = FetchDescriptor<RecentChannel>(
            predicate: #Predicate { $0.channelID == channelID }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Inserts a recent channel (for CloudKit sync).
    func insertRecentChannel(_ recentChannel: RecentChannel) {
        // Check for duplicates by channelID
        if recentChannelEntry(forChannelID: recentChannel.channelID) == nil {
            modelContext.insert(recentChannel)
            save()
        }
    }

    // MARK: - Recent Playlists

    /// Adds a playlist to recent history (remote playlists only).
    /// If playlist already exists, updates its timestamp and moves to top.
    func addRecentPlaylist(_ playlist: Playlist) {
        // Skip local playlists
        guard let recentPlaylist = RecentPlaylist.from(playlist: playlist) else {
            return
        }
        
        let playlistID = playlist.id.playlistID
        
        // Check for existing entry
        let fetchDescriptor = FetchDescriptor<RecentPlaylist>(
            predicate: #Predicate { $0.playlistID == playlistID }
        )
        
        let savedEntry: RecentPlaylist
        if let existing = (try? modelContext.fetch(fetchDescriptor))?.first {
            // Update timestamp to move to top
            existing.visitedAt = Date()
            // Also update metadata
            existing.title = playlist.title
            existing.authorName = playlist.authorName
            existing.videoCount = playlist.videoCount
            existing.thumbnailURLString = playlist.thumbnailURL?.absoluteString
            savedEntry = existing
        } else {
            // Create new entry
            modelContext.insert(recentPlaylist)
            savedEntry = recentPlaylist
        }
        
        // Enforce limit
        enforceRecentPlaylistsLimit()
        
        save()
        
        // Queue for CloudKit sync
        cloudKitSync?.queueRecentPlaylistSave(savedEntry)
        
        NotificationCenter.default.post(name: .recentPlaylistsDidChange, object: nil)
    }

    /// Fetches recent playlists ordered by most recent first.
    func fetchRecentPlaylists(limit: Int) -> [RecentPlaylist] {
        // Process pending changes to ensure we fetch fresh data
        modelContext.processPendingChanges()
        
        var fetchDescriptor = FetchDescriptor<RecentPlaylist>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        fetchDescriptor.fetchLimit = limit
        return (try? modelContext.fetch(fetchDescriptor)) ?? []
    }

    /// Deletes a specific recent playlist entry.
    func deleteRecentPlaylist(_ playlist: RecentPlaylist) {
        let playlistID = playlist.playlistID
        let scope = SourceScope.from(
            sourceRawValue: playlist.sourceRawValue,
            globalProvider: nil,
            instanceURLString: playlist.instanceURLString,
            externalExtractor: nil
        )
        modelContext.delete(playlist)
        save()

        // Queue scoped CloudKit deletion
        cloudKitSync?.queueRecentPlaylistDelete(playlistID: playlistID, scope: scope)

        NotificationCenter.default.post(name: .recentPlaylistsDidChange, object: nil)
    }

    /// Clears all recent playlists.
    func clearRecentPlaylists() {
        let fetchDescriptor = FetchDescriptor<RecentPlaylist>()
        if let allPlaylists = try? modelContext.fetch(fetchDescriptor) {
            guard !allPlaylists.isEmpty else { return }

            // Capture IDs and scopes before deleting
            let deleteInfo: [(playlistID: String, scope: SourceScope)] = allPlaylists.map { playlist in
                (playlist.playlistID, SourceScope.from(
                    sourceRawValue: playlist.sourceRawValue,
                    globalProvider: nil,
                    instanceURLString: playlist.instanceURLString,
                    externalExtractor: nil
                ))
            }

            allPlaylists.forEach { modelContext.delete($0) }
            save()

            // Queue CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueRecentPlaylistDelete(playlistID: info.playlistID, scope: info.scope)
            }

            NotificationCenter.default.post(name: .recentPlaylistsDidChange, object: nil)
        }
    }

    /// Enforces the user-configured limit by deleting oldest entries.
    func enforceRecentPlaylistsLimit() {
        let limit = settingsManager?.searchHistoryLimit ?? 25
        guard limit > 0 else { return }

        let fetchDescriptor = FetchDescriptor<RecentPlaylist>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )

        guard let allPlaylists = try? modelContext.fetch(fetchDescriptor),
              allPlaylists.count > limit else { return }

        // Delete oldest entries beyond limit
        let toDelete = allPlaylists.dropFirst(limit)

        // Capture IDs and scopes before deleting
        let deleteInfo: [(playlistID: String, scope: SourceScope)] = toDelete.map { playlist in
            (playlist.playlistID, SourceScope.from(
                sourceRawValue: playlist.sourceRawValue,
                globalProvider: nil,
                instanceURLString: playlist.instanceURLString,
                externalExtractor: nil
            ))
        }

        toDelete.forEach { modelContext.delete($0) }

        // Queue CloudKit deletions
        for info in deleteInfo {
            cloudKitSync?.queueRecentPlaylistDelete(playlistID: info.playlistID, scope: info.scope)
        }
    }
    
    /// Gets all recent playlists (for CloudKit sync).
    func allRecentPlaylists() -> [RecentPlaylist] {
        let descriptor = FetchDescriptor<RecentPlaylist>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch recent playlists", error: error)
            return []
        }
    }
    
    /// Gets a recent playlist by playlistID (for CloudKit sync).
    func recentPlaylistEntry(forPlaylistID playlistID: String) -> RecentPlaylist? {
        let descriptor = FetchDescriptor<RecentPlaylist>(
            predicate: #Predicate { $0.playlistID == playlistID }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
    
    /// Inserts a recent playlist (for CloudKit sync).
    func insertRecentPlaylist(_ recentPlaylist: RecentPlaylist) {
        // Check for duplicates by playlistID
        if recentPlaylistEntry(forPlaylistID: recentPlaylist.playlistID) == nil {
            modelContext.insert(recentPlaylist)
            save()
        }
    }
}
