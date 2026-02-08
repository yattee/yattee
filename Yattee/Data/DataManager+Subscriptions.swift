//
//  DataManager+Subscriptions.swift
//  Yattee
//
//  Subscription operations for DataManager.
//

import Foundation
import SwiftData

extension DataManager {
    // MARK: - Subscriptions

    /// Subscribes to a channel.
    /// - Parameter channel: The channel to subscribe to.
    func subscribe(to channel: Channel) {
        let channelID = channel.id.channelID
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            guard existing.isEmpty else {
                return
            }

            let subscription = Subscription.from(channel: channel)
            modelContext.insert(subscription)
            save()
            
            // Queue for CloudKit sync
            cloudKitSync?.queueSubscriptionSave(subscription)
            
            let change = SubscriptionChange(addedSubscriptions: [subscription], removedChannelIDs: [])
            NotificationCenter.default.post(
                name: .subscriptionsDidChange,
                object: nil,
                userInfo: [SubscriptionChange.userInfoKey: change]
            )
        } catch {
            LoggingService.shared.logCloudKitError("Failed to subscribe", error: error)
        }
    }

    /// Subscribes to a channel from an Author.
    /// - Parameters:
    ///   - author: The author/channel to subscribe to.
    ///   - source: The content source (YouTube or PeerTube).
    func subscribe(to author: Author, source: ContentSource) {
        let channelID = author.id
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            guard existing.isEmpty else {
                return
            }

            let sourceRaw: String
            var instanceURL: String?

            switch source {
            case .global:
                sourceRaw = "global"
            case .federated(_, let instance):
                sourceRaw = "federated"
                instanceURL = instance.absoluteString
            case .extracted:
                // Extracted sources don't support subscriptions
                return
            }

            let subscription = Subscription(
                channelID: channelID,
                sourceRawValue: sourceRaw,
                instanceURLString: instanceURL,
                name: author.name,
                subscriberCount: author.subscriberCount,
                avatarURLString: author.thumbnailURL?.absoluteString
            )
            modelContext.insert(subscription)
            save()
            
            // Queue for CloudKit sync
            cloudKitSync?.queueSubscriptionSave(subscription)
            
            let change = SubscriptionChange(addedSubscriptions: [subscription], removedChannelIDs: [])
            NotificationCenter.default.post(
                name: .subscriptionsDidChange,
                object: nil,
                userInfo: [SubscriptionChange.userInfoKey: change]
            )
        } catch {
            LoggingService.shared.logCloudKitError("Failed to subscribe", error: error)
        }
    }

    /// Unsubscribes from a channel.
    func unsubscribe(from channelID: String) {
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let subscriptions = try modelContext.fetch(descriptor)
            guard !subscriptions.isEmpty else { return }

            // Capture scopes before deleting
            let scopes = subscriptions.map {
                SourceScope.from(
                    sourceRawValue: $0.sourceRawValue,
                    globalProvider: $0.providerName,
                    instanceURLString: $0.instanceURLString,
                    externalExtractor: nil
                )
            }

            subscriptions.forEach { modelContext.delete($0) }
            save()

            // Queue scoped CloudKit deletions
            for scope in scopes {
                cloudKitSync?.queueSubscriptionDelete(channelID: channelID, scope: scope)
            }

            let change = SubscriptionChange(addedSubscriptions: [], removedChannelIDs: [channelID])
            NotificationCenter.default.post(
                name: .subscriptionsDidChange,
                object: nil,
                userInfo: [SubscriptionChange.userInfoKey: change]
            )
        } catch {
            LoggingService.shared.logCloudKitError("Failed to unsubscribe", error: error)
        }
    }

    /// Bulk adds subscriptions from channel data (for testing).
    func bulkAddSubscriptions(_ channels: [(id: String, name: String)]) {
        var addedCount = 0

        for channel in channels {
            let channelID = channel.id
            let descriptor = FetchDescriptor<Subscription>(
                predicate: #Predicate { $0.channelID == channelID }
            )

            do {
                let existing = try modelContext.fetch(descriptor)
                guard existing.isEmpty else {
                    continue
                }

                let subscription = Subscription(
                    channelID: channel.id,
                    sourceRawValue: "youtube",
                    instanceURLString: nil,
                    name: channel.name
                )
                modelContext.insert(subscription)
                addedCount += 1
            } catch {
                continue
            }
        }

        if addedCount > 0 {
            save()
            SubscriptionFeedCache.shared.invalidate()
            LoggingService.shared.info("Bulk added \(addedCount) subscriptions", category: .general)
        }
    }

    /// Checks if subscribed to a channel.
    func isSubscribed(to channelID: String) -> Bool {
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let count = try modelContext.fetchCount(descriptor)
            return count > 0
        } catch {
            return false
        }
    }

    /// Gets a subscription by channel ID.
    func subscription(for channelID: String) -> Subscription? {
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            return nil
        }
    }

    /// Gets all subscriptions.
    func subscriptions() -> [Subscription] {
        let descriptor = FetchDescriptor<Subscription>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch subscriptions", error: error)
            return []
        }
    }



    /// Inserts a subscription into the database.
    /// Used by SubscriptionService for caching server subscriptions locally.
    func insertSubscription(_ subscription: Subscription) {
        // Check for duplicates
        let channelID = subscription.channelID
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            if existing.isEmpty {
                modelContext.insert(subscription)
                save()
            }
        } catch {
            // Insert anyway if we can't check
            modelContext.insert(subscription)
            save()
        }
    }

    /// Deletes a subscription from the database.
    /// Used by SubscriptionService for removing stale cached subscriptions.
    func deleteSubscription(_ subscription: Subscription) {
        modelContext.delete(subscription)
        // Note: caller is responsible for calling save() after batch operations
    }

    /// Removes subscriptions matching the given channel IDs.
    func removeSubscriptions(matching channelIDs: Set<String>) {
        let allSubscriptions = subscriptions()
        var removedCount = 0
        var deleteInfo: [(channelID: String, scope: SourceScope)] = []

        for subscription in allSubscriptions {
            if channelIDs.contains(subscription.channelID) {
                // Capture scope before deleting
                let scope = SourceScope.from(
                    sourceRawValue: subscription.sourceRawValue,
                    globalProvider: subscription.providerName,
                    instanceURLString: subscription.instanceURLString,
                    externalExtractor: nil
                )
                deleteInfo.append((subscription.channelID, scope))
                modelContext.delete(subscription)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            save()

            // Queue CloudKit deletions
            for info in deleteInfo {
                cloudKitSync?.queueSubscriptionDelete(channelID: info.channelID, scope: info.scope)
            }

            SubscriptionFeedCache.shared.invalidate()
            LoggingService.shared.info("Removed \(removedCount) test subscriptions", category: .general)
        }
    }

    /// Returns the total count of subscriptions.
    var subscriptionCount: Int {
        let descriptor = FetchDescriptor<Subscription>()
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            return 0
        }
    }

    /// Returns all subscriptions.
    var allSubscriptions: [Subscription] {
        subscriptions()
    }

    /// Updates lastVideoPublishedAt for subscriptions based on feed videos.
    func updateLastVideoPublishedDates(from videos: [Video]) {
        var latestByChannel: [String: Date] = [:]
        for video in videos {
            guard let publishedAt = video.publishedAt else { continue }
            let channelID = video.author.id
            if let existing = latestByChannel[channelID] {
                if publishedAt > existing { latestByChannel[channelID] = publishedAt }
            } else {
                latestByChannel[channelID] = publishedAt
            }
        }

        guard !latestByChannel.isEmpty else { return }

        let allSubscriptions = subscriptions()
        var updated = false
        for subscription in allSubscriptions {
            if let latestDate = latestByChannel[subscription.channelID],
               subscription.lastVideoPublishedAt == nil || latestDate > subscription.lastVideoPublishedAt! {
                subscription.lastVideoPublishedAt = latestDate
                updated = true
            }
        }
        if updated {
            save()
            NotificationCenter.default.post(name: .subscriptionsDidChange, object: nil)
        }
    }

    /// Imports subscriptions from external sources (YouTube CSV, OPML).
    /// Skips existing subscriptions and returns import statistics.
    /// - Parameter channels: Array of tuples containing channel ID and name
    /// - Returns: Tuple with count of imported and skipped subscriptions
    func importSubscriptionsFromExternal(_ channels: [(channelID: String, name: String)]) -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        var addedSubscriptions: [Subscription] = []

        for channel in channels {
            // Skip if already subscribed
            if isSubscribed(to: channel.channelID) {
                skipped += 1
                continue
            }

            // Create new subscription
            let subscription = Subscription(
                channelID: channel.channelID,
                sourceRawValue: "global",
                instanceURLString: nil,
                name: channel.name
            )
            subscription.providerName = ContentSource.youtubeProvider

            modelContext.insert(subscription)
            addedSubscriptions.append(subscription)
            imported += 1
        }

        if imported > 0 {
            save()
            SubscriptionFeedCache.shared.invalidate()

            // Queue imported subscriptions for CloudKit sync
            for subscription in addedSubscriptions {
                cloudKitSync?.queueSubscriptionSave(subscription)
            }

            // Post notification for UI updates
            let change = SubscriptionChange(addedSubscriptions: addedSubscriptions, removedChannelIDs: [])
            NotificationCenter.default.post(
                name: .subscriptionsDidChange,
                object: nil,
                userInfo: [SubscriptionChange.userInfoKey: change]
            )

            LoggingService.shared.info("Imported \(imported) subscriptions from external source", category: .general)
        }

        return (imported, skipped)
    }

    /// Updates subscription metadata from fresh channel data.
    func updateSubscription(for channelID: String, with channel: Channel) {
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            let subscriptions = try modelContext.fetch(descriptor)
            if let subscription = subscriptions.first {
                subscription.update(from: channel)
                save()
            }
        } catch {
            LoggingService.shared.logCloudKitError("Failed to update subscription", error: error)
        }
    }
}
