//
//  YatteeServerFeedChunkingTests.swift
//  YatteeTests
//
//  Tests for chunking and merging of stateless feed requests against Yattee Server,
//  which rejects more than 500 channels per request.
//

import Testing
import Foundation
@testable import Yattee

@Suite("Yattee Server Feed Chunking Tests")
struct YatteeServerFeedChunkingTests {

    private func video(id: String, published: Int64?) -> ServerFeedVideo {
        ServerFeedVideo(
            type: "video",
            videoId: id,
            title: "Video \(id)",
            author: "Author",
            authorId: "UC\(id)",
            lengthSeconds: 60,
            published: published,
            publishedText: nil,
            viewCount: nil,
            videoThumbnails: nil,
            extractor: "youtube",
            videoUrl: nil,
            isUpcoming: nil,
            premiereTimestamp: nil
        )
    }

    // MARK: - Chunking

    @Test("Chunked splits arrays at the requested size")
    func chunkedSplitsAtSize() {
        let channels = Array(0..<1018)
        let chunks = channels.chunked(into: 500)
        #expect(chunks.map(\.count) == [500, 500, 18])
        #expect(chunks.flatMap { $0 } == channels)
    }

    @Test("Chunked keeps lists within the size as a single chunk")
    func chunkedSingleChunk() {
        #expect(Array(0..<500).chunked(into: 500).count == 1)
        #expect(Array(0..<3).chunked(into: 500).map(\.count) == [3])
        #expect([Int]().chunked(into: 500).isEmpty)
    }

    // MARK: - Feed Response Merging

    @Test("Merging a single feed response returns it unchanged")
    func mergedSingleFeedResponsePassthrough() {
        // Deliberately unsorted: a single response must not be re-sorted or truncated.
        let response = StatelessFeedResponse(
            status: "pending",
            videos: [video(id: "a", published: 100), video(id: "b", published: 300)],
            total: 2,
            hasMore: true,
            readyCount: 1,
            pendingCount: 2,
            errorCount: nil,
            etaSeconds: 30
        )
        let merged = StatelessFeedResponse.merged([response], limit: 1)
        #expect(merged.videos.map(\.videoId) == ["a", "b"])
        #expect(merged.status == "pending")
        #expect(merged.total == 2)
    }

    @Test("Merging feed responses sorts videos by published date and applies the limit")
    func mergedFeedResponsesSortsAndLimits() {
        let first = StatelessFeedResponse(
            status: "ready",
            videos: [video(id: "old", published: 100), video(id: "newest", published: 900)],
            total: 2,
            hasMore: false,
            readyCount: 500,
            pendingCount: 0,
            errorCount: 0,
            etaSeconds: nil
        )
        let second = StatelessFeedResponse(
            status: "ready",
            videos: [video(id: "middle", published: 500), video(id: "undated", published: nil)],
            total: 2,
            hasMore: false,
            readyCount: 18,
            pendingCount: 0,
            errorCount: 0,
            etaSeconds: nil
        )

        let merged = StatelessFeedResponse.merged([first, second], limit: 3)
        #expect(merged.videos.map(\.videoId) == ["newest", "middle", "old"])
        #expect(merged.total == 4)
        #expect(merged.hasMore) // truncated from 4 to 3
        #expect(merged.readyCount == 518)
        #expect(merged.status == "ready")
        #expect(merged.isReady)
    }

    @Test("Merged feed response is pending while any chunk is pending")
    func mergedFeedResponsePendingWhileAnyChunkPending() {
        let ready = StatelessFeedResponse(
            status: "ready", videos: [], total: 0, hasMore: false,
            readyCount: 500, pendingCount: 0, errorCount: 0, etaSeconds: nil
        )
        let pending = StatelessFeedResponse(
            status: "pending", videos: [], total: 0, hasMore: false,
            readyCount: 10, pendingCount: 8, errorCount: 0, etaSeconds: 45
        )

        let merged = StatelessFeedResponse.merged([ready, pending], limit: 100)
        #expect(merged.status == "pending")
        #expect(!merged.isReady)
        #expect(merged.pendingCount == 8)
        #expect(merged.etaSeconds == 45)
    }

    @Test("Merged feed response keeps counts nil when no chunk reports them")
    func mergedFeedResponseKeepsNilCounts() {
        let first = StatelessFeedResponse(
            status: "ready", videos: [], total: 0, hasMore: false,
            readyCount: nil, pendingCount: nil, errorCount: nil, etaSeconds: nil
        )
        let merged = StatelessFeedResponse.merged([first, first], limit: 100)
        #expect(merged.readyCount == nil)
        #expect(merged.pendingCount == nil)
        #expect(merged.errorCount == nil)
        #expect(merged.etaSeconds == nil)
    }

    // MARK: - Feed Status Merging

    @Test("Merging status responses sums counts and stays pending until all chunks are ready")
    func mergedStatusResponses() {
        let ready = StatelessFeedStatusResponse(status: "ready", readyCount: 500, pendingCount: 0, errorCount: 1)
        let pending = StatelessFeedStatusResponse(status: "pending", readyCount: 10, pendingCount: 8, errorCount: 0)

        let merged = StatelessFeedStatusResponse.merged([ready, pending])
        #expect(merged.status == "pending")
        #expect(merged.readyCount == 510)
        #expect(merged.pendingCount == 8)
        #expect(merged.errorCount == 1)

        let allReady = StatelessFeedStatusResponse.merged([ready, ready])
        #expect(allReady.isReady)
        #expect(allReady.readyCount == 1000)
    }
}
