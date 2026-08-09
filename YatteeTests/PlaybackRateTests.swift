//
//  PlaybackRateTests.swift
//  YatteeTests
//
//  Tests for PlaybackRate display-text formatting.
//

import Testing
import Foundation
@testable import Yattee

@Suite("PlaybackRate Display Tests")
struct PlaybackRateDisplayTests {
    @Test("displayText renders every rate without losing precision")
    func displayTextPrecision() {
        #expect(PlaybackRate.x025.displayText == "0.25x")
        #expect(PlaybackRate.x05.displayText == "0.5x")
        #expect(PlaybackRate.x075.displayText == "0.75x")
        #expect(PlaybackRate.x125.displayText == "1.25x")
        #expect(PlaybackRate.x15.displayText == "1.5x")
        #expect(PlaybackRate.x175.displayText == "1.75x")
        #expect(PlaybackRate.x2.displayText == "2x")
        #expect(PlaybackRate.x25.displayText == "2.5x")
        #expect(PlaybackRate.x3.displayText == "3x")
    }

    @Test("displayText for the normal rate uses the localized label, not the numeric form")
    func displayTextNormal() {
        let normal = PlaybackRate.x1.displayText
        #expect(normal == String(localized: "player.playbackRate.normal"))
        #expect(!normal.hasSuffix("x"))
    }

    @Test("compactDisplayText always shows the numeric value")
    func compactDisplayText() {
        #expect(PlaybackRate.x1.compactDisplayText == "1x")
        #expect(PlaybackRate.x125.compactDisplayText == "1.25x")
        #expect(PlaybackRate.x15.compactDisplayText == "1.5x")
        #expect(PlaybackRate.x175.compactDisplayText == "1.75x")
        #expect(PlaybackRate.x2.compactDisplayText == "2x")
        #expect(PlaybackRate.x3.compactDisplayText == "3x")
    }

    @Test("every case has a non-empty display string")
    func allCasesNonEmpty() {
        for rate in PlaybackRate.allCases {
            #expect(!rate.displayText.isEmpty)
            #expect(!rate.compactDisplayText.isEmpty)
        }
    }
}
