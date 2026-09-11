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

    /// The feed error worth showing in this state, if any.
    ///
    /// While the context banner is up, only the errors it already answers for
    /// stand down — the banner names their cause, so it is the one that stays.
    /// Everything else keeps its own message and its retry: a local refresh
    /// that failed on the network is news the banner does not carry, and
    /// swallowing it leaves a stale feed with nothing to say and nothing to
    /// press.
    func displayedError(contextBannerVisible: Bool) -> FeedLoadError? {
        guard case let .error(error) = self else { return nil }
        guard !contextBannerVisible || !error.isAnsweredByContextBanner else { return nil }

        return error
    }

    /// Specific error types for feed loading.
    enum FeedLoadError: Equatable {
        case yatteeServerRequired
        case notAuthenticated
        case networkError(String)

        /// Whether a context banner, when one is up, already answers for this.
        ///
        /// A selected account that cannot be used reads local data, and the
        /// local feed then asks for the Yattee Server it has no reason to have
        /// — "add a subscriptions account in Settings" under a banner saying
        /// *this* account needs signing in again is two answers to one
        /// question. These two are the account the banner is already talking
        /// about; a refresh that failed on the way out is not, and has a retry
        /// worth offering.
        var isAnsweredByContextBanner: Bool {
            switch self {
            case .yatteeServerRequired, .notAuthenticated:
                return true
            case .networkError:
                return false
            }
        }
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

        // Ordered behind any purge already asked for, or this reads the file
        // that purge is about to delete.
        await diskClearTask?.value

        let generation = accountGeneration

        if let cacheData = await FeedCache.shared.load() {
            // The identity or the login can change while this is awaiting the
            // disk. Applying what it brings back would restore the previous
            // account's private feed on top of a cache that was deliberately
            // emptied.
            guard generation == accountGeneration else {
                LoggingService.shared.info(
                    "Discarding a disk feed that belongs to the previous login",
                    category: .general
                )
                return
            }

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
        // The Top Shelf snapshot lives in the shared app group and is read by
        // tvOS without the app running, so emptying the cache is not enough:
        // the previous login's feed would stay on the system home screen until
        // some later refresh happened to rewrite it. Written from the cleared
        // cache, so this erases it.
        TopShelfSnapshotWriter.writeFeed()
        diskClearTask = Task {
            await FeedCache.shared.clear()
        }
    }

    /// The outstanding erase of the on-disk feed.
    ///
    /// A load starting after a purge can still reach the cache actor first and
    /// bring the erased feed back — the generation it captures is already the
    /// new one, so nothing downstream can tell. Loads wait for this instead.
    private var diskClearTask: Task<Void, Never>?

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
    ///
    /// `generation` is the account this result was requested for, captured when
    /// the request started — several requests can be in flight at once, so it
    /// cannot be read from shared state at the end.
    func update(videos: [Video], generation: Int) {
        guard isCurrentAccountsResult(generation) else { return }

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
    private func appendVideos(_ newVideos: [Video], generation: Int) {
        guard isCurrentAccountsResult(generation) else { return }

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

    /// Reports what a feed request implies about the account it used.
    ///
    /// The feed talks to the same servers as the subscription providers but
    /// does not go through one, so without this a credential that expires
    /// during a feed-only refresh would keep looking signed in and the local
    /// fallback would never engage.
    private func recordOutcome(_ error: Error?, backend: AppEnvironment.FeedBackend, using appEnvironment: AppEnvironment) {
        let type: InstanceType = backend == .invidious ? .invidious : .piped
        guard let account = appEnvironment.account(forSelectedContext: type) else { return }

        appEnvironment.accountsManager.recordServerOutcome(error, for: account)
    }

    // MARK: - Account Change Handling

    /// Clears cache when subscription account changes.
    /// Call this when the user switches between local and Invidious accounts.
    func handleAccountChange() {
        LoggingService.shared.info("Subscription account changed, clearing feed cache", category: .general)
        // Anything already in flight was authenticated as the previous account.
        // Clearing does not cancel it, and signing in again keeps the same
        // account ID and context — so without this fence the old request lands
        // afterwards and writes the previous user's private feed straight back
        // into the cache, and onto disk.
        accountGeneration += 1
        clear()
        feedLoadState = .idle
        // The request that was running belongs to the previous account and its
        // result is now fenced out, so it must not go on blocking the
        // replacement — the new account would sit on an empty feed until
        // something else asked for a refresh.
        isLoading = false
    }

    /// Fences whatever is in flight and lets a replacement start, keeping the
    /// feed that is already here.
    ///
    /// For a move between the selected account and local data that the user did
    /// not make — an unreachable server, an instance switched off. The
    /// selection has not changed, so what is cached is still that account's own
    /// feed and it is the only thing standing between the banner and an empty
    /// screen. Purging it is what left the feed with nothing to fall back to
    /// and no way to reach a terminal state: the request it emptied the cache
    /// for is the one that cannot answer.
    func handleEffectiveContextChange() {
        LoggingService.shared.info("Subscription reads moved, keeping the cached feed", category: .general)
        accountGeneration += 1
        cancelPolling()
        feedLoadState = .idle
        isLoading = false
    }

    /// Which login the cache currently holds data for.
    private var accountGeneration = 0

    /// The account a request starting now belongs to. Carried by the request
    /// itself: switching accounts mid-flight starts a replacement while the
    /// first one is still running.
    private func beginRequest() -> Int {
        accountGeneration
    }

    private func isCurrentAccountsResult(_ generation: Int) -> Bool {
        guard generation == accountGeneration else {
            LoggingService.shared.info(
                "Discarding a feed result that belongs to the previous login",
                category: .general
            )
            return false
        }
        return true
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

        let generation = beginRequest()

        // The *effective* context, so an account still waiting on its instance
        // or credential falls back to local rather than reporting
        // notAuthenticated while the subscriptions list already shows local data.
        let context = appEnvironment.dataContextValidator.effectiveContext
        let backend = appEnvironment.feedBackend(for: context)
        LoggingService.shared.debug("Starting feed refresh for \(backend)", category: .general)

        // Use a detached task to prevent SwiftUI from cancelling the request
        // when @State properties change during the refresh operation.
        // This is necessary because loadSubscriptionsAsync() updates @State
        // before feedCache.refresh() completes, which can cause SwiftUI to
        // cancel the parent task.
        await Task.detached { @MainActor in
            switch backend {
            case .local:
                await self.refreshLocalAccount(using: appEnvironment, generation: generation)
            case .invidious:
                await self.refreshInvidiousAccount(using: appEnvironment, generation: generation)
            case .piped:
                await self.refreshPipedAccount(using: appEnvironment, generation: generation)
            }
        }.value
    }

    /// Refreshes feed for local account using Yattee Server.
    private func refreshLocalAccount(using appEnvironment: AppEnvironment, generation: Int) async {
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
        await refreshFromStatelessServer(instance: serverInstance, using: appEnvironment, generation: generation)
    }

    /// Refreshes feed for Invidious account using authenticated feed endpoint.
    private func refreshInvidiousAccount(using appEnvironment: AppEnvironment, generation: Int) async {
        guard let (instance, sid) = getInvidiousAuth(using: appEnvironment) else {
            LoggingService.shared.warning("Invidious account not authenticated", category: .general)
            feedLoadState = .error(.notAuthenticated)
            isLoading = false
            return
        }

        LoggingService.shared.info("Refreshing feed using Invidious account: \(instance.url.absoluteString)", category: .general)
        
        // Reset pagination for fresh refresh
        currentPage = 1
        
        await refreshFromInvidiousFeed(instance: instance, sid: sid, using: appEnvironment, generation: generation)
    }

    /// Gets the authenticated Invidious instance and session ID.
    ///
    /// Resolved through the selected account and nothing else: a second login on
    /// the same instance has its own credential, and the instance-keyed lookup
    /// this used to fall back to cannot tell the two apart.
    private func getInvidiousAuth(using appEnvironment: AppEnvironment) -> (Instance, String)? {
        guard let account = appEnvironment.account(forSelectedContext: .invidious),
              let instance = appEnvironment.accountsManager.instance(for: account),
              let sid = appEnvironment.accountCredentialsManager(for: account)?.credential(for: account) else {
            LoggingService.shared.debug("No Invidious account resolved for the selected context", category: .general)
            return nil
        }

        return (instance, sid)
    }

    // MARK: - Piped Account

    /// Refreshes feed for Piped account using authenticated feed endpoint.
    private func refreshPipedAccount(using appEnvironment: AppEnvironment, generation: Int) async {
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
            let feedVideos = try await appEnvironment.contentService.feed(
                for: instance,
                credential: authToken
            )
            guard isCurrentAccountsResult(generation) else { return }

            LoggingService.shared.info("Piped feed: Received \(feedVideos.count) videos", category: .general)
            recordOutcome(nil, backend: .piped, using: appEnvironment)

            update(videos: feedVideos, generation: generation)
            appEnvironment.dataManager.updateLastVideoPublishedDates(from: feedVideos)
            prefetchDeArrow(for: feedVideos, using: appEnvironment)
            feedLoadState = .ready
        } catch {
            LoggingService.shared.error("Failed to fetch Piped feed: \(error.localizedDescription)", category: .general)
            guard isCurrentAccountsResult(generation) else { return }
            recordOutcome(error, backend: .piped, using: appEnvironment)
            feedLoadState = .error(.networkError(error.localizedDescription))
        }

        isLoading = false
    }

    /// Gets the authenticated Piped instance and auth token.
    private func getPipedAuth(using appEnvironment: AppEnvironment) -> (Instance, String)? {
        guard let account = appEnvironment.account(forSelectedContext: .piped),
              let instance = appEnvironment.accountsManager.instance(for: account),
              let token = appEnvironment.accountCredentialsManager(for: account)?.credential(for: account) else {
            LoggingService.shared.debug("No Piped account resolved for the selected context", category: .general)
            return nil
        }

        return (instance, token)
    }

    // MARK: - Invidious Feed

    /// Refreshes feed from authenticated Invidious feed API.
    private func refreshFromInvidiousFeed(
        instance: Instance,
        sid: String,
        using appEnvironment: AppEnvironment,
        generation: Int
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

            guard isCurrentAccountsResult(generation) else { return }

            let feedVideos = response.videos
            LoggingService.shared.info(
                "Invidious feed: Received \(feedVideos.count) videos (page \(currentPage))",
                category: .general
            )
            recordOutcome(nil, backend: .invidious, using: appEnvironment)

            // For first page, replace all videos. For subsequent pages, this shouldn't be called.
            update(videos: feedVideos, generation: generation)
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
            guard isCurrentAccountsResult(generation) else { return }
            recordOutcome(error, backend: .invidious, using: appEnvironment)
            feedLoadState = .error(.networkError(error.localizedDescription))
        }

        isLoading = false
    }

    /// Loads the next page of Invidious feed (for infinite scroll).
    func loadMoreInvidiousFeed(using appEnvironment: AppEnvironment) async {
        guard !isLoading else { return }
        guard hasMorePages else { return }
        guard appEnvironment.feedBackend(for: appEnvironment.dataContextValidator.effectiveContext) == .invidious
        else { return }

        guard let (instance, sid) = getInvidiousAuth(using: appEnvironment) else {
            return
        }

        let generation = beginRequest()
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

            guard isCurrentAccountsResult(generation) else { return }

            let feedVideos = response.videos
            LoggingService.shared.info(
                "Invidious feed: Loaded page \(nextPage), received \(feedVideos.count) videos",
                category: .general
            )

            // Append new videos to existing cache
            appendVideos(feedVideos, generation: generation)

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
    private func refreshFromStatelessServer(instance: Instance, using appEnvironment: AppEnvironment, generation: Int) async {
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

            guard isCurrentAccountsResult(generation) else { return }

            let serverVideos = response.toVideos()
            LoggingService.shared.info(
                "refreshFromStatelessServer: Received \(serverVideos.count) videos from server, status: \(response.status), ready: \(response.isReady)",
                category: .general
            )
            update(videos: serverVideos, generation: generation)
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
                        appEnvironment: appEnvironment,
                        generation: generation
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
        appEnvironment: AppEnvironment,
        generation: Int
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
                        update(videos: serverVideos, generation: generation)
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
