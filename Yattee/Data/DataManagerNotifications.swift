//
//  DataManagerNotifications.swift
//  Yattee
//
//  Notification definitions for data changes.
//

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when subscriptions are modified (subscribe or unsubscribe).
    static let subscriptionsDidChange = Notification.Name("subscriptionsDidChange")
    /// Posted when bookmarks are modified (add or remove).
    static let bookmarksDidChange = Notification.Name("bookmarksDidChange")
    /// Posted when watch history is modified (add, update, or remove).
    static let watchHistoryDidChange = Notification.Name("watchHistoryDidChange")
    /// Posted when playlists are modified (create, update, or delete).
    static let playlistsDidChange = Notification.Name("playlistsDidChange")
    /// Posted when media sources are modified (add, update, or delete).
    static let mediaSourcesDidChange = Notification.Name("mediaSourcesDidChange")
    /// Posted when search history is modified (add or delete).
    static let searchHistoryDidChange = Notification.Name("searchHistoryDidChange")
    /// Posted when recent channels are modified (add or delete).
    static let recentChannelsDidChange = Notification.Name("recentChannelsDidChange")
    /// Posted when recent playlists are modified (add or delete).
    static let recentPlaylistsDidChange = Notification.Name("recentPlaylistsDidChange")
    /// Posted when video details (likes, views, etc.) are loaded or updated.
    static let videoDetailsDidLoad = Notification.Name("videoDetailsDidLoad")
    /// Posted when sidebar settings (max channels, sort order, etc.) are modified.
    static let sidebarSettingsDidChange = Notification.Name("sidebarSettingsDidChange")
}

// MARK: - Subscription Change

/// Describes what changed in subscriptions for incremental feed updates.
struct SubscriptionChange {
    let addedSubscriptions: [Subscription]
    let removedChannelIDs: [String]

    static let userInfoKey = "subscriptionChange"

    var isEmpty: Bool {
        addedSubscriptions.isEmpty && removedChannelIDs.isEmpty
    }
}
