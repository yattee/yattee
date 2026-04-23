//
//  BackgroundFeedRefresher.swift
//  Yattee
//
//  Core background feed refresh logic for notifications.
//

import Foundation

/// Performs background feed refresh and detects new videos for notifications.
/// Only fetches videos from channels with notifications enabled.
@MainActor
final class BackgroundFeedRefresher {
    // MARK: - Dependencies

    private weak var appEnvironment: AppEnvironment?
    private let notificationManager: NotificationManager

    // MARK: - Initialization

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    func setAppEnvironment(_ environment: AppEnvironment) {
        self.appEnvironment = environment
    }

    // MARK: - Refresh Logic

    /// Performs background refresh and sends notifications for new videos.
    /// Routes to appropriate refresh method based on subscription account type.
    func performBackgroundRefresh() async {
        guard let appEnvironment else {
            LoggingService.shared.warning("Background refresh skipped: no app environment", category: .notifications)
            return
        }

        guard appEnvironment.settingsManager.backgroundNotificationsEnabled else {
            LoggingService.shared.debug("Background refresh disabled in settings", category: .notifications)
            return
        }

        // Route based on subscription account type
        switch appEnvironment.settingsManager.subscriptionAccount.type {
        case .local:
            await performLocalAccountRefresh()
        case .invidious:
            await performInvidiousAccountRefresh()
        case .piped:
            await performPipedAccountRefresh()
        }
    }

    // MARK: - Local Account Refresh

    /// Performs background refresh for local (Yattee/iCloud) subscription account.
    /// Requires Yattee Server - uses stateless feed endpoint for efficient single-request fetching.
    private func performLocalAccountRefresh() async {
        guard let appEnvironment else { return }

        // Require Yattee Server for local account background refresh
        guard let yatteeServer = appEnvironment.instancesManager.instances
            .first(where: { $0.type == .yatteeServer && $0.isEnabled }) else {
            LoggingService.shared.debug("Background refresh requires Yattee Server for local subscriptions", category: .notifications)
            return
        }

        let lastCheckDate = appEnvironment.settingsManager.lastBackgroundCheck ?? Date.distantPast

        // Get channel IDs with notifications enabled from ChannelNotificationSettings
        let notifiableChannelIDs = Set(appEnvironment.dataManager.channelIDsWithNotificationsEnabled())

        // Filter subscriptions to only those with notifications enabled
        let notifiableSubscriptions = appEnvironment.dataManager.subscriptions().filter {
            notifiableChannelIDs.contains($0.channelID)
        }

        LoggingService.shared.info(
            "Background refresh starting (local account) | lastBackgroundCheck: \(lastCheckDate) | channels with notifications: \(notifiableSubscriptions.count)",
            category: .notifications
        )

        guard !notifiableSubscriptions.isEmpty else {
            LoggingService.shared.debug("No subscriptions with notifications enabled", category: .notifications)
            appEnvironment.settingsManager.lastBackgroundCheck = Date()
            return
        }

        LoggingService.shared.debug("Fetching feed from Yattee Server: \(yatteeServer.url)", category: .notifications)

        // Convert subscriptions to channel requests
        let channelRequests = notifiableSubscriptions.map { subscription in
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
            if let authHeader = appEnvironment.basicAuthCredentialsManager.basicAuthHeader(for: yatteeServer) {
                await httpClient.setDefaultHeaders(["Authorization": authHeader])
            }
            let yatteeServerAPI = YatteeServerAPI(httpClient: httpClient)
            let response = try await yatteeServerAPI.postFeed(
                channels: channelRequests,
                limit: 5 * notifiableSubscriptions.count,
                offset: 0,
                instance: yatteeServer
            )

            LoggingService.shared.debug("API returned \(response.videos.count) total videos", category: .notifications)

            // Load last notified video IDs per channel for deduplication
            let lastNotified = appEnvironment.settingsManager.lastNotifiedVideoPerChannel

            // Filter to new videos - don't wait for ready, use whatever is available
            var dateFilteredCount = 0
            var dedupedCount = 0
            let newVideos: [(video: Video, channelName: String)] = response.videos.compactMap { serverVideo in
                guard let video = serverVideo.toVideo(),
                      let publishedAt = video.publishedAt,
                      publishedAt > lastCheckDate,
                      publishedAt <= Date() else {
                    return nil
                }
                dateFilteredCount += 1
                // Skip if this is the last video we notified about for this channel
                if lastNotified[video.author.id] == video.id.videoID {
                    dedupedCount += 1
                    return nil
                }
                return (video: video, channelName: serverVideo.author)
            }

            LoggingService.shared.debug(
                "After date filter: \(dateFilteredCount) videos newer than \(lastCheckDate)",
                category: .notifications
            )
            LoggingService.shared.debug(
                "After deduplication: \(newVideos.count) videos (removed \(dedupedCount) already-notified)",
                category: .notifications
            )

            // Update last notified video per channel (store newest video ID for each channel)
            var updatedLastNotified = lastNotified
            for (video, _) in newVideos {
                updatedLastNotified[video.author.id] = video.id.videoID
            }
            appEnvironment.settingsManager.lastNotifiedVideoPerChannel = updatedLastNotified

            // Update timestamp before sending notification
            appEnvironment.settingsManager.lastBackgroundCheck = Date()

            await sendNotificationsIfNeeded(newVideos: newVideos)
        } catch {
            LoggingService.shared.logNotificationError("Background refresh failed (local account)", error: error)
        }
    }

    // MARK: - Invidious Account Refresh

    /// Performs background refresh for Invidious subscription account.
    /// Fetches the full Invidious feed and filters to channels with notifications enabled.
    private func performInvidiousAccountRefresh() async {
        guard let appEnvironment else { return }

        // Require authenticated Invidious instance
        guard let invidiousInstance = appEnvironment.instancesManager.instances
            .first(where: { $0.type == .invidious && $0.isEnabled }),
              let sid = appEnvironment.invidiousCredentialsManager.sid(for: invidiousInstance) else {
            LoggingService.shared.debug("Background refresh requires authenticated Invidious instance", category: .notifications)
            return
        }

        let lastCheckDate = appEnvironment.settingsManager.lastBackgroundCheck ?? Date.distantPast

        // Get channel IDs with notifications enabled from ChannelNotificationSettings
        let notifiableChannelIDs = Set(appEnvironment.dataManager.channelIDsWithNotificationsEnabled())

        LoggingService.shared.info(
            "Background refresh starting (Invidious account) | lastBackgroundCheck: \(lastCheckDate) | channels with notifications: \(notifiableChannelIDs.count)",
            category: .notifications
        )

        guard !notifiableChannelIDs.isEmpty else {
            LoggingService.shared.debug("No channels with notifications enabled", category: .notifications)
            appEnvironment.settingsManager.lastBackgroundCheck = Date()
            return
        }

        LoggingService.shared.debug("Fetching feed from Invidious: \(invidiousInstance.url)", category: .notifications)

        do {
            // Fetch the Invidious feed - fetch enough to cover recent videos from notifiable channels
            // Use a reasonable limit since we're filtering client-side
            let feedResponse = try await appEnvironment.invidiousAPI.feed(
                instance: invidiousInstance,
                sid: sid,
                page: 1,
                maxResults: 100
            )

            LoggingService.shared.debug("API returned \(feedResponse.videos.count) total videos", category: .notifications)

            // Load last notified video IDs per channel for deduplication
            let lastNotified = appEnvironment.settingsManager.lastNotifiedVideoPerChannel

            // Filter to new videos from notifiable channels
            var channelFilteredCount = 0
            var dateFilteredCount = 0
            var dedupedCount = 0
            let newVideos: [(video: Video, channelName: String)] = feedResponse.videos.compactMap { video in
                // Only include videos from channels with notifications enabled
                guard notifiableChannelIDs.contains(video.author.id) else {
                    return nil
                }
                channelFilteredCount += 1

                // Only include videos published after last check and not in the future
                guard let publishedAt = video.publishedAt,
                      publishedAt > lastCheckDate,
                      publishedAt <= Date() else {
                    return nil
                }
                dateFilteredCount += 1

                // Skip if this is the last video we notified about for this channel
                if lastNotified[video.author.id] == video.id.videoID {
                    dedupedCount += 1
                    return nil
                }

                return (video: video, channelName: video.author.name)
            }

            LoggingService.shared.debug(
                "After channel filter: \(channelFilteredCount) videos from notifiable channels",
                category: .notifications
            )
            LoggingService.shared.debug(
                "After date filter: \(dateFilteredCount) videos newer than \(lastCheckDate)",
                category: .notifications
            )
            LoggingService.shared.debug(
                "After deduplication: \(newVideos.count) videos (removed \(dedupedCount) already-notified)",
                category: .notifications
            )

            // Update last notified video per channel (store newest video ID for each channel)
            var updatedLastNotified = lastNotified
            for (video, _) in newVideos {
                updatedLastNotified[video.author.id] = video.id.videoID
            }
            appEnvironment.settingsManager.lastNotifiedVideoPerChannel = updatedLastNotified

            // Update timestamp before sending notification
            appEnvironment.settingsManager.lastBackgroundCheck = Date()

            await sendNotificationsIfNeeded(newVideos: newVideos)
        } catch {
            LoggingService.shared.logNotificationError("Background refresh failed (Invidious account)", error: error)
        }
    }

    // MARK: - Piped Account Refresh

    /// Performs background refresh for Piped subscription account.
    /// Fetches the Piped feed and filters to channels with notifications enabled.
    private func performPipedAccountRefresh() async {
        guard let appEnvironment else { return }

        // Get the instance ID from subscription account settings
        let account = appEnvironment.settingsManager.subscriptionAccount
        guard let instanceID = account.instanceID,
              let pipedInstance = appEnvironment.instancesManager.instances.first(where: { $0.id == instanceID }),
              let authToken = appEnvironment.pipedCredentialsManager.credential(for: pipedInstance) else {
            LoggingService.shared.debug("Background refresh requires authenticated Piped instance", category: .notifications)
            return
        }

        let lastCheckDate = appEnvironment.settingsManager.lastBackgroundCheck ?? Date.distantPast

        // Get channel IDs with notifications enabled from ChannelNotificationSettings
        let notifiableChannelIDs = Set(appEnvironment.dataManager.channelIDsWithNotificationsEnabled())

        LoggingService.shared.info(
            "Background refresh starting (Piped account) | lastBackgroundCheck: \(lastCheckDate) | channels with notifications: \(notifiableChannelIDs.count)",
            category: .notifications
        )

        guard !notifiableChannelIDs.isEmpty else {
            LoggingService.shared.debug("No channels with notifications enabled", category: .notifications)
            appEnvironment.settingsManager.lastBackgroundCheck = Date()
            return
        }

        LoggingService.shared.debug("Fetching feed from Piped: \(pipedInstance.url)", category: .notifications)

        do {
            // Fetch the Piped feed
            let pipedAPI = PipedAPI(httpClient: appEnvironment.httpClient)
            let feedVideos = try await pipedAPI.feed(instance: pipedInstance, authToken: authToken)

            LoggingService.shared.debug("API returned \(feedVideos.count) total videos", category: .notifications)

            // Load last notified video IDs per channel for deduplication
            let lastNotified = appEnvironment.settingsManager.lastNotifiedVideoPerChannel

            // Filter to new videos from notifiable channels
            var channelFilteredCount = 0
            var dateFilteredCount = 0
            var dedupedCount = 0
            let newVideos: [(video: Video, channelName: String)] = feedVideos.compactMap { video in
                // Only include videos from channels with notifications enabled
                guard notifiableChannelIDs.contains(video.author.id) else {
                    return nil
                }
                channelFilteredCount += 1

                // Only include videos published after last check and not in the future
                guard let publishedAt = video.publishedAt,
                      publishedAt > lastCheckDate,
                      publishedAt <= Date() else {
                    return nil
                }
                dateFilteredCount += 1

                // Skip if this is the last video we notified about for this channel
                if lastNotified[video.author.id] == video.id.videoID {
                    dedupedCount += 1
                    return nil
                }

                return (video: video, channelName: video.author.name)
            }

            LoggingService.shared.debug(
                "After channel filter: \(channelFilteredCount) videos from notifiable channels",
                category: .notifications
            )
            LoggingService.shared.debug(
                "After date filter: \(dateFilteredCount) videos newer than \(lastCheckDate)",
                category: .notifications
            )
            LoggingService.shared.debug(
                "After deduplication: \(newVideos.count) videos (removed \(dedupedCount) already-notified)",
                category: .notifications
            )

            // Update last notified video per channel (store newest video ID for each channel)
            var updatedLastNotified = lastNotified
            for (video, _) in newVideos {
                updatedLastNotified[video.author.id] = video.id.videoID
            }
            appEnvironment.settingsManager.lastNotifiedVideoPerChannel = updatedLastNotified

            // Update timestamp before sending notification
            appEnvironment.settingsManager.lastBackgroundCheck = Date()

            await sendNotificationsIfNeeded(newVideos: newVideos)
        } catch {
            LoggingService.shared.logNotificationError("Background refresh failed (Piped account)", error: error)
        }
    }

    // MARK: - Notification Sending

    /// Sends notifications for new videos if any were found.
    /// Filters out videos the user has already started or finished watching.
    /// - Parameter newVideos: Array of new videos with their channel names
    private func sendNotificationsIfNeeded(newVideos: [(video: Video, channelName: String)]) async {
        #if !os(tvOS)
        guard !newVideos.isEmpty else {
            LoggingService.shared.debug("No new videos found", category: .notifications)
            return
        }

        var videosToNotify = newVideos

        // Filter out upcoming/premiere videos that haven't aired yet
        let upcomingCount = videosToNotify.count
        videosToNotify = videosToNotify.filter { !$0.video.isUpcoming }
        if upcomingCount - videosToNotify.count > 0 {
            LoggingService.shared.debug(
                "Filtered \(upcomingCount - videosToNotify.count) upcoming/premiere videos from notifications",
                category: .notifications
            )
        }

        // Filter out videos the user has already started or finished watching
        if let appEnvironment {
            let watchEntries = appEnvironment.dataManager.watchEntriesMap()
            let originalCount = videosToNotify.count

            videosToNotify = videosToNotify.filter { item in
                guard let entry = watchEntries[item.video.id.videoID] else {
                    // No watch entry - video hasn't been watched, include it
                    return true
                }
                // Skip if user has started watching (any progress) or finished
                return entry.watchedSeconds <= 0 && !entry.isFinished
            }

            let filteredCount = originalCount - videosToNotify.count
            if filteredCount > 0 {
                LoggingService.shared.debug(
                    "Filtered \(filteredCount) watched/started videos from notifications",
                    category: .notifications
                )
            }
        }

        if !videosToNotify.isEmpty {
            await notificationManager.sendNotification(for: videosToNotify)
            LoggingService.shared.info(
                "Background refresh complete | Found \(videosToNotify.count) new videos from \(Set(videosToNotify.map(\.channelName)).count) channels | Notification sent: true",
                category: .notifications
            )
        } else {
            LoggingService.shared.info(
                "Background refresh complete | Found 0 new videos | Notification sent: false",
                category: .notifications
            )
        }
        #endif
    }
}
