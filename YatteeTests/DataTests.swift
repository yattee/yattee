//
//  DataTests.swift
//  YatteeTests
//
//  Tests for the local data persistence layer.
//

import Testing
import Foundation
@testable import Yattee

@MainActor
@Suite("Data Layer Tests")
struct DataTests {

    // MARK: - Watch Entry Tests

    @Suite("Watch Entry")
    struct WatchEntryTests {
        @Test("Progress calculation")
        @MainActor
        func progressCalculation() {
            let entry = WatchEntry(
                videoID: "test123",
                sourceRawValue: "youtube",
                title: "Test Video",
                authorName: "Test Channel",
                authorID: "channel123",
                duration: 600, // 10 minutes
                watchedSeconds: 300 // 5 minutes
            )

            #expect(entry.progress == 0.5)
        }

        @Test("Auto-finish at 90%")
        @MainActor
        func autoFinishAt90Percent() {
            let entry = WatchEntry(
                videoID: "test123",
                sourceRawValue: "youtube",
                title: "Test Video",
                authorName: "Test Channel",
                authorID: "channel123",
                duration: 100
            )

            #expect(!entry.isFinished)

            entry.updateProgress(seconds: 90)

            #expect(entry.isFinished)
            #expect(entry.progress >= 0.9)
        }

        @Test("Reset progress")
        @MainActor
        func resetProgress() {
            let entry = WatchEntry(
                videoID: "test123",
                sourceRawValue: "youtube",
                title: "Test Video",
                authorName: "Test Channel",
                authorID: "channel123",
                duration: 100,
                watchedSeconds: 90,
                isFinished: true
            )

            entry.resetProgress()

            #expect(entry.watchedSeconds == 0)
            #expect(!entry.isFinished)
        }

        @Test("Content source YouTube")
        @MainActor
        func contentSourceYouTube() {
            let entry = WatchEntry(
                videoID: "abc123",
                sourceRawValue: "global",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            if case .global = entry.contentSource {
                // Expected
            } else {
                Issue.record("Expected global source")
            }
        }

        @Test("Content source Federated")
        @MainActor
        func contentSourceFederated() {
            let entry = WatchEntry(
                videoID: "uuid123",
                sourceRawValue: "federated",
                instanceURLString: "https://peertube.example.com",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            if case .federated(_, let instance) = entry.contentSource {
                #expect(instance.host == "peertube.example.com")
            } else {
                Issue.record("Expected federated source")
            }
        }

        @Test("Remaining time formatting")
        @MainActor
        func remainingTimeFormatting() {
            let entry = WatchEntry(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 600, // 10 minutes
                watchedSeconds: 300 // 5 minutes watched
            )

            // 5 minutes remaining = "5:00"
            #expect(entry.remainingTime == "5:00")
        }

        @Test("Remaining time with seconds")
        @MainActor
        func remainingTimeWithSeconds() {
            let entry = WatchEntry(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 125, // 2:05
                watchedSeconds: 60 // 1 minute watched
            )

            // 65 seconds remaining = "1:05"
            #expect(entry.remainingTime == "1:05")
        }

        @Test("Thumbnail URL conversion")
        @MainActor
        func thumbnailURL() {
            let entry = WatchEntry(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100,
                thumbnailURLString: "https://example.com/thumb.jpg"
            )

            #expect(entry.thumbnailURL?.absoluteString == "https://example.com/thumb.jpg")
        }

        @Test("Thumbnail URL nil for invalid string")
        @MainActor
        func thumbnailURLNil() {
            let entry = WatchEntry(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100,
                thumbnailURLString: nil
            )

            #expect(entry.thumbnailURL == nil)
        }

        @Test("Mark as finished")
        @MainActor
        func markAsFinished() {
            let entry = WatchEntry(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            #expect(!entry.isFinished)
            entry.markAsFinished()
            #expect(entry.isFinished)
        }
    }

    // MARK: - Bookmark Tests

    @Suite("Bookmark")
    struct BookmarkTests {
        @Test("Formatted duration hours")
        @MainActor
        func formattedDurationHours() {
            let bookmark = Bookmark(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Long Video",
                authorName: "Channel",
                authorID: "ch1",
                duration: 3661 // 1:01:01
            )

            #expect(bookmark.formattedDuration == "1:01:01")
        }

        @Test("Formatted duration minutes")
        @MainActor
        func formattedDurationMinutes() {
            let bookmark = Bookmark(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Short Video",
                authorName: "Channel",
                authorID: "ch1",
                duration: 125 // 2:05
            )

            #expect(bookmark.formattedDuration == "2:05")
        }

        @Test("Live shows LIVE")
        @MainActor
        func liveShowsLive() {
            let bookmark = Bookmark(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Live Stream",
                authorName: "Channel",
                authorID: "ch1",
                duration: 0,
                isLive: true
            )

            #expect(bookmark.formattedDuration == "LIVE")
        }

        @Test("Content source Global")
        @MainActor
        func contentSourceGlobal() {
            let bookmark = Bookmark(
                videoID: "abc123",
                sourceRawValue: "global",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            if case .global = bookmark.contentSource {
                // Expected
            } else {
                Issue.record("Expected global source")
            }
        }

        @Test("Content source Federated")
        @MainActor
        func contentSourceFederated() {
            let bookmark = Bookmark(
                videoID: "uuid123",
                sourceRawValue: "federated",
                instanceURLString: "https://peertube.example.com",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            if case .federated(_, let instance) = bookmark.contentSource {
                #expect(instance.host == "peertube.example.com")
            } else {
                Issue.record("Expected federated source")
            }
        }

        @Test("Thumbnail URL conversion")
        @MainActor
        func thumbnailURL() {
            let bookmark = Bookmark(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100,
                thumbnailURLString: "https://example.com/thumb.jpg"
            )

            #expect(bookmark.thumbnailURL?.absoluteString == "https://example.com/thumb.jpg")
        }

        @Test("Zero duration shows empty string")
        @MainActor
        func zeroDuration() {
            let bookmark = Bookmark(
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 0,
                isLive: false
            )

            #expect(bookmark.formattedDuration == "")
        }
    }

    // MARK: - Local Playlist Tests

    @Suite("Local Playlist")
    struct LocalPlaylistTests {
        @Test("Video count")
        @MainActor
        func videoCount() {
            let playlist = LocalPlaylist(title: "My Playlist")

            #expect(playlist.videoCount == 0)
        }

        @Test("Total duration formatting")
        @MainActor
        func totalDurationFormatting() {
            let playlist = LocalPlaylist(title: "My Playlist")

            // Empty playlist
            #expect(playlist.formattedTotalDuration == "0 min")
        }

        @Test("Total duration with hours")
        @MainActor
        func totalDurationWithHours() {
            let playlist = LocalPlaylist(title: "Long Playlist")

            let item = LocalPlaylistItem(
                sortOrder: 0,
                videoID: "video1",
                sourceRawValue: "youtube",
                title: "Long Video",
                authorName: "Channel",
                authorID: "ch1",
                duration: 7200 // 2 hours
            )
            item.playlist = playlist
            playlist.items?.append(item)

            #expect(playlist.formattedTotalDuration == "2h 0m")
        }

        @Test("Contains video check")
        @MainActor
        func containsVideoCheck() {
            let playlist = LocalPlaylist(title: "Test")

            let item = LocalPlaylistItem(
                sortOrder: 0,
                videoID: "abc123",
                sourceRawValue: "youtube",
                title: "Video",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )
            item.playlist = playlist
            playlist.items?.append(item)

            #expect(playlist.contains(videoID: "abc123"))
            #expect(!playlist.contains(videoID: "xyz789"))
        }

        @Test("Sorted items by order")
        @MainActor
        func sortedItems() {
            let playlist = LocalPlaylist(title: "Test")

            // Add items out of order
            let item2 = LocalPlaylistItem(
                sortOrder: 2,
                videoID: "video2",
                sourceRawValue: "youtube",
                title: "Second",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )
            let item1 = LocalPlaylistItem(
                sortOrder: 1,
                videoID: "video1",
                sourceRawValue: "youtube",
                title: "First",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )
            let item3 = LocalPlaylistItem(
                sortOrder: 3,
                videoID: "video3",
                sourceRawValue: "youtube",
                title: "Third",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            item1.playlist = playlist
            item2.playlist = playlist
            item3.playlist = playlist
            playlist.items?.append(item2)
            playlist.items?.append(item1)
            playlist.items?.append(item3)

            let sorted = playlist.sortedItems
            #expect(sorted.count == 3)
            #expect(sorted[0].videoID == "video1")
            #expect(sorted[1].videoID == "video2")
            #expect(sorted[2].videoID == "video3")
        }

        @Test("Thumbnail URL from first sorted item")
        @MainActor
        func thumbnailURL() {
            let playlist = LocalPlaylist(title: "Test")

            let item1 = LocalPlaylistItem(
                sortOrder: 1,
                videoID: "video1",
                sourceRawValue: "youtube",
                title: "First",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100,
                thumbnailURLString: "https://example.com/thumb1.jpg"
            )
            let item2 = LocalPlaylistItem(
                sortOrder: 0,
                videoID: "video2",
                sourceRawValue: "youtube",
                title: "Actually First",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100,
                thumbnailURLString: "https://example.com/thumb2.jpg"
            )

            item1.playlist = playlist
            item2.playlist = playlist
            playlist.items?.append(item1)
            playlist.items?.append(item2)

            // Should get thumbnail from item with lowest sortOrder
            #expect(playlist.thumbnailURL?.absoluteString == "https://example.com/thumb2.jpg")
        }

        @Test("Items is optional for CloudKit compatibility")
        @MainActor
        func itemsOptional() {
            let playlist = LocalPlaylist(title: "Empty")
            // items should be initialized as empty array, not nil
            #expect(playlist.items != nil)
            #expect(playlist.items?.isEmpty == true)
        }
    }

    // MARK: - Subscription Tests

    @Suite("Subscription")
    struct SubscriptionTests {
        @Test("Formatted subscriber count")
        @MainActor
        func formattedSubscriberCount() {
            let sub = Subscription(
                channelID: "ch123",
                sourceRawValue: "youtube",
                name: "Popular Channel",
                subscriberCount: 1_500_000
            )

            #expect(sub.formattedSubscriberCount == "1.5M")
        }

        @Test("No subscriber count")
        @MainActor
        func noSubscriberCount() {
            let sub = Subscription(
                channelID: "ch123",
                sourceRawValue: "youtube",
                name: "New Channel"
            )

            #expect(sub.formattedSubscriberCount == nil)
        }

        @Test("Content source Global")
        @MainActor
        func contentSourceGlobal() {
            let sub = Subscription(
                channelID: "ch123",
                sourceRawValue: "global",
                name: "Channel"
            )

            if case .global = sub.contentSource {
                // Expected
            } else {
                Issue.record("Expected global source")
            }
        }

        @Test("Content source Federated")
        @MainActor
        func contentSourceFederated() {
            let sub = Subscription(
                channelID: "ch123",
                sourceRawValue: "federated",
                instanceURLString: "https://peertube.example.com",
                name: "Channel"
            )

            if case .federated(_, let instance) = sub.contentSource {
                #expect(instance.host == "peertube.example.com")
            } else {
                Issue.record("Expected federated source")
            }
        }

        @Test("Avatar URL conversion")
        @MainActor
        func avatarURL() {
            let sub = Subscription(
                channelID: "ch123",
                sourceRawValue: "youtube",
                name: "Channel",
                avatarURLString: "https://example.com/avatar.jpg"
            )

            #expect(sub.avatarURL?.absoluteString == "https://example.com/avatar.jpg")
        }

        @Test("Banner URL conversion")
        @MainActor
        func bannerURL() {
            let sub = Subscription(
                channelID: "ch123",
                sourceRawValue: "youtube",
                name: "Channel",
                bannerURLString: "https://example.com/banner.jpg"
            )

            #expect(sub.bannerURL?.absoluteString == "https://example.com/banner.jpg")
        }

        @Test("Update from channel")
        @MainActor
        func updateFromChannel() {
            let sub = Subscription(
                channelID: "ch123",
                sourceRawValue: "youtube",
                name: "Old Name",
                subscriberCount: 1000
            )

            let channel = Channel(
                id: .global("ch123"),
                name: "New Name",
                description: "Updated description",
                subscriberCount: 2000,
                thumbnailURL: URL(string: "https://example.com/new-avatar.jpg"),
                bannerURL: URL(string: "https://example.com/new-banner.jpg"),
                isVerified: true
            )

            sub.update(from: channel)

            #expect(sub.name == "New Name")
            #expect(sub.channelDescription == "Updated description")
            #expect(sub.subscriberCount == 2000)
            #expect(sub.avatarURLString == "https://example.com/new-avatar.jpg")
            #expect(sub.bannerURLString == "https://example.com/new-banner.jpg")
            #expect(sub.isVerified == true)
        }
    }

    // MARK: - LocalPlaylistItem Tests

    @Suite("LocalPlaylistItem")
    struct LocalPlaylistItemTests {
        @Test("Content source Global")
        @MainActor
        func contentSourceGlobal() {
            let item = LocalPlaylistItem(
                sortOrder: 0,
                videoID: "abc123",
                sourceRawValue: "global",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            if case .global = item.contentSource {
                // Expected
            } else {
                Issue.record("Expected global source")
            }
        }

        @Test("Content source Federated")
        @MainActor
        func contentSourceFederated() {
            let item = LocalPlaylistItem(
                sortOrder: 0,
                videoID: "uuid123",
                sourceRawValue: "federated",
                instanceURLString: "https://peertube.example.com",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            if case .federated(_, let instance) = item.contentSource {
                #expect(instance.host == "peertube.example.com")
            } else {
                Issue.record("Expected federated source")
            }
        }

        @Test("Thumbnail URL conversion")
        @MainActor
        func thumbnailURL() {
            let item = LocalPlaylistItem(
                sortOrder: 0,
                videoID: "abc123",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100,
                thumbnailURLString: "https://example.com/thumb.jpg"
            )

            #expect(item.thumbnailURL?.absoluteString == "https://example.com/thumb.jpg")
        }

        @Test("Default values for CloudKit compatibility")
        @MainActor
        func defaultValues() {
            let item = LocalPlaylistItem(
                sortOrder: 0,
                videoID: "test",
                sourceRawValue: "youtube",
                title: "Test",
                authorName: "Channel",
                authorID: "ch1",
                duration: 100
            )

            // Check default values are set
            #expect(item.isLive == false)
            #expect(item.thumbnailURLString == nil)
            #expect(item.instanceURLString == nil)
            #expect(item.peertubeUUID == nil)
        }
    }

    // MARK: - DataManager Tests

    @Suite("DataManager")
    struct DataManagerTests {
        @Test("Watch progress round trip")
        @MainActor
        func watchProgressRoundTrip() async throws {
            let manager = try DataManager(inMemory: true)

            // Create a test video
            let video = Video(
                id: .global("testVideo123"),
                title: "Test Video",
                description: nil,
                author: Author(id: "ch1", name: "Channel"),
                duration: 600,
                publishedAt: nil,
                publishedText: nil,
                viewCount: nil,
                likeCount: nil,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            )

            // Record progress
            manager.updateWatchProgress(for: video, seconds: 300)

            // Retrieve progress
            let progress = manager.watchProgress(for: "testVideo123")

            #expect(progress == 300)
        }

        @Test("Bookmark toggle")
        @MainActor
        func bookmarkToggle() async throws {
            let manager = try DataManager(inMemory: true)

            let video = Video(
                id: .global("bookmarkTest"),
                title: "Bookmark Me",
                description: nil,
                author: Author(id: "ch1", name: "Channel"),
                duration: 300,
                publishedAt: nil,
                publishedText: nil,
                viewCount: nil,
                likeCount: nil,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            )

            #expect(!manager.isBookmarked(videoID: "bookmarkTest"))

            manager.addBookmark(for: video)
            #expect(manager.isBookmarked(videoID: "bookmarkTest"))

            manager.removeBookmark(for: "bookmarkTest")
            #expect(!manager.isBookmarked(videoID: "bookmarkTest"))
        }

        @Test("Create and delete playlist")
        @MainActor
        func createAndDeletePlaylist() async throws {
            let manager = try DataManager(inMemory: true)

            let playlist = manager.createPlaylist(title: "Test Playlist", description: "A test")

            #expect(playlist.title == "Test Playlist")
            #expect(playlist.playlistDescription == "A test")

            var playlists = manager.playlists()
            #expect(playlists.count == 1)

            manager.deletePlaylist(playlist)

            playlists = manager.playlists()
            #expect(playlists.count == 0)
        }

        @Test("Subscription management")
        @MainActor
        func subscriptionManagement() async throws {
            let manager = try DataManager(inMemory: true)

            let channel = Channel(
                id: .global("testChannel"),
                name: "Test Channel",
                description: "A test channel",
                subscriberCount: 10000,
                thumbnailURL: nil
            )

            #expect(!manager.isSubscribed(to: "testChannel"))

            manager.subscribe(to: channel)
            #expect(manager.isSubscribed(to: "testChannel"))

            let subs = manager.subscriptions()
            #expect(subs.count == 1)
            #expect(subs.first?.name == "Test Channel")

            manager.unsubscribe(from: "testChannel")
            #expect(!manager.isSubscribed(to: "testChannel"))
        }

        @Test("Watch history ordering")
        @MainActor
        func watchHistoryOrdering() async throws {
            let manager = try DataManager(inMemory: true)

            // Create multiple videos
            for i in 1...3 {
                let video = Video(
                    id: .global("video\(i)"),
                    title: "Video \(i)",
                    description: nil,
                    author: Author(id: "ch1", name: "Channel"),
                    duration: 100,
                    publishedAt: nil,
                    publishedText: nil,
                    viewCount: nil,
                    likeCount: nil,
                    thumbnails: [],
                    isLive: false,
                    isUpcoming: false,
                    scheduledStartTime: nil
                )
                manager.updateWatchProgress(for: video, seconds: Double(i * 10))

                // Small delay to ensure different timestamps
                try await Task.sleep(for: .milliseconds(10))
            }

            let history = manager.watchHistory()

            #expect(history.count == 3)
            // Most recent should be first
            #expect(history.first?.videoID == "video3")
        }
    }
}
