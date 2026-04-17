//
//  SubscriptionFeedCache.swift
//  Yattee
//
//  Subscription feed cache with disk persistence.
//  Routes feed fetching based on subscription account type.
//

import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// State of feed loading.
enum FeedLoadState: Equatable {
    case idle
    case loading
    case loadingMore
    case ready
    case partiallyLoaded(readyCount: Int, pendingCount: Int, errorCount: Int)
    case error(FeedLoadError)

    /// Specific error types for feed loading.
    enum FeedLoadError: Equatable {
        case yatteeServerRequired
        case notAuthenticated
        case networkError(String)
    }
}

/// Subscription feed cache with disk persistence.
/// Routes feed fetching based on the selected subscription account type:
/// - Local accounts: Use Yattee Server (required)
/// - Invidious accounts: Use Invidious /api/v1/auth/feed endpoint
@MainActor
@Observable
final class SubscriptionFeedCache {
    static let shared = SubscriptionFeedCache()

    var videos: [Video] = []
    var lastUpdated: Date?
    var isLoading = false
    var loadingProgress: (loaded: Int, total: Int)?
    var hasLoadedOnce = false

    /// State of feed loading.
    var feedLoadState: FeedLoadState = .idle

    /// Whether more pages are available from Invidious feed (for infinite scroll).
    var hasMorePages = false

    /// Whether the disk cache has been loaded.
    private var diskCacheLoaded = false

    /// Current page for Invidious feed pagination (1-based).
    private var currentPage = 1

    /// Active polling task for feed status (can be cancelled).
    private var pollingTask: Task<Void, Never>?

    /// Whether app is in foreground (polling only allowed in foreground).
    private var isAppInForeground = true

    private init() {
        setupLifecycleObservers()
    }

    // MARK: - Lifecycle

    /// Sets up observers to detect when app goes to background.
    private func setupLifecycleObservers() {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.handleAppBackgrounded()
            }
        }
        #elseif os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.handleAppBackgrounded()
            }
        }
        #endif
    }

    /// Handles app going to background - cancels any active polling.
    private func handleAppBackgrounded() {
        isAppInForeground = false
        cancelPolling()
    }

    /// Cancels any active feed status polling.
    func cancelPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Cache Validity

    /// Returns true if the cache is valid based on the configured validity duration.
    /// Uses the setting from SettingsManager (default 30 minutes).
    func isCacheValid(using settingsManager: SettingsManager?) -> Bool {
        guard let lastUpdated, !videos.isEmpty else { return false }
        let validitySeconds = settingsManager?.feedCacheValiditySeconds
            ?? TimeInterval(SettingsManager.defaultFeedCacheValidityMinutes * 60)
        return Date().timeIntervalSince(lastUpdated) < validitySeconds
    }

    // MARK: - Disk Cache

    /// Loads cached data from disk if not already loaded.
    /// Call this early (e.g., on app launch) to populate the feed quickly.
    func loadFromDiskIfNeeded() async {
        guard !diskCacheLoaded else {
            LoggingService.shared.debug("Feed cache already loaded from disk, skipping", category: .general)
            return
        }
        diskCacheLoaded = true

        if let cacheData = await FeedCache.shared.load() {
            videos = cacheData.videos
            lastUpdated = cacheData.lastUpdated
            hasLoadedOnce = true
            let videoCount = videos.count
            let oldestVideoDate = videos.compactMap { $0.publishedAt }.min()
            let age = Date().timeIntervalSince(cacheData.lastUpdated)
            LoggingService.shared.debug(
                "Loaded feed cache from disk: \(videoCount) videos, lastUpdated: \(cacheData.lastUpdated) (\(Int(age))s ago), oldest video: \(oldestVideoDate?.description ?? "none")",
                category: .general
            )
        } else {
            LoggingService.shared.debug("No feed cache found on disk", category: .general)
        }
    }

    func clear() {
        cancelPolling()
        videos = []
        lastUpdated = nil
        hasMorePages = false
        currentPage = 1
        Task {
            await FeedCache.shared.clear()
        }
    }

    func invalidate() {
        lastUpdated = nil
        Task {
            await FeedCache.shared.invalidate()
        }
    }

    /// Saves the current feed state to disk.
    private func saveToDisk() {
        guard let lastUpdated else {
            LoggingService.shared.warning("saveToDisk called but lastUpdated is nil", category: .general)
            return
        }
        LoggingService.shared.debug("Saving feed cache to disk: \(videos.count) videos, lastUpdated: \(lastUpdated)", category: .general)
        Task {
            await FeedCache.shared.save(videos: videos, lastUpdated: lastUpdated)
        }
    }

    /// Updates the cache with new videos and persists to disk.
    func update(videos: [Video]) {
        let oldCount = self.videos.count
        let oldDate = self.lastUpdated
        self.videos = videos
        self.lastUpdated = Date()
        self.hasLoadedOnce = true
        LoggingService.shared.info(
            "Feed cache updated: \(oldCount) -> \(videos.count) videos, lastUpdated changed from \(oldDate?.description ?? "nil") to \(Date())",
            category: .general
        )
        saveToDisk()
        TopShelfSnapshotWriter.writeFeed()
    }

    /// Appends videos to the existing cache (for pagination).
    private func appendVideos(_ newVideos: [Video]) {
        let existingIDs = Set(videos.map { $0.id })
        let uniqueNewVideos = newVideos.filter { !existingIDs.contains($0.id) }
        videos.append(contentsOf: uniqueNewVideos)
        lastUpdated = Date()
        LoggingService.shared.debug(
            "Appended \(uniqueNewVideos.count) videos to feed cache (total: \(videos.count))",
            category: .general
        )
        saveToDisk()
    }

    // MARK: - Account Change Handling

    /// Clears cache when subscription account changes.
    /// Call this when the user switches between local and Invidious accounts.
    func handleAccountChange() {
        LoggingService.shared.info("Subscription account changed, clearing feed cache", category: .general)
        clear()
        feedLoadState = .idle
    }

    // MARK: - Refresh

    /// Refreshes the feed from network.
    /// Routes based on subscription account type:
    /// - Local: Requires Yattee Server
    /// - Invidious: Uses authenticated feed endpoint
    ///
    /// Note: This method uses a detached task internally to prevent SwiftUI from
    /// cancelling the network request when view state changes during refresh.
    func refresh(using appEnvironment: AppEnvironment) async {
        guard !isLoading else {
            LoggingService.shared.debug("Feed refresh called but already loading, skipping", category: .general)
            return
        }

        let accountType = appEnvironment.settingsManager.subscriptionAccount.type
        LoggingService.shared.debug("Starting feed refresh for account type: \(accountType)", category: .general)

        // Use a detached task to prevent SwiftUI from cancelling the request
        // when @State properties change during the refresh operation.
        // This is necessary because loadSubscriptionsAsync() updates @State
        // before feedCache.refresh() completes, which can cause SwiftUI to
        // cancel the parent task.
        await Task.detached { @MainActor in
            switch accountType {
            case .local:
                await self.refreshLocalAccount(using: appEnvironment)
            case .invidious:
                await self.refreshInvidiousAccount(using: appEnvironment)
            case .piped:
                await self.refreshPipedAccount(using: appEnvironment)
            }
        }.value
    }

    /// Refreshes feed for local account using Yattee Server.
    private func refreshLocalAccount(using appEnvironment: AppEnvironment) async {
        // Require Yattee Server for local accounts
        guard let serverInstance = appEnvironment.instancesManager.instances.first(where: {
            $0.type == .yatteeServer && $0.isEnabled
        }) else {
            LoggingService.shared.warning("Local subscriptions require Yattee Server, but none is configured", category: .general)
            feedLoadState = .error(.yatteeServerRequired)
            isLoading = false
            return
        }

        LoggingService.shared.info("Refreshing feed using Yattee Server: \(serverInstance.url.absoluteString)", category: .general)
        await refreshFromStatelessServer(instance: serverInstance, using: appEnvironment)
    }

    /// Refreshes feed for Invidious account using authenticated feed endpoint.
    private func refreshInvidiousAccount(using appEnvironment: AppEnvironment) async {
        guard let (instance, sid) = getInvidiousAuth(using: appEnvironment) else {
            LoggingService.shared.warning("Invidious account not authenticated", category: .general)
            feedLoadState = .error(.notAuthenticated)
            isLoading = false
            return
        }

        LoggingService.shared.info("Refreshing feed using Invidious account: \(instance.url.absoluteString)", category: .general)
        
        // Reset pagination for fresh refresh
        currentPage = 1
        
        await refreshFromInvidiousFeed(instance: instance, sid: sid, using: appEnvironment)
    }

    /// Gets the authenticated Invidious instance and session ID.
    private func getInvidiousAuth(using appEnvironment: AppEnvironment) -> (Instance, String)? {
        // Get the instance ID from subscription account settings
        let account = appEnvironment.settingsManager.subscriptionAccount
        
        let instance: Instance?
        if let instanceID = account.instanceID {
            // Use the specific instance from account settings
            instance = appEnvironment.instancesManager.instances.first { $0.id == instanceID }
        } else {
            // Fall back to first enabled Invidious instance
            instance = appEnvironment.instancesManager.instances.first {
                $0.type == .invidious && $0.isEnabled
            }
        }
        
        guard let instance else {
            LoggingService.shared.debug("No Invidious instance found for subscription account", category: .general)
            return nil
        }
        
        guard let sid = appEnvironment.invidiousCredentialsManager.sid(for: instance) else {
            LoggingService.shared.debug("No session ID found for Invidious instance: \(instance.id)", category: .general)
            return nil
        }
        
        return (instance, sid)
    }

    // MARK: - Piped Account

    /// Refreshes feed for Piped account using authenticated feed endpoint.
    private func refreshPipedAccount(using appEnvironment: AppEnvironment) async {
        guard let (instance, authToken) = getPipedAuth(using: appEnvironment) else {
            LoggingService.shared.warning("Piped account not authenticated", category: .general)
            feedLoadState = .error(.notAuthenticated)
            isLoading = false
            return
        }

        LoggingService.shared.info("Refreshing feed using Piped account: \(instance.url.absoluteString)", category: .general)

        isLoading = true
        feedLoadState = .loading
        loadingProgress = nil
        hasMorePages = false // Piped doesn't support pagination

        do {
            let pipedAPI = PipedAPI(httpClient: appEnvironment.httpClient)
            let feedVideos = try await pipedAPI.feed(instance: instance, authToken: authToken)

            LoggingService.shared.info("Piped feed: Received \(feedVideos.count) videos", category: .general)

            update(videos: feedVideos)
            appEnvironment.dataManager.updateLastVideoPublishedDates(from: feedVideos)
            prefetchDeArrow(for: feedVideos, using: appEnvironment)
            feedLoadState = .ready
        } catch {
            LoggingService.shared.error("Failed to fetch Piped feed: \(error.localizedDescription)", category: .general)
            feedLoadState = .error(.networkError(error.localizedDescription))
        }

        isLoading = false
    }

    /// Gets the authenticated Piped instance and auth token.
    private func getPipedAuth(using appEnvironment: AppEnvironment) -> (Instance, String)? {
        let account = appEnvironment.settingsManager.subscriptionAccount

        guard let instanceID = account.instanceID,
              let instance = appEnvironment.instancesManager.instances.first(where: { $0.id == instanceID }),
              let authToken = appEnvironment.pipedCredentialsManager.credential(for: instance) else {
            LoggingService.shared.debug("No authenticated Piped instance found for subscription account", category: .general)
            return nil
        }

        return (instance, authToken)
    }

    // MARK: - Invidious Feed

    /// Refreshes feed from authenticated Invidious feed API.
    private func refreshFromInvidiousFeed(
        instance: Instance,
        sid: String,
        using appEnvironment: AppEnvironment
    ) async {
        isLoading = true
        feedLoadState = .loading
        loadingProgress = nil

        do {
            let response = try await appEnvironment.invidiousAPI.feed(
                instance: instance,
                sid: sid,
                page: currentPage,
                maxResults: 50
            )

            let feedVideos = response.videos
            LoggingService.shared.info(
                "Invidious feed: Received \(feedVideos.count) videos (page \(currentPage))",
                category: .general
            )

            // For first page, replace all videos. For subsequent pages, this shouldn't be called.
            update(videos: feedVideos)
            appEnvironment.dataManager.updateLastVideoPublishedDates(from: feedVideos)

            // Update pagination state
            hasMorePages = response.hasMore
            currentPage = 1

            // Prefetch DeArrow branding for YouTube videos
            prefetchDeArrow(for: feedVideos, using: appEnvironment)

            feedLoadState = .ready
        } catch {
            LoggingService.shared.error(
                "Failed to fetch Invidious feed: \(error.localizedDescription)",
                category: .general
            )
            feedLoadState = .error(.networkError(error.localizedDescription))
        }

        isLoading = false
    }

    /// Loads the next page of Invidious feed (for infinite scroll).
    func loadMoreInvidiousFeed(using appEnvironment: AppEnvironment) async {
        guard !isLoading else { return }
        guard hasMorePages else { return }
        guard appEnvironment.settingsManager.subscriptionAccount.type == .invidious else { return }

        guard let (instance, sid) = getInvidiousAuth(using: appEnvironment) else {
            return
        }

        isLoading = true
        feedLoadState = .loadingMore

        let nextPage = currentPage + 1

        do {
            let response = try await appEnvironment.invidiousAPI.feed(
                instance: instance,
                sid: sid,
                page: nextPage,
                maxResults: 50
            )

            let feedVideos = response.videos
            LoggingService.shared.info(
                "Invidious feed: Loaded page \(nextPage), received \(feedVideos.count) videos",
                category: .general
            )

            // Append new videos to existing cache
            appendVideos(feedVideos)

            // Update pagination state
            hasMorePages = response.hasMore
            currentPage = nextPage

            // Prefetch DeArrow branding for new videos
            prefetchDeArrow(for: feedVideos, using: appEnvironment)

            feedLoadState = .ready
        } catch {
            LoggingService.shared.error(
                "Failed to load more Invidious feed: \(error.localizedDescription)",
                category: .general
            )
            // Don't show error state for pagination failures, just stop loading
            feedLoadState = .ready
        }

        isLoading = false
    }

    // MARK: - Yattee Server Feed

    /// Refreshes feed from Yattee Server's stateless POST feed API.
    private func refreshFromStatelessServer(instance: Instance, using appEnvironment: AppEnvironment) async {
        let subscriptions = appEnvironment.dataManager.subscriptions()
        LoggingService.shared.debug("refreshFromStatelessServer: Found \(subscriptions.count) subscriptions", category: .general)
        guard !subscriptions.isEmpty else {
            videos = []
            isLoading = false
            hasLoadedOnce = true
            feedLoadState = .ready
            LoggingService.shared.debug("refreshFromStatelessServer: No subscriptions, clearing feed", category: .general)
            return
        }

        isLoading = true
        feedLoadState = .loading
        loadingProgress = nil

        let channelRequests = subscriptions.map { subscription in
            StatelessChannelRequest(
                channelId: subscription.channelID,
                site: subscription.site,
                channelName: subscription.name,
                channelUrl: subscription.channelURLString,
                avatarUrl: subscription.avatarURLString
            )
        }

        do {
            let httpClient = HTTPClient()
            if let authHeader = appEnvironment.basicAuthCredentialsManager.basicAuthHeader(for: instance) {
                await httpClient.setDefaultHeaders(["Authorization": authHeader])
            }
            let yatteeServerAPI = YatteeServerAPI(httpClient: httpClient)
            LoggingService.shared.debug("refreshFromStatelessServer: Calling postFeed for \(channelRequests.count) channels", category: .general)
            let response = try await yatteeServerAPI.postFeed(
                channels: channelRequests,
                limit: 100,
                offset: 0,
                instance: instance
            )

            let serverVideos = response.toVideos()
            LoggingService.shared.info(
                "refreshFromStatelessServer: Received \(serverVideos.count) videos from server, status: \(response.status), ready: \(response.isReady)",
                category: .general
            )
            update(videos: serverVideos)
            appEnvironment.dataManager.updateLastVideoPublishedDates(from: serverVideos)

            // Prefetch DeArrow branding
            prefetchDeArrow(for: serverVideos, using: appEnvironment)

            if response.isReady {
                feedLoadState = .ready
                isLoading = false
            } else {
                // Show partial results and poll for completion
                feedLoadState = .partiallyLoaded(
                    readyCount: response.readyCount ?? 0,
                    pendingCount: response.pendingCount ?? 0,
                    errorCount: response.errorCount ?? 0
                )
                // Reset foreground flag since this is a user-initiated action
                isAppInForeground = true
                pollingTask = Task {
                    await pollUntilReady(
                        channels: channelRequests,
                        instance: instance,
                        appEnvironment: appEnvironment
                    )
                }
                await pollingTask?.value
                pollingTask = nil
            }
        } catch {
            LoggingService.shared.error(
                "Yattee Server feed failed: \(error.localizedDescription)",
                category: .general
            )
            feedLoadState = .error(.networkError(error.localizedDescription))
            isLoading = false
        }
    }

    /// Polls server until all channels are cached, then refreshes.
    /// Stops polling after max retries, consecutive errors, or when app is backgrounded.
    private func pollUntilReady(
        channels: [StatelessChannelRequest],
        instance: Instance,
        appEnvironment: AppEnvironment
    ) async {
        let statusChannels = channels.map {
            StatelessChannelStatusRequest(channelId: $0.channelId, site: $0.site)
        }
        let httpClient = HTTPClient()
        if let authHeader = appEnvironment.basicAuthCredentialsManager.basicAuthHeader(for: instance) {
            await httpClient.setDefaultHeaders(["Authorization": authHeader])
        }
        let yatteeServerAPI = YatteeServerAPI(httpClient: httpClient)

        let maxRetries = 5
        var retryCount = 0
        let maxConsecutiveErrors = 3
        var consecutiveErrors = 0

        while retryCount < maxRetries {
            // Check for cancellation before sleep
            guard !Task.isCancelled else {
                LoggingService.shared.debug("Feed status polling cancelled", category: .general)
                break
            }

            // Check if app is still in foreground
            guard isAppInForeground else {
                LoggingService.shared.debug("Feed status polling stopped - app backgrounded", category: .general)
                break
            }

            try? await Task.sleep(for: .seconds(5))

            // Check again after sleep
            guard !Task.isCancelled, isAppInForeground else {
                LoggingService.shared.debug("Feed status polling cancelled during sleep", category: .general)
                break
            }

            retryCount += 1

            do {
                let status = try await yatteeServerAPI.postFeedStatus(
                    channels: statusChannels,
                    instance: instance
                )
                consecutiveErrors = 0 // Reset on success

                if status.isReady {
                    // Fetch full feed now that all channels are cached
                    if let response = try? await yatteeServerAPI.postFeed(
                        channels: channels,
                        limit: 100,
                        offset: 0,
                        instance: instance
                    ) {
                        let serverVideos = response.toVideos()
                        update(videos: serverVideos)
                        appEnvironment.dataManager.updateLastVideoPublishedDates(from: serverVideos)
                        prefetchDeArrow(for: serverVideos, using: appEnvironment)
                    }
                    feedLoadState = .ready
                    isLoading = false
                    return
                }

                // Update progress UI
                feedLoadState = .partiallyLoaded(
                    readyCount: status.readyCount,
                    pendingCount: status.pendingCount,
                    errorCount: status.errorCount
                )
            } catch {
                consecutiveErrors += 1
                LoggingService.shared.debug(
                    "Feed status poll error (\(consecutiveErrors)/\(maxConsecutiveErrors)): \(error.localizedDescription)",
                    category: .general
                )

                if consecutiveErrors >= maxConsecutiveErrors {
                    LoggingService.shared.warning(
                        "Feed status polling stopped after \(maxConsecutiveErrors) consecutive errors",
                        category: .general
                    )
                    break
                }
            }
        }

        if retryCount >= maxRetries {
            LoggingService.shared.warning(
                "Feed status polling timed out after \(retryCount) attempts",
                category: .general
            )
        }

        // Show whatever we have
        feedLoadState = .ready
        isLoading = false
    }

    // MARK: - Cache Warming

    /// Warms the cache if expired.
    func warmIfNeeded(using appEnvironment: AppEnvironment) {
        guard !isLoading else { return }

        Task { @MainActor in
            // Load disk cache first to get accurate lastUpdated timestamp
            await loadFromDiskIfNeeded()

            guard !isCacheValid(using: appEnvironment.settingsManager) else { return }

            // Use the same routing logic as refresh()
            await refresh(using: appEnvironment)
        }
    }

    // MARK: - Helpers

    /// Prefetches DeArrow branding for YouTube videos.
    private func prefetchDeArrow(for videos: [Video], using appEnvironment: AppEnvironment) {
        let youtubeIDs = videos.compactMap { video -> String? in
            if case .global = video.id.source { return video.id.videoID }
            return nil
        }
        appEnvironment.deArrowBrandingProvider.prefetch(videoIDs: youtubeIDs)
    }
}
