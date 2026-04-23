//
//  ChapterParserTests.swift
//  YatteeTests
//
//  Unit tests for ChapterParser.
//

import Foundation
import Testing

@testable import Yattee

@Suite("ChapterParser")
struct ChapterParserTests {
    
    // MARK: - Timestamp Format Tests
    
    @Test("parses M:SS format")
    func parseMSSFormat() {
        let description = """
        0:00 Intro
        5:30 Topic One
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.count == 2)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].startTime == 330) // 5:30 = 330 seconds
        #expect(chapters[1].title == "Topic One")
    }
    
    @Test("parses MM:SS format")
    func parseMMSSFormat() {
        let description = """
        00:00 Intro
        05:30 Topic One
        12:45 Topic Two
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 900)
        
        #expect(chapters.count == 3)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[1].startTime == 330)
        #expect(chapters[2].startTime == 765) // 12:45 = 765 seconds
    }
    
    @Test("parses H:MM:SS format")
    func parseHMMSSFormat() {
        let description = """
        0:00:00 Intro
        1:23:45 Deep Dive
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 7200)
        
        #expect(chapters.count == 2)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[1].startTime == 5025) // 1*3600 + 23*60 + 45 = 5025
    }
    
    @Test("parses HH:MM:SS format")
    func parseHHMMSSFormat() {
        let description = """
        00:00:00 Intro
        01:23:45 Deep Dive
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 7200)
        
        #expect(chapters.count == 2)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[1].startTime == 5025)
    }
    
    // MARK: - Prefix Stripping Tests
    
    @Test("strips prefix characters")
    func stripPrefixCharacters() {
        let description = """
        ▶ 0:00 Intro
        ► 1:00 First Topic
        • 2:00 Second Topic
        - 3:00 Third Topic
        * 4:00 Fourth Topic
        → 5:00 Fifth Topic
        ➤ 6:00 Sixth Topic
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.count == 7)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "First Topic")
        #expect(chapters[2].title == "Second Topic")
        #expect(chapters[3].title == "Third Topic")
        #expect(chapters[4].title == "Fourth Topic")
        #expect(chapters[5].title == "Fifth Topic")
        #expect(chapters[6].title == "Sixth Topic")
    }
    
    // MARK: - Separator Stripping Tests
    
    @Test("strips separators between timestamp and title")
    func stripSeparators() {
        let description = """
        0:00 - Intro
        1:00 | First Topic
        2:00 : Second Topic
        3:00 – Third Topic
        4:00 — Fourth Topic
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.count == 5)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "First Topic")
        #expect(chapters[2].title == "Second Topic")
        #expect(chapters[3].title == "Third Topic")
        #expect(chapters[4].title == "Fourth Topic")
    }
    
    // MARK: - Timestamp Position Tests
    
    @Test("requires timestamp at line start")
    func timestampMustBeFirst() {
        let description = """
        0:00 Intro
        Check out 5:30 moment
        Intro - 1:00
        10:00 Outro
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 900)
        
        // "Check out 5:30 moment" doesn't start with a timestamp, so it breaks the block.
        // First block has only 1 chapter (0:00 Intro), which is less than minimum 2.
        // Result: empty array
        #expect(chapters.isEmpty)
    }
    
    // MARK: - Bracket Tests
    
    @Test("ignores bracketed timestamps")
    func ignoreBracketedTimestamps() {
        let description = """
        0:00 Intro
        [1:00] Should Be Ignored
        (2:00) Also Ignored
        3:00 Valid Chapter
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.count == 2)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[1].startTime == 180) // 3:00
    }
    
    // MARK: - Empty Title Tests
    
    @Test("skips chapters without titles")
    func skipEmptyTitles() {
        let description = """
        0:00 Intro
        1:00
        2:00    
        3:00 Valid Chapter
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "Valid Chapter")
    }
    
    // MARK: - Minimum Chapters Tests
    
    @Test("requires minimum 2 chapters")
    func minimumChaptersRequired() {
        let description = """
        0:00 Only One Chapter
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.isEmpty)
    }
    
    @Test("returns chapters when exactly 2 exist")
    func exactlyTwoChapters() {
        let description = """
        0:00 First
        5:00 Second
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.count == 2)
    }
    
    // MARK: - Block Detection Tests
    
    @Test("detects first contiguous block only")
    func firstContiguousBlockOnly() {
        let description = """
        Some intro text
        
        0:00 Intro
        1:00 Topic A
        2:00 Topic B
        
        Check my other video:
        0:00 Other Video Intro
        1:00 Other Topic
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.count == 3)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "Topic A")
        #expect(chapters[2].title == "Topic B")
    }
    
    @Test("empty lines don't break block")
    func emptyLinesDontBreakBlock() {
        let description = """
        0:00 Intro
        
        1:00 Topic A
        
        
        2:00 Topic B
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters.count == 3)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "Topic A")
        #expect(chapters[2].title == "Topic B")
    }
    
    // MARK: - Sorting Tests
    
    @Test("auto-sorts chronologically")
    func autoSortChronologically() {
        let description = """
        5:00 Middle
        0:00 Start
        10:00 End
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 900)
        
        #expect(chapters.count == 3)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[0].title == "Start")
        #expect(chapters[1].startTime == 300)
        #expect(chapters[1].title == "Middle")
        #expect(chapters[2].startTime == 600)
        #expect(chapters[2].title == "End")
    }
    
    // MARK: - Synthetic Intro Tests
    
    @Test("inserts synthetic intro at 0:00")
    func insertSyntheticIntro() {
        let description = """
        1:00 First Real Chapter
        5:00 Second Chapter
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600, introTitle: "Intro")
        
        #expect(chapters.count == 3)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].startTime == 60)
        #expect(chapters[1].title == "First Real Chapter")
    }
    
    @Test("does not insert intro if first chapter starts at 0:00")
    func noSyntheticIntroWhenStartsAtZero() {
        let description = """
        0:00 Actual Intro
        5:00 Next Chapter
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600, introTitle: "Intro")
        
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Actual Intro")
    }
    
    @Test("uses custom intro title")
    func customIntroTitle() {
        let description = """
        1:00 First Chapter
        5:00 Second Chapter
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600, introTitle: "Einleitung")
        
        #expect(chapters[0].title == "Einleitung")
    }
    
    // MARK: - Duplicate Timestamp Tests
    
    @Test("merges duplicate timestamps")
    func mergeDuplicateTimestamps() {
        let description = """
        0:00 Intro
        5:00 Topic A
        5:00 Topic B
        10:00 Outro
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 900)
        
        #expect(chapters.count == 3)
        #expect(chapters[1].startTime == 300)
        #expect(chapters[1].title == "Topic A / Topic B")
    }
    
    // MARK: - Duration Validation Tests
    
    @Test("discards timestamps beyond duration")
    func discardBeyondDuration() {
        let description = """
        0:00 Intro
        5:00 Middle
        20:00 Beyond Duration
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600) // 10 minutes
        
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "Middle")
    }
    
    @Test("returns empty for nil description")
    func nilDescription() {
        let chapters = ChapterParser.parse(description: nil, videoDuration: 600)
        
        #expect(chapters.isEmpty)
    }
    
    @Test("returns empty for empty description")
    func emptyDescription() {
        let chapters = ChapterParser.parse(description: "", videoDuration: 600)
        
        #expect(chapters.isEmpty)
    }
    
    @Test("returns empty for zero duration")
    func zeroDuration() {
        let description = """
        0:00 Intro
        5:00 Topic
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 0)
        
        #expect(chapters.isEmpty)
    }
    
    @Test("returns empty for negative duration")
    func negativeDuration() {
        let description = """
        0:00 Intro
        5:00 Topic
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: -100)
        
        #expect(chapters.isEmpty)
    }
    
    // MARK: - End Time Tests
    
    @Test("calculates correct end times")
    func correctEndTimes() {
        let description = """
        0:00 Intro
        1:00 Middle
        5:00 Outro
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        #expect(chapters[0].endTime == 60)   // Ends when Middle starts
        #expect(chapters[1].endTime == 300)  // Ends when Outro starts
        #expect(chapters[2].endTime == 600)  // Ends at video duration
    }
    
    // MARK: - Real World Examples
    
    @Test("parses real world MKBHD-style description")
    func realWorldMKBHDStyle() {
        let description = """
        Mac Studio is here! Plus, a new display.
        
        MKBHD Merch: http://shop.MKBHD.com
        
        0:00 Intro
        1:52 The Design/Ports
        4:00 Display XDR
        6:00 M1 Ultra Chip
        8:06 Real World Performance
        11:09 Who should buy this?
        13:07 My Thoughts
        
        Tech I'm using right now: https://www.example.com
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 900)
        
        #expect(chapters.count == 7)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "The Design/Ports")
        #expect(chapters[2].title == "Display XDR")
        #expect(chapters[3].title == "M1 Ultra Chip")
        #expect(chapters[4].title == "Real World Performance")
        #expect(chapters[5].title == "Who should buy this?")
        #expect(chapters[6].title == "My Thoughts")
    }
    
    @Test("parses real world Linus Tech Tips style description")
    func realWorldLTTStyle() {
        let description = """
        Get exclusive NordVPN deal here ➼ https://nordvpn.com/ltt
        
        Timestamps:
        ► 0:00 - Intro
        ► 2:15 - Unboxing
        ► 5:30 - Build Quality
        ► 8:45 - Performance Tests
        ► 12:00 - Conclusion
        
        BUY: GPU at Amazon: https://amazon.com
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 900)
        
        #expect(chapters.count == 5)
        #expect(chapters[0].title == "Intro")
        #expect(chapters[1].title == "Unboxing")
        #expect(chapters[2].title == "Build Quality")
        #expect(chapters[3].title == "Performance Tests")
        #expect(chapters[4].title == "Conclusion")
    }
    
    @Test("parses description with indented timestamps")
    func indentedTimestamps() {
        let description = """
        Video chapters:
        
          0:00 Introduction
          3:00 Main Topic
          10:00 Conclusion
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 900)
        
        #expect(chapters.count == 3)
        #expect(chapters[0].title == "Introduction")
    }
    
    @Test("handles timestamps with special characters in titles")
    func specialCharactersInTitles() {
        let description = """
        0:00 Introduction & Overview
        5:00 Q&A Session
        10:00 What's Next?
        15:00 C++ vs Rust
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 1200)
        
        #expect(chapters.count == 4)
        #expect(chapters[0].title == "Introduction & Overview")
        #expect(chapters[1].title == "Q&A Session")
        #expect(chapters[2].title == "What's Next?")
        #expect(chapters[3].title == "C++ vs Rust")
    }
    
    // MARK: - Edge Cases
    
    @Test("handles invalid seconds value")
    func invalidSecondsValue() {
        let description = """
        0:00 Intro
        1:99 Invalid Seconds
        2:00 Valid
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600)
        
        // 1:99 should be rejected, leaving only 2 valid chapters
        #expect(chapters.count == 2)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[1].startTime == 120)
    }
    
    @Test("handles timestamp at exact duration boundary")
    func timestampAtDurationBoundary() {
        let description = """
        0:00 Intro
        5:00 Middle
        10:00 At Boundary
        """
        let chapters = ChapterParser.parse(description: description, videoDuration: 600) // 10:00 = 600s
        
        // 10:00 (600s) is NOT < 600, so it should be filtered out
        #expect(chapters.count == 2)
    }
    
    @Test("handles very long video with many chapters")
    func manyChapters() {
        var lines: [String] = []
        for i in 0..<50 {
            let minutes = i * 5
            lines.append("\(minutes):00 Chapter \(i + 1)")
        }
        let description = lines.joined(separator: "\n")
        
        let chapters = ChapterParser.parse(description: description, videoDuration: 15000) // ~4 hours
        
        #expect(chapters.count == 50)
        #expect(chapters.first?.title == "Chapter 1")
        #expect(chapters.last?.title == "Chapter 50")
    }
}
