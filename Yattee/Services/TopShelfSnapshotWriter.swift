//
//  TopShelfSnapshotWriter.swift
//  Yattee
//
//  Builds Top Shelf snapshots from app data and persists them to the App Group
//  UserDefaults suite so the tvOS Top Shelf extension can read them without
//  touching SwiftData. No-op on non-tvOS platforms.
//

import Foundation
import SwiftData

@MainActor
enum TopShelfSnapshotWriter {
    #if os(tvOS)
    private static var observers: [NSObjectProtocol] = []
    #endif

    /// Re-writes all three snapshot sections from current app data.
    /// Call on app launch, after bookmark/watch mutations, and after feed refresh.
    static func writeAll(dataManager: DataManager?, settingsManager: SettingsManager? = nil) {
        #if os(tvOS)
        writeContinueWatching(dataManager: dataManager)
        writeBookmarks(dataManager: dataManager)
        writeFeed()
        if let settingsManager {
            settingsManager.mirrorEnabledSectionsToAppGroup(settingsManager.topShelfSections)
        }
        #endif
    }

    /// Registers NotificationCenter observers so bookmark/history changes
    /// elsewhere in the app keep the snapshot in sync. Idempotent.
    static func startObserving(dataManager: DataManager?) {
        #if os(tvOS)
        guard observers.isEmpty, let dataManager else { return }
        let center = NotificationCenter.default
        let boxed = WeakDataManagerBox(dataManager)
        observers.append(center.addObserver(
            forName: .bookmarksDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in writeBookmarks(dataManager: boxed.value) }
        })
        observers.append(center.addObserver(
            forName: .watchHistoryDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in writeContinueWatching(dataManager: boxed.value) }
        })
        #endif
    }

    static func writeContinueWatching(dataManager: DataManager?) {
        #if os(tvOS)
        guard let dataManager else { return }
        let history = dataManager.watchHistory(limit: 50)
        let items = history
            .filter { !$0.isFinished && $0.watchedSeconds > 10 }
            .prefix(TopShelfSnapshot.maxItems)
            .compactMap(Self.makeItem(from:))
        TopShelfSnapshot.write(Array(items), section: .continueWatching)
        #endif
    }

    static func writeBookmarks(dataManager: DataManager?) {
        #if os(tvOS)
        guard let dataManager else { return }
        let bookmarks = dataManager.bookmarks(limit: TopShelfSnapshot.maxItems)
        let items = bookmarks.compactMap(Self.makeItem(from:))
        TopShelfSnapshot.write(items, section: .recentBookmarks)
        #endif
    }

    static func writeFeed() {
        #if os(tvOS)
        let videos = SubscriptionFeedCache.shared.videos.prefix(TopShelfSnapshot.maxItems)
        let items = videos.compactMap(Self.makeItem(from:))
        TopShelfSnapshot.write(items, section: .recentFeed)
        #endif
    }
}

#if os(tvOS)
/// Wraps a weak DataManager reference so it can be captured in Sendable closures.
/// Access is confined to the main actor via the enclosing NotificationCenter queue.
private final class WeakDataManagerBox: @unchecked Sendable {
    weak var value: DataManager?
    init(_ value: DataManager?) { self.value = value }
}

private extension TopShelfSnapshotWriter {
    static func makeItem(from bookmark: Bookmark) -> TopShelfItem? {
        guard let deepLink = deepLinkURL(
            videoID: bookmark.videoID,
            sourceRawValue: bookmark.sourceRawValue,
            globalProvider: bookmark.globalProvider,
            instanceURLString: bookmark.instanceURLString
        ) else { return nil }
        return TopShelfItem(
            videoID: bookmark.videoID,
            title: bookmark.title,
            authorName: bookmark.authorName,
            duration: bookmark.duration,
            thumbnailURL: bookmark.thumbnailURLString,
            deepLinkURL: deepLink,
            progressSeconds: nil
        )
    }

    static func makeItem(from entry: WatchEntry) -> TopShelfItem? {
        guard let deepLink = deepLinkURL(
            videoID: entry.videoID,
            sourceRawValue: entry.sourceRawValue,
            globalProvider: entry.globalProvider,
            instanceURLString: entry.instanceURLString
        ) else { return nil }
        return TopShelfItem(
            videoID: entry.videoID,
            title: entry.title,
            authorName: entry.authorName,
            duration: entry.duration,
            thumbnailURL: entry.thumbnailURLString,
            deepLinkURL: deepLink,
            progressSeconds: entry.watchedSeconds
        )
    }

    static func makeItem(from video: Video) -> TopShelfItem? {
        guard let deepLink = deepLinkURL(for: video.id) else { return nil }
        let thumbnail = bestThumbnailURL(from: video.thumbnails)
        return TopShelfItem(
            videoID: video.id.videoID,
            title: video.title,
            authorName: video.author.name,
            duration: video.duration,
            thumbnailURL: thumbnail,
            deepLinkURL: deepLink,
            progressSeconds: nil
        )
    }

    /// Builds a `yattee://video/...` deep link from a Video's ID.
    /// Returns nil for source types not round-trippable via the URL scheme (e.g. extracted).
    static func deepLinkURL(for videoID: VideoID) -> String? {
        switch videoID.source {
        case .global:
            return "yattee://video/\(videoID.videoID)"
        case .federated(_, let instance):
            var components = URLComponents()
            components.scheme = "yattee"
            components.host = "video"
            components.path = "/\(videoID.videoID)"
            components.queryItems = [
                URLQueryItem(name: "source", value: "peertube"),
                URLQueryItem(name: "instance", value: instance.absoluteString)
            ]
            return components.url?.absoluteString
        case .extracted:
            return nil
        }
    }

    /// Builds a deep link from the stored Bookmark/WatchEntry source fields.
    static func deepLinkURL(
        videoID: String,
        sourceRawValue: String,
        globalProvider: String?,
        instanceURLString: String?
    ) -> String? {
        switch sourceRawValue {
        case "global":
            // Only YouTube survives the round-trip; other global providers fall through.
            return "yattee://video/\(videoID)"
        case "federated":
            guard globalProvider == "peertube",
                  let urlStr = instanceURLString,
                  let instanceURL = URL(string: urlStr) else {
                return nil
            }
            var components = URLComponents()
            components.scheme = "yattee"
            components.host = "video"
            components.path = "/\(videoID)"
            components.queryItems = [
                URLQueryItem(name: "source", value: "peertube"),
                URLQueryItem(name: "instance", value: instanceURL.absoluteString)
            ]
            return components.url?.absoluteString
        default:
            return nil
        }
    }

    static func bestThumbnailURL(from thumbnails: [Thumbnail]) -> String? {
        thumbnails.max(by: { $0.quality < $1.quality })?.url.absoluteString
    }
}
#endif
