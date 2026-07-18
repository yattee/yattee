//
//  DeArrowBrandingProvider.swift
//  Yattee
//
//  Observable provider for DeArrow branding data with batch prefetching.
//

import Foundation

/// Provides observable access to DeArrow branding data with performance optimizations.
@MainActor
@Observable
final class DeArrowBrandingProvider {
    // MARK: - Observable State

    /// Cached titles by video ID.
    private(set) var titles: [String: String] = [:]

    /// Cached thumbnail URLs by video ID.
    private(set) var thumbnailURLs: [String: URL] = [:]

    // MARK: - Dependencies

    private let api: DeArrowAPI
    private weak var settingsManager: SettingsManager?

    // MARK: - Request Tracking

    /// Video IDs currently being fetched.
    private var inFlightRequests: Set<String> = []

    /// Video IDs that have been processed (success or failure).
    private var processedIDs: Set<String> = []

    /// Prefetch task for batch operations.
    private var prefetchTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Maximum concurrent requests during batch prefetch.
    private let maxConcurrentRequests = 5

    /// Delay between batches in milliseconds.
    private let batchDelayMs: UInt64 = 100

    // MARK: - Initialization

    init(api: DeArrowAPI) {
        self.api = api
    }

    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
        // Sync initial API URLs from settings
        Task {
            await syncAPIURLs()
        }
    }

    /// Syncs API URLs from settings to the DeArrow API.
    /// Call this when settings change.
    func syncAPIURLs() async {
        guard let settings = settingsManager else { return }

        if let apiURL = URL(string: settings.deArrowAPIURL) {
            await api.setBaseURL(apiURL)
        }

        if let thumbnailURL = URL(string: settings.deArrowThumbnailAPIURL) {
            await api.setThumbnailBaseURL(thumbnailURL)
        }
    }

    // MARK: - Public API

    /// Returns the DeArrow title for a video, if available and enabled.
    func title(for video: Video) -> String? {
        guard settingsManager?.deArrowEnabled == true,
              settingsManager?.deArrowReplaceTitles == true,
              case .global = video.id.source else {
            return nil
        }
        return titles[video.id.videoID]
    }

    /// Returns the DeArrow thumbnail URL for a video, if available and enabled.
    func thumbnailURL(for video: Video) -> URL? {
        guard settingsManager?.deArrowEnabled == true,
              settingsManager?.deArrowReplaceThumbnails == true,
              case .global = video.id.source else {
            return nil
        }
        return thumbnailURLs[video.id.videoID]
    }

    /// Fetches branding for a single video if not already processed.
    /// Only fetches for YouTube videos (global source).
    func fetchIfNeeded(for video: Video) {
        guard settingsManager?.deArrowEnabled == true,
              case .global = video.id.source else { return }
        let videoID = video.id.videoID
        guard !processedIDs.contains(videoID) && !inFlightRequests.contains(videoID) else { return }

        inFlightRequests.insert(videoID)

        Task(priority: .low) {
            await fetchBranding(for: videoID)
            inFlightRequests.remove(videoID)
            processedIDs.insert(videoID)
        }
    }

    /// Prefetches branding for multiple videos with throttling.
    /// - Parameter videoIDs: Array of YouTube video IDs to prefetch.
    func prefetch(videoIDs: [String]) {
        guard settingsManager?.deArrowEnabled == true else { return }

        // Filter out already processed or in-flight IDs
        let idsToFetch = videoIDs.filter { id in
            !processedIDs.contains(id) && !inFlightRequests.contains(id)
        }

        guard !idsToFetch.isEmpty else { return }

        // Cancel any existing prefetch task
        prefetchTask?.cancel()

        prefetchTask = Task(priority: .background) {
            await batchFetch(videoIDs: idsToFetch)
        }
    }

    /// Clears all cached data and resets state.
    func clearCache() async {
        prefetchTask?.cancel()
        prefetchTask = nil

        titles.removeAll()
        thumbnailURLs.removeAll()
        inFlightRequests.removeAll()
        processedIDs.removeAll()

        await api.clearCache()
    }

    // MARK: - Private

    private func fetchBranding(for videoID: String) async {
        // Parallel fetch: request branding and cached thumbnail simultaneously
        // This speeds up requests per DeArrow API docs recommendation
        async let brandingTask = api.branding(for: videoID)
        async let cachedThumbnailTask = api.fetchThumbnail(for: videoID, timestamp: nil)

        do {
            let branding = try await brandingTask
            let cachedThumbnail = await cachedThumbnailTask

            guard let branding else { return }

            // Store title if available
            if let title = branding.bestTitle {
                titles[videoID] = title
            }

            // Handle thumbnail with timestamp verification
            if let expectedTimestamp = branding.bestThumbnailTimestamp {
                if let serverTimestamp = cachedThumbnail.serverTimestamp,
                   cachedThumbnail.imageData != nil,
                   timestampsMatch(serverTimestamp, expectedTimestamp) {
                    // Cached thumbnail matches expected timestamp - use it
                    thumbnailURLs[videoID] = cachedThumbnail.url
                    LoggingService.shared.logPlayer("DeArrow: using cached thumbnail", details: "Video: \(videoID), timestamp: \(serverTimestamp)")
                } else {
                    // Need to fetch with correct timestamp
                    let correctThumbnail = await api.fetchThumbnail(for: videoID, timestamp: expectedTimestamp)
                    if correctThumbnail.imageData != nil {
                        thumbnailURLs[videoID] = correctThumbnail.url
                        LoggingService.shared.logPlayer("DeArrow: fetched thumbnail with timestamp", details: "Video: \(videoID), timestamp: \(expectedTimestamp)")
                    }
                }
            }
        } catch {
            // Silently fail - we don't want DeArrow errors to affect the app
            LoggingService.shared.logPlayerError("DeArrow fetch failed for \(videoID)", error: error)
        }
    }

    /// Checks if two timestamps match within a small tolerance (0.5 seconds).
    private func timestampsMatch(_ t1: Double, _ t2: Double) -> Bool {
        abs(t1 - t2) < 0.5
    }

    private func batchFetch(videoIDs: [String]) async {
        // Process in batches with concurrency limit
        let batches = videoIDs.chunked(into: maxConcurrentRequests)

        for batch in batches {
            // Check for cancellation
            if Task.isCancelled { break }

            // Mark as in-flight
            for id in batch {
                inFlightRequests.insert(id)
            }

            // Fetch batch concurrently
            await withTaskGroup(of: Void.self) { group in
                for videoID in batch {
                    group.addTask(priority: .low) { [weak self] in
                        await self?.fetchBranding(for: videoID)
                    }
                }
            }

            // Mark as processed and remove from in-flight
            for id in batch {
                inFlightRequests.remove(id)
                processedIDs.insert(id)
            }

            // Throttle between batches
            if !Task.isCancelled {
                try? await Task.sleep(nanoseconds: batchDelayMs * 1_000_000)
            }
        }
    }
}

// MARK: - Array Extension

private extension Array {
    /// Splits the array into chunks of the specified size.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
