//
//  APITests.swift
//  YatteeTests
//
//  Tests for API-related types and structures.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - SearchResult Tests

@Suite("SearchResult Tests")
@MainActor
struct SearchResultTests {

    @Test("Empty SearchResult")
    func emptyResult() {
        let result = SearchResult.empty
        #expect(result.videos.isEmpty)
        #expect(result.channels.isEmpty)
        #expect(result.playlists.isEmpty)
        #expect(result.nextPage == nil)
    }

    @Test("SearchResult with content")
    func resultWithContent() {
        let videos = [
            makeVideo(title: "Video 1"),
            makeVideo(title: "Video 2"),
        ]
        let channels = [
            Channel(id: .global("ch1"), name: "Channel 1"),
        ]

        let result = SearchResult(
            videos: videos,
            channels: channels,
            playlists: [],
            orderedItems: [],
            nextPage: 2
        )

        #expect(result.videos.count == 2)
        #expect(result.channels.count == 1)
        #expect(result.playlists.isEmpty)
        #expect(result.nextPage == 2)
    }

    private func makeVideo(title: String) -> Video {
        Video(
            id: .global("test"),
            title: title,
            description: nil,
            author: Author(id: "channel", name: "Test Channel"),
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
    }
}

// MARK: - API Endpoint Routing Tests

@Suite("API Endpoint Routing Tests")
@MainActor
struct APIEndpointRoutingTests {

    @Test("Invidious instance uses correct API")
    func invidiousRouting() {
        let instance = Instance(type: .invidious, url: URL(string: "https://inv.example.com")!)
        #expect(instance.type == .invidious)
        #expect(instance.isYouTubeInstance == true)
    }

    @Test("Piped instance uses correct API")
    func pipedRouting() {
        let instance = Instance(type: .piped, url: URL(string: "https://piped.example.com")!)
        #expect(instance.type == .piped)
        #expect(instance.isYouTubeInstance == true)
    }

    @Test("PeerTube instance uses correct API")
    func peerTubeRouting() {
        let instance = Instance(type: .peertube, url: URL(string: "https://pt.example.com")!)
        #expect(instance.type == .peertube)
        #expect(instance.isPeerTubeInstance == true)
    }
}

// MARK: - Author Tests

@Suite("Author Tests")
@MainActor
struct AuthorTests {

    @Test("Author creation")
    func creation() {
        let author = Author(id: "UC123", name: "Test Channel")
        #expect(author.id == "UC123")
        #expect(author.name == "Test Channel")
    }

    @Test("Author with optional fields")
    func optionalFields() {
        let author = Author(
            id: "UC123",
            name: "Test Channel",
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            instance: URL(string: "https://peertube.example.com")
        )
        #expect(author.thumbnailURL != nil)
        #expect(author.instance != nil)
    }
}

// MARK: - Thumbnail Tests

@Suite("Thumbnail Tests")
@MainActor
struct ThumbnailTests {

    @Test("Thumbnail quality ordering")
    func qualityOrdering() {
        // Comparable implementation - lower quality < higher quality
        #expect(Thumbnail.Quality.default < Thumbnail.Quality.medium)
        #expect(Thumbnail.Quality.medium < Thumbnail.Quality.high)
        #expect(Thumbnail.Quality.high < Thumbnail.Quality.standard)
        #expect(Thumbnail.Quality.standard < Thumbnail.Quality.maxres)
    }

    @Test("Best thumbnail selection")
    func bestThumbnailSelection() {
        let thumbnails = [
            Thumbnail(url: URL(string: "https://example.com/default.jpg")!, quality: .default),
            Thumbnail(url: URL(string: "https://example.com/high.jpg")!, quality: .high),
            Thumbnail(url: URL(string: "https://example.com/medium.jpg")!, quality: .medium),
        ]

        // Using Comparable - max returns highest quality
        let best = thumbnails.max(by: { $0.quality < $1.quality })
        #expect(best?.quality == .high)
    }

    @Test("Thumbnail with dimensions")
    func thumbnailWithDimensions() {
        let thumbnail = Thumbnail(
            url: URL(string: "https://example.com/thumb.jpg")!,
            quality: .high,
            width: 1280,
            height: 720
        )
        #expect(thumbnail.width == 1280)
        #expect(thumbnail.height == 720)
    }
}

// MARK: - Channel Search Tests

@Suite("ChannelSearchPage Tests")
@MainActor
struct ChannelSearchPageTests {

    @Test("Empty ChannelSearchPage")
    func emptyPage() {
        let page = ChannelSearchPage.empty
        #expect(page.items.isEmpty)
        #expect(page.nextPage == nil)
    }

    @Test("ChannelSearchPage with videos")
    func pageWithVideos() {
        let video = makeVideo(title: "Test Video")
        let items: [ChannelSearchItem] = [.video(video)]

        let page = ChannelSearchPage(items: items, nextPage: 2)

        #expect(page.items.count == 1)
        #expect(page.nextPage == 2)

        if case .video(let v) = page.items[0] {
            #expect(v.title == "Test Video")
        } else {
            Issue.record("Expected video item")
        }
    }

    @Test("ChannelSearchPage with playlists")
    func pageWithPlaylists() {
        let playlist = Playlist(
            id: .global("PL123"),
            title: "Test Playlist",
            author: Author(id: "ch1", name: "Channel"),
            videoCount: 10
        )
        let items: [ChannelSearchItem] = [.playlist(playlist)]

        let page = ChannelSearchPage(items: items, nextPage: nil)

        #expect(page.items.count == 1)
        #expect(page.nextPage == nil)

        if case .playlist(let p) = page.items[0] {
            #expect(p.title == "Test Playlist")
        } else {
            Issue.record("Expected playlist item")
        }
    }

    @Test("ChannelSearchPage with mixed content")
    func pageWithMixedContent() {
        let video = makeVideo(title: "Video 1")
        let playlist = Playlist(
            id: .global("PL456"),
            title: "Playlist 1",
            author: Author(id: "ch1", name: "Channel"),
            videoCount: 5
        )
        let items: [ChannelSearchItem] = [
            .video(video),
            .playlist(playlist),
        ]

        let page = ChannelSearchPage(items: items, nextPage: 3)

        #expect(page.items.count == 2)
        #expect(page.nextPage == 3)
    }

    @Test("ChannelSearchItem identifiers are unique")
    func uniqueIdentifiers() {
        let video = makeVideo(title: "Video")
        let playlist = Playlist(
            id: .global("PL789"),
            title: "Playlist",
            author: Author(id: "ch1", name: "Channel"),
            videoCount: 3
        )

        let videoItem = ChannelSearchItem.video(video)
        let playlistItem = ChannelSearchItem.playlist(playlist)

        #expect(videoItem.id != playlistItem.id)
        #expect(videoItem.id.hasPrefix("video-"))
        #expect(playlistItem.id.hasPrefix("playlist-"))
    }

    private func makeVideo(title: String) -> Video {
        Video(
            id: .global("test-\(title)"),
            title: title,
            description: nil,
            author: Author(id: "channel", name: "Test Channel"),
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
    }
}
