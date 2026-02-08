//
//  InvidiousAPIIntegrationTests.swift
//  YatteeTests
//
//  Integration tests for InvidiousAPI against a real instance.
//  These tests make actual network requests and validate response parsing.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Integration Test Tag

extension Tag {
    /// Tag for integration tests that require network access.
    @Tag static var integration: Self
}

// MARK: - Invidious API Integration Tests

@Suite("Invidious API Integration Tests", .tags(.integration), .serialized)
struct InvidiousAPIIntegrationTests {
    let api: InvidiousAPI
    let instance: Instance

    init() {
        let httpClient = HTTPClient()
        self.api = InvidiousAPI(httpClient: httpClient)
        self.instance = IntegrationTestConstants.testInstance
    }

    // MARK: - Trending Tests

    @Test("Trending returns videos or handles unavailable")
    func trendingReturnsVideos() async throws {
        do {
            let videos = try await api.trending(instance: instance)
            // If trending is available, it should return videos
            if !videos.isEmpty {
                #expect(videos.count >= 1, "Trending should return at least one video")
            }
        } catch {
            // Trending may not be enabled on all instances - skip gracefully
            // This is acceptable for integration tests
        }
    }

    @Test("Trending videos have required fields when available")
    func trendingVideosHaveRequiredFields() async throws {
        do {
            let videos = try await api.trending(instance: instance)

            guard let video = videos.first else {
                // No videos is acceptable
                return
            }

            #expect(!video.id.videoID.isEmpty, "Video should have an ID")
            #expect(!video.title.isEmpty, "Video should have a title")
            #expect(!video.author.name.isEmpty, "Video should have an author name")
            #expect(video.duration >= 0, "Video should have non-negative duration")
        } catch {
            // Trending may not be available
        }
    }

    @Test("Trending videos have thumbnails when available")
    func trendingVideosHaveThumbnails() async throws {
        do {
            let videos = try await api.trending(instance: instance)

            guard let video = videos.first else {
                return
            }

            #expect(!video.thumbnails.isEmpty, "Video should have thumbnails")
            #expect(video.bestThumbnail != nil, "Video should have a best thumbnail")
        } catch {
            // Trending may not be available
        }
    }

    // MARK: - Search Tests

    @Test("Search returns results")
    func searchReturnsResults() async throws {
        let result = try await api.search(
            query: IntegrationTestConstants.testSearchQuery,
            instance: instance,
            page: 1
        )

        #expect(!result.videos.isEmpty, "Search should return videos")
    }

    @Test("Search videos have required fields")
    func searchVideosHaveRequiredFields() async throws {
        let result = try await api.search(
            query: IntegrationTestConstants.testSearchQuery,
            instance: instance,
            page: 1
        )

        guard let video = result.videos.first else {
            Issue.record("No videos returned from search")
            return
        }

        #expect(!video.id.videoID.isEmpty, "Search video should have an ID")
        #expect(!video.title.isEmpty, "Search video should have a title")
    }

    @Test("Search pagination works")
    func searchPaginationWorks() async throws {
        let page1 = try await api.search(
            query: IntegrationTestConstants.testSearchQuery,
            instance: instance,
            page: 1
        )

        #expect(page1.nextPage != nil, "First page should have a next page")

        let page2 = try await api.search(
            query: IntegrationTestConstants.testSearchQuery,
            instance: instance,
            page: 2
        )

        // Page 2 should have different videos (if enough results exist)
        if !page1.videos.isEmpty && !page2.videos.isEmpty {
            let page1IDs = Set(page1.videos.map { $0.id.videoID })
            let page2IDs = Set(page2.videos.map { $0.id.videoID })
            let overlap = page1IDs.intersection(page2IDs)

            // Allow some overlap but not complete overlap
            #expect(overlap.count < page1.videos.count, "Page 2 should have different videos than page 1")
        }
    }

    @Test("Search suggestions returns strings")
    func searchSuggestionsReturnsStrings() async throws {
        let suggestions = try await api.searchSuggestions(
            query: "never gonna",
            instance: instance
        )

        #expect(!suggestions.isEmpty, "Search suggestions should return results")
        #expect(suggestions.contains { $0.lowercased().contains("never") }, "Suggestions should be relevant to query")
    }

    // MARK: - Video Details Tests

    @Test("Video details returns complete info")
    func videoDetailsReturnsCompleteInfo() async throws {
        let video = try await api.video(
            id: IntegrationTestConstants.testVideoID,
            instance: instance
        )

        #expect(video.id.videoID == IntegrationTestConstants.testVideoID, "Should return correct video")
        #expect(!video.title.isEmpty, "Video should have a title")
        #expect(!video.author.name.isEmpty, "Video should have an author")
        #expect(video.duration > 0, "Video should have positive duration")
        #expect(video.viewCount ?? 0 > 0, "Popular video should have views")
    }

    @Test("Video details includes thumbnails")
    func videoDetailsIncludesThumbnails() async throws {
        let video = try await api.video(
            id: IntegrationTestConstants.testVideoID,
            instance: instance
        )

        #expect(!video.thumbnails.isEmpty, "Video should have thumbnails")

        let thumbnail = video.thumbnails.first!
        #expect(thumbnail.url.absoluteString.contains("http"), "Thumbnail should have valid URL")
    }

    @Test("Video details includes author info")
    func videoDetailsIncludesAuthorInfo() async throws {
        let video = try await api.video(
            id: IntegrationTestConstants.testVideoID,
            instance: instance
        )

        #expect(!video.author.id.isEmpty, "Author should have an ID")
        #expect(!video.author.name.isEmpty, "Author should have a name")
    }

    // MARK: - Streams Tests

    @Test("Streams includes HLS when available")
    func streamsIncludesHLS() async throws {
        let streams = try await api.streams(
            videoID: IntegrationTestConstants.testVideoID,
            instance: instance
        )

        // HLS may not be available on all instances
        let hlsStream = streams.first { $0.format == "hls" }
        if let hls = hlsStream {
            #expect(hls.mimeType == "application/x-mpegURL", "HLS should have correct MIME type")
        }
        // Test passes whether HLS is available or not
    }

    @Test("Streams includes multiple formats")
    func streamsIncludesMultipleFormats() async throws {
        let streams = try await api.streams(
            videoID: IntegrationTestConstants.testVideoID,
            instance: instance
        )

        #expect(streams.count > 1, "Should have multiple streams")

        let formats = Set(streams.map { $0.format })
        #expect(formats.count > 1, "Should have multiple formats")
    }

    @Test("Streams includes video resolutions")
    func streamsIncludesVideoResolutions() async throws {
        let streams = try await api.streams(
            videoID: IntegrationTestConstants.testVideoID,
            instance: instance
        )

        let videoStreams = streams.filter { $0.resolution != nil && !$0.isAudioOnly }
        #expect(!videoStreams.isEmpty, "Should have video streams with resolutions")

        let hasHD = videoStreams.contains { ($0.resolution?.height ?? 0) >= 720 }
        #expect(hasHD, "Popular video should have HD streams")
    }

    @Test("Streams includes audio-only tracks")
    func streamsIncludesAudioOnlyTracks() async throws {
        let streams = try await api.streams(
            videoID: IntegrationTestConstants.testVideoID,
            instance: instance
        )

        let audioStreams = streams.filter { $0.isAudioOnly }
        #expect(!audioStreams.isEmpty, "Should have audio-only streams")
    }

    // MARK: - Channel Tests

    @Test("Channel returns info")
    func channelReturnsInfo() async throws {
        let channel = try await api.channel(
            id: IntegrationTestConstants.testChannelID,
            instance: instance
        )

        #expect(channel.id.channelID == IntegrationTestConstants.testChannelID, "Should return correct channel")
        #expect(!channel.name.isEmpty, "Channel should have a name")
        #expect(channel.subscriberCount ?? 0 > 0, "Popular channel should have subscribers")
    }

    @Test("Channel includes thumbnail")
    func channelIncludesThumbnail() async throws {
        let channel = try await api.channel(
            id: IntegrationTestConstants.testChannelID,
            instance: instance
        )

        #expect(channel.thumbnailURL != nil, "Channel should have thumbnail URL")
    }

    @Test("Channel videos returns videos")
    func channelVideosReturnsVideos() async throws {
        let page = try await api.channelVideos(
            id: IntegrationTestConstants.testChannelID,
            instance: instance,
            continuation: nil
        )

        #expect(!page.videos.isEmpty, "Channel should have videos")

        let video = page.videos.first!
        #expect(!video.title.isEmpty, "Channel video should have title")
    }

    // MARK: - Comments Tests

    @Test("Comments returns results or handles disabled")
    func commentsReturnsResultsOrHandlesDisabled() async throws {
        do {
            let page = try await api.comments(
                videoID: IntegrationTestConstants.testVideoID,
                instance: instance,
                continuation: nil
            )

            // If we get here, comments are enabled
            #expect(!page.comments.isEmpty, "Video with comments should return some")

            let comment = page.comments.first!
            #expect(!comment.id.isEmpty, "Comment should have ID")
            #expect(!comment.content.isEmpty, "Comment should have content")
            #expect(!comment.author.name.isEmpty, "Comment should have author")
        } catch APIError.commentsDisabled {
            // Comments disabled is acceptable - test passes
        } catch {
            throw error
        }
    }

    // MARK: - Captions Tests

    @Test("Captions returns available tracks")
    func captionsReturnsAvailableTracks() async throws {
        let captions = try await api.captions(
            videoID: IntegrationTestConstants.testVideoID,
            instance: instance
        )

        // Popular video should have captions, but it's not guaranteed
        if !captions.isEmpty {
            let caption = captions.first!
            #expect(!caption.label.isEmpty, "Caption should have label")
            #expect(!caption.languageCode.isEmpty, "Caption should have language code")
            #expect(caption.url.absoluteString.contains("http"), "Caption should have valid URL")
        }
    }

    // MARK: - Error Handling Tests

    @Test("Invalid video ID returns error")
    func invalidVideoIDReturnsError() async throws {
        do {
            _ = try await api.video(id: "invalid_video_id_that_does_not_exist", instance: instance)
            Issue.record("Expected error for invalid video ID")
        } catch {
            // Any error is acceptable - notFound, requestFailed, etc.
            // Different instances may return different error codes
        }
    }

    @Test("Invalid channel ID returns error")
    func invalidChannelIDReturnsError() async throws {
        do {
            _ = try await api.channel(id: "invalid_channel_id_xyz", instance: instance)
            Issue.record("Expected error for invalid channel ID")
        } catch {
            // Any error is acceptable - notFound, requestFailed, etc.
            // Different instances may return different error codes
        }
    }
}
