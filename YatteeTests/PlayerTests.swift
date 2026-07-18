//
//  PlayerTests.swift
//  YatteeTests
//
//  Tests for player service and SponsorBlock integration.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - SponsorBlock Category Extended Tests

@Suite("SponsorBlock Category Extended Tests")
struct SponsorBlockCategoryExtendedTests {
    @Test("All categories have descriptions")
    func descriptions() {
        for category in SponsorBlockCategory.allCases {
            #expect(!category.localizedDescription.isEmpty)
        }
    }

    @Test("Default auto-skip categories")
    func defaultAutoSkip() {
        #expect(SponsorBlockCategory.sponsor.defaultAutoSkip)
        #expect(SponsorBlockCategory.selfpromo.defaultAutoSkip)
        #expect(SponsorBlockCategory.interaction.defaultAutoSkip)
        #expect(!SponsorBlockCategory.filler.defaultAutoSkip)
        #expect(!SponsorBlockCategory.highlight.defaultAutoSkip)
    }

    @Test("Highlight category exists")
    func highlightCategory() {
        #expect(SponsorBlockCategory.highlight.rawValue == "poi_highlight")
        #expect(SponsorBlockCategory.highlight.displayName == "Highlight")
    }
}

// MARK: - SponsorBlock Segment Tests

@Suite("SponsorBlock Segment Tests")
struct SponsorBlockSegmentTests {
    @Test("Segment timing calculations")
    func segmentTiming() throws {
        let json = """
        {
            "UUID": "test-uuid",
            "category": "sponsor",
            "actionType": "skip",
            "segment": [10.5, 30.0],
            "videoDuration": 600.0,
            "votes": 10,
            "description": "Sponsor segment"
        }
        """

        let segment = try JSONDecoder().decode(SponsorBlockSegment.self, from: json.data(using: .utf8)!)

        #expect(segment.uuid == "test-uuid")
        #expect(segment.startTime == 10.5)
        #expect(segment.endTime == 30.0)
        #expect(segment.duration == 19.5)
        #expect(segment.category == .sponsor)
        #expect(segment.actionType == .skip)
        #expect(!segment.isPointOfInterest)
        #expect(segment.segmentDescription == "Sponsor segment")
    }

    @Test("Point of interest detection")
    func pointOfInterest() throws {
        let json = """
        {
            "UUID": "poi-uuid",
            "category": "poi_highlight",
            "actionType": "poi",
            "segment": [120.0, 120.0]
        }
        """

        let segment = try JSONDecoder().decode(SponsorBlockSegment.self, from: json.data(using: .utf8)!)

        #expect(segment.isPointOfInterest)
        #expect(segment.startTime == segment.endTime)
    }
}

// MARK: - Segment Array Extension Tests

@Suite("Segment Array Extensions")
struct SegmentArrayTests {
    let segments: [SponsorBlockSegment]

    init() throws {
        let json = """
        [
            {"UUID": "1", "category": "sponsor", "actionType": "skip", "segment": [10.0, 20.0]},
            {"UUID": "2", "category": "intro", "actionType": "skip", "segment": [0.0, 5.0]},
            {"UUID": "3", "category": "selfpromo", "actionType": "mute", "segment": [30.0, 40.0]},
            {"UUID": "4", "category": "outro", "actionType": "skip", "segment": [580.0, 600.0]}
        ]
        """
        self.segments = try JSONDecoder().decode([SponsorBlockSegment].self, from: json.data(using: .utf8)!)
    }

    @Test("Filter skippable segments")
    func skippable() {
        let skippable = segments.skippable()
        #expect(skippable.count == 3)
        #expect(!skippable.contains { $0.uuid == "3" }) // mute action excluded
    }

    @Test("Filter by categories")
    func inCategories() {
        let sponsorOnly = segments.inCategories([.sponsor])
        #expect(sponsorOnly.count == 1)
        #expect(sponsorOnly.first?.uuid == "1")

        let multiple = segments.inCategories([.sponsor, .intro])
        #expect(multiple.count == 2)
    }

    @Test("Find segment at time")
    func segmentAtTime() {
        let atStart = segments.segment(at: 2.0)
        #expect(atStart?.uuid == "2") // intro 0-5

        let atSponsor = segments.segment(at: 15.0)
        #expect(atSponsor?.uuid == "1") // sponsor 10-20

        let atNothing = segments.segment(at: 25.0)
        #expect(atNothing == nil)
    }

    @Test("Find next segment after time")
    func nextSegmentAfterTime() {
        let afterStart = segments.nextSegment(after: 6.0)
        #expect(afterStart?.uuid == "1") // sponsor at 10.0

        let afterSponsor = segments.nextSegment(after: 25.0)
        #expect(afterSponsor?.uuid == "3") // selfpromo at 30.0

        let afterAll = segments.nextSegment(after: 590.0)
        #expect(afterAll == nil)
    }
}

// MARK: - Player State Tests

@Suite("Player State Tests")
@MainActor
struct PlayerStateTests {
    @Test("Initial state")
    func initialState() {
        let state = PlayerState()

        #expect(state.playbackState == .idle)
        #expect(state.currentVideo == nil)
        #expect(state.currentTime == 0)
        #expect(state.duration == 0)
        #expect(state.rate == .x1)
        #expect(!state.isMuted)
    }

    @Test("Progress calculation")
    func progressCalculation() {
        let state = PlayerState()
        state.duration = 100
        state.currentTime = 50

        #expect(state.progress == 0.5)
    }

    @Test("Progress calculation with zero duration")
    func progressZeroDuration() {
        let state = PlayerState()
        state.duration = 0
        state.currentTime = 50

        #expect(state.progress == 0)
    }

    @Test("Time formatting")
    func timeFormatting() {
        let state = PlayerState()

        state.currentTime = 65 // 1:05
        #expect(state.formattedCurrentTime == "1:05")

        state.duration = 3661 // 1:01:01
        #expect(state.formattedDuration == "1:01:01")

        state.currentTime = 3600 // remaining = 61 seconds = 1:01
        #expect(state.formattedRemainingTime == "-1:01")
    }

    @Test("Queue operations")
    func queueOperations() {
        let state = PlayerState()

        let video1 = Video(
            id: .global("video1"),
            title: "Video 1",
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

        let video2 = Video(
            id: .global("video2"),
            title: "Video 2",
            description: nil,
            author: Author(id: "ch1", name: "Channel"),
            duration: 200,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )

        // Add to queue
        state.addToQueue(video1)
        state.addToQueue(video2)

        #expect(state.queue.count == 2)
        #expect(!state.hasPrevious)
        #expect(state.hasNext)

        // Advance - returns first item (video1) and removes it from queue
        let next = state.advanceQueue()
        #expect(next?.video.id == video1.id)
        #expect(state.queue.count == 1)
        #expect(!state.hasPrevious)  // No history yet
        #expect(state.hasNext)  // video2 still in queue

        // Add video1 to history manually (simulating playback)
        state.pushToHistory(next!)

        // Now advance to video2
        let next2 = state.advanceQueue()
        #expect(next2?.video.id == video2.id)
        #expect(state.hasPrevious)  // video1 is in history
        #expect(!state.hasNext)  // queue is empty

        // Retreat - returns last item from history (video1)
        let prev = state.retreatQueue()
        #expect(prev?.video.id == video1.id)
        #expect(!state.hasPrevious)  // history is now empty

        // Clear
        state.clearQueue()
        #expect(state.queue.isEmpty)
    }

    @Test("SponsorBlock auto-skip categories")
    func autoSkipCategories() {
        let state = PlayerState()

        // Default should include common skip categories
        #expect(state.autoSkipCategories.contains(.sponsor))
        #expect(state.autoSkipCategories.contains(.selfpromo))
        #expect(!state.autoSkipCategories.contains(.filler))
    }
}

// MARK: - Playback Rate Tests

@Suite("Playback Rate Tests")
struct PlaybackRateTests {
    @Test("All rates have display text")
    func displayText() {
        for rate in PlaybackRate.allCases {
            #expect(!rate.displayText.isEmpty)
        }
    }

    @Test("Normal rate displays correctly")
    func normalRate() {
        #expect(PlaybackRate.x1.displayText == "Normal")
    }

    @Test("Other rates format correctly")
    func otherRates() {
        #expect(PlaybackRate.x15.displayText == "1.5x")
        #expect(PlaybackRate.x2.displayText == "2x")
        #expect(PlaybackRate.x025.displayText == "0.25x")
    }

    @Test("Compact display text always shows numeric format")
    func compactDisplayText() {
        #expect(PlaybackRate.x1.compactDisplayText == "1x")
        #expect(PlaybackRate.x15.compactDisplayText == "1.5x")
        #expect(PlaybackRate.x2.compactDisplayText == "2x")
    }
}

// MARK: - Video Chapter Tests

@Suite("Video Chapter Tests")
struct VideoChapterTests {
    @Test("Chapter initialization")
    func initialization() {
        let chapter = VideoChapter(
            title: "Introduction",
            startTime: 0,
            endTime: 60
        )

        #expect(chapter.title == "Introduction")
        #expect(chapter.startTime == 0)
        #expect(chapter.endTime == 60)
        #expect(chapter.duration == 60)
    }

    @Test("Formatted start time")
    func formattedStartTime() {
        let chapter1 = VideoChapter(title: "A", startTime: 65)
        #expect(chapter1.formattedStartTime == "1:05")

        let chapter2 = VideoChapter(title: "B", startTime: 3661)
        #expect(chapter2.formattedStartTime == "1:01:01")
    }

    @Test("Current chapter detection")
    @MainActor
    func currentChapter() {
        let state = PlayerState()
        state.chapters = [
            VideoChapter(title: "Intro", startTime: 0, endTime: 30),
            VideoChapter(title: "Main", startTime: 30, endTime: 120),
            VideoChapter(title: "Outro", startTime: 120, endTime: 150)
        ]

        state.currentTime = 15
        #expect(state.currentChapter?.title == "Intro")

        state.currentTime = 60
        #expect(state.currentChapter?.title == "Main")

        state.currentTime = 130
        #expect(state.currentChapter?.title == "Outro")
    }
}

// MARK: - Playback State Tests

@Suite("Playback State Tests")
struct PlaybackStateTests {
    @Test("State equality")
    func stateEquality() {
        #expect(PlaybackState.idle == PlaybackState.idle)
        #expect(PlaybackState.playing == PlaybackState.playing)
        #expect(PlaybackState.idle != PlaybackState.playing)

        // Failed states are equal regardless of error content
        let error1 = NSError(domain: "test", code: 1)
        let error2 = NSError(domain: "test", code: 2)
        #expect(PlaybackState.failed(error1) == PlaybackState.failed(error2))
    }
}
