//
//  ChapterIntegrationTests.swift
//  YatteeTests
//
//  Integration tests for chapter resolution from SponsorBlock and description parsing.
//

import Foundation
import Testing

@testable import Yattee

@Suite("Chapter Integration")
struct ChapterIntegrationTests {

    // MARK: - SponsorBlock Chapter Extraction

    @Test("extracts chapters from SponsorBlock segments")
    func sponsorBlockChapterExtraction() {
        let segments: [SponsorBlockSegment] = [
            makeSponsorBlockChapter(startTime: 0, description: "Introduction"),
            makeSponsorBlockChapter(startTime: 60, description: "Main Topic"),
            makeSponsorBlockChapter(startTime: 300, description: "Conclusion"),
        ]

        let chapters = segments.extractChapters(videoDuration: 600)

        #expect(chapters.count == 3)
        #expect(chapters[0].title == "Introduction")
        #expect(chapters[0].startTime == 0)
        #expect(chapters[0].endTime == 60)
        #expect(chapters[1].title == "Main Topic")
        #expect(chapters[1].startTime == 60)
        #expect(chapters[1].endTime == 300)
        #expect(chapters[2].title == "Conclusion")
        #expect(chapters[2].startTime == 300)
        #expect(chapters[2].endTime == 600)
    }

    @Test("requires minimum 2 SponsorBlock chapters")
    func sponsorBlockMinimumChapters() {
        let segments: [SponsorBlockSegment] = [
            makeSponsorBlockChapter(startTime: 0, description: "Only One"),
        ]

        let chapters = segments.extractChapters(videoDuration: 600)

        #expect(chapters.isEmpty)
    }

    @Test("filters non-chapter SponsorBlock segments")
    func sponsorBlockFiltersNonChapters() {
        let segments: [SponsorBlockSegment] = [
            makeSponsorBlockChapter(startTime: 0, description: "Intro"),
            makeSponsorBlockSegment(startTime: 30, endTime: 60, actionType: .skip, category: .sponsor),
            makeSponsorBlockChapter(startTime: 120, description: "Content"),
            makeSponsorBlockSegment(startTime: 180, endTime: 200, actionType: .mute, category: .musicOfftopic),
        ]

        let chapters = segments.extractChapters(videoDuration: 600)

        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "Content")
    }

    @Test("uses fallback title for chapters without description")
    func sponsorBlockFallbackTitle() {
        let segments: [SponsorBlockSegment] = [
            makeSponsorBlockChapter(startTime: 0, description: nil),
            makeSponsorBlockChapter(startTime: 60, description: nil),
        ]

        let chapters = segments.extractChapters(videoDuration: 600)

        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Chapter 1")
        #expect(chapters[1].title == "Chapter 2")
    }

    @Test("sorts SponsorBlock chapters by start time")
    func sponsorBlockSorting() {
        let segments: [SponsorBlockSegment] = [
            makeSponsorBlockChapter(startTime: 300, description: "Third"),
            makeSponsorBlockChapter(startTime: 0, description: "First"),
            makeSponsorBlockChapter(startTime: 120, description: "Second"),
        ]

        let chapters = segments.extractChapters(videoDuration: 600)

        #expect(chapters.count == 3)
        #expect(chapters[0].title == "First")
        #expect(chapters[1].title == "Second")
        #expect(chapters[2].title == "Third")
    }

    // MARK: - Helpers

    private func makeSponsorBlockChapter(startTime: Double, description: String?) -> SponsorBlockSegment {
        makeSponsorBlockSegment(
            startTime: startTime,
            endTime: startTime, // Chapters have same start/end
            actionType: .chapter,
            category: .sponsor, // Category doesn't matter for chapters
            description: description
        )
    }

    private func makeSponsorBlockSegment(
        startTime: Double,
        endTime: Double,
        actionType: SponsorBlockActionType,
        category: SponsorBlockCategory,
        description: String? = nil
    ) -> SponsorBlockSegment {
        // Create segment using JSON decoding since init is not public
        let json: [String: Any] = [
            "UUID": UUID().uuidString,
            "category": category.rawValue,
            "actionType": actionType.rawValue,
            "segment": [startTime, endTime],
            "videoDuration": 600.0,
            "description": description as Any
        ]

        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(SponsorBlockSegment.self, from: data)
    }
}
