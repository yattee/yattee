//
//  SearchViewModel.swift
//  Yattee
//
//  Shared search logic for InstanceBrowseView and SearchView.
//

import Foundation
import SwiftUI

/// Unified search result item for displaying mixed content types.
enum SearchResultItem: Identifiable, Sendable {
    case video(Video, index: Int)
    case playlist(Playlist)
    case channel(Channel)

    var id: String {
        switch self {
        case .video(let video, _):
            return "video-\(video.id.id)"
        case .playlist(let playlist):
            return "playlist-\(playlist.id.id)"
        case .channel(let channel):
            return "channel-\(channel.id.id)"
        }
    }

    /// Whether this item is a channel (for divider alignment with circular avatar).
    var isChannel: Bool {
        if case .channel = self { return true }
        return false
    }
}

/// Observable view model for search functionality.
@Observable
@MainActor
final class SearchViewModel {
    // MARK: - Configuration

    let instance: Instance
    private let contentService: ContentService
    private let deArrowProvider: DeArrowBrandingProvider?
    private weak var dataManager: DataManager?
    private weak var settingsManager: SettingsManager?

    // MARK: - Search State

    var filters = SearchFilters()
    
    /// Hide watched videos (controlled by view options, not filters)
    var hideWatchedVideos: Bool = false

    /// Unified result items preserving API order (for InstanceBrowseView style display).
    private(set) var resultItems: [SearchResultItem] = []

    /// Separate video array for video queue functionality.
    private(set) var videos: [Video] = []

    /// Separate channel array (for SearchView style display).
    private(set) var channels: [Channel] = []

    /// Separate playlist array (for SearchView style display).
    private(set) var playlists: [Playlist] = []

    // MARK: - UI State

    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var errorMessage: String?
    private(set) var suggestions: [String] = []
    private(set) var isFetchingSuggestions = false

    // MARK: - Pagination

    private(set) var page = 1
    private(set) var hasMoreResults = true
    private(set) var isLoadingMore = false

    // MARK: - Private

    private var searchTask: Task<Void, Never>?
    private var suggestionsTask: Task<Void, Never>?
    private var lastQuery: String = ""
    
    /// Incremented each time filters change to detect stale results.
    private var filterVersion: Int = 0

    // MARK: - Computed

    var hasResults: Bool {
        !resultItems.isEmpty || !videos.isEmpty || !channels.isEmpty || !playlists.isEmpty
    }

    // MARK: - Init

    init(
        instance: Instance,
        contentService: ContentService,
        deArrowProvider: DeArrowBrandingProvider? = nil,
        dataManager: DataManager? = nil,
        settingsManager: SettingsManager? = nil
    ) {
        self.instance = instance
        self.contentService = contentService
        self.deArrowProvider = deArrowProvider
        self.dataManager = dataManager
        self.settingsManager = settingsManager
    }

    // MARK: - Search Methods

    /// Performs a search with the given query.
    /// - Parameters:
    ///   - query: The search query
    ///   - resetResults: Whether to reset pagination and clear existing results
    func search(query: String, resetResults: Bool = true) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return }
        
        // Cancel any in-flight search to prevent race conditions
        searchTask?.cancel()
        
        // Increment filter version to invalidate any pending results
        filterVersion += 1
        let versionAtStart = filterVersion
        let filtersAtStart = filters
        
        // Save to history if not in incognito mode and recent searches are enabled
        if settingsManager?.incognitoModeEnabled != true,
           settingsManager?.saveRecentSearches != false {
            dataManager?.addSearchQuery(trimmedQuery)
        }

        if resetResults {
            page = 1
            hasMoreResults = true
            resultItems = []
            videos = []
            channels = []
            playlists = []
        }

        lastQuery = trimmedQuery
        hasSearched = true
        isSearching = true
        errorMessage = nil

        // Store the task so it can be cancelled if filters change
        searchTask = Task {
            do {
                let result = try await contentService.search(
                    query: trimmedQuery,
                    instance: instance,
                    page: page,
                    filters: filtersAtStart
                )
                
                // Check if filters changed while we were waiting - discard stale results
                guard versionAtStart == filterVersion else { return }

                if resetResults {
                    // Fresh results
                    videos = filterWatchedVideos(result.videos)
                    channels = result.channels
                    playlists = result.playlists

                    // Build unified result items from ordered items
                    resultItems = result.orderedItems.enumerated().compactMap { _, item in
                        switch item {
                        case .video(let video):
                            // Skip watched videos if filter is enabled
                            if hideWatchedVideos && isVideoWatched(video) {
                                return nil
                            }
                            if let index = videos.firstIndex(where: { $0.id == video.id }) {
                                return .video(video, index: index)
                            }
                            return nil
                        case .channel(let channel):
                            return .channel(channel)
                        case .playlist(let playlist):
                            return .playlist(playlist)
                        }
                    }
                } else {
                    // Append with deduplication
                    let existingVideoIDs = Set(videos.map(\.id))
                    let existingChannelIDs = Set(channels.map(\.id))
                    let existingPlaylistIDs = Set(playlists.map(\.id))

                    let filteredNewVideos = filterWatchedVideos(result.videos)
                    let newVideos = filteredNewVideos.filter { !existingVideoIDs.contains($0.id) }
                    let newChannels = result.channels.filter { !existingChannelIDs.contains($0.id) }
                    let newPlaylists = result.playlists.filter { !existingPlaylistIDs.contains($0.id) }

                    // Append to separate arrays
                    videos.append(contentsOf: newVideos)
                    channels.append(contentsOf: newChannels)
                    playlists.append(contentsOf: newPlaylists)

                    // Append to unified result items
                    for item in result.orderedItems {
                        switch item {
                        case .video(let video):
                            // Skip watched videos if filter is enabled
                            if hideWatchedVideos && isVideoWatched(video) {
                                continue
                            }
                            guard !existingVideoIDs.contains(video.id) else { continue }
                            let videoIndex = videos.firstIndex(where: { $0.id == video.id }) ?? videos.count - 1
                            resultItems.append(.video(video, index: videoIndex))
                        case .channel(let channel):
                            guard !existingChannelIDs.contains(channel.id) else { continue }
                            resultItems.append(.channel(channel))
                        case .playlist(let playlist):
                            guard !existingPlaylistIDs.contains(playlist.id) else { continue }
                            resultItems.append(.playlist(playlist))
                        }
                    }
                }

                hasMoreResults = result.nextPage != nil
                prefetchBranding(for: result.videos)
            } catch {
                // Check if filters changed - don't show error for stale request
                guard versionAtStart == filterVersion else { return }
                // Don't report cancellation errors
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }

            isSearching = false
            isLoadingMore = false
        }
        
        await searchTask?.value
    }

    /// Loads more search results for the current query.
    func loadMore() async {
        guard hasMoreResults, !isLoadingMore, !isSearching, !lastQuery.isEmpty else { return }
        isLoadingMore = true
        page += 1
        await search(query: lastQuery, resetResults: false)
    }

    /// Clears all search results and resets state.
    func clearResults() {
        searchTask?.cancel()
        resultItems = []
        videos = []
        channels = []
        playlists = []
        errorMessage = nil
        page = 1
        hasMoreResults = true
        hasSearched = false
        suggestions = []
        suggestionsTask?.cancel()
        lastQuery = ""
    }

    /// Clears search results without clearing suggestions.
    /// Use when user is editing query but suggestions should persist.
    func clearSearchResults() {
        searchTask?.cancel()
        resultItems = []
        videos = []
        channels = []
        playlists = []
        errorMessage = nil
        page = 1
        hasMoreResults = true
        hasSearched = false
        lastQuery = ""
    }

    // MARK: - Suggestions

    /// Fetches search suggestions for the given query with debouncing.
    func fetchSuggestions(for query: String) {
        suggestionsTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else {
            suggestions = []
            isFetchingSuggestions = false
            return
        }

        isFetchingSuggestions = true

        suggestionsTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }

            do {
                let results = try await contentService.searchSuggestions(
                    query: trimmedQuery,
                    instance: instance
                )
                guard !Task.isCancelled else { return }
                suggestions = results
                isFetchingSuggestions = false
            } catch {
                // Only clear suggestions on actual errors, not cancellation
                guard !Task.isCancelled else { return }
                suggestions = []
                isFetchingSuggestions = false
            }
        }
    }

    /// Cancels any pending suggestions fetch.
    func cancelSuggestions() {
        suggestionsTask?.cancel()
        suggestions = []
        isFetchingSuggestions = false
    }

    // MARK: - Private

    private func prefetchBranding(for videos: [Video]) {
        guard let deArrowProvider else { return }
        let youtubeIDs = videos.compactMap { video -> String? in
            if case .global = video.id.source { return video.id.videoID }
            return nil
        }
        deArrowProvider.prefetch(videoIDs: youtubeIDs)
    }
    
    /// Filters out watched videos if hideWatchedVideos is enabled.
    private func filterWatchedVideos(_ videos: [Video]) -> [Video] {
        guard hideWatchedVideos, let dataManager else {
            return videos
        }
        
        let watchMap = dataManager.watchEntriesMap()
        return videos.filter { video in
            guard let entry = watchMap[video.id.videoID] else { return true }
            return !entry.isFinished
        }
    }
    
    /// Checks if a video is watched (finished).
    private func isVideoWatched(_ video: Video) -> Bool {
        guard let dataManager else { return false }
        let watchMap = dataManager.watchEntriesMap()
        guard let entry = watchMap[video.id.videoID] else { return false }
        return entry.isFinished
    }
}
