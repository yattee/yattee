//
//  MPVTrackFormatTests.swift
//  YatteeTests
//
//  Tests for MPVTrack sample-rate (kHz) label formatting.
//

import Testing
import Foundation
@testable import Yattee

@Suite("MPVTrack sample-rate formatting")
struct MPVTrackFormatTests {
    @Test("Whole-kHz rates have no decimal")
    func wholeKHz() {
        #expect(MPVTrack.formatSampleRate(8000) == "8 kHz")
        #expect(MPVTrack.formatSampleRate(16000) == "16 kHz")
        #expect(MPVTrack.formatSampleRate(24000) == "24 kHz")
        #expect(MPVTrack.formatSampleRate(48000) == "48 kHz")
        #expect(MPVTrack.formatSampleRate(96000) == "96 kHz")
        #expect(MPVTrack.formatSampleRate(192000) == "192 kHz")
    }

    @Test("44.1 kHz family keeps its decimal (the bug)")
    func fractionalKHz() {
        #expect(MPVTrack.formatSampleRate(44100) == "44.1 kHz")
        #expect(MPVTrack.formatSampleRate(88200) == "88.2 kHz")
        #expect(MPVTrack.formatSampleRate(176400) == "176.4 kHz")
    }

    @Test("Half-decimal rates keep two digits")
    func halfDecimal() {
        #expect(MPVTrack.formatSampleRate(22050) == "22.05 kHz")
        // 11025/1000 = 11.025; %.2f rounds the nearest double to "11.03" on macOS arm64.
        #expect(MPVTrack.formatSampleRate(11025) == "11.03 kHz")
    }

    @Test("detailText surfaces the formatted sample rate")
    func detailTextIntegration() {
        let track = MPVTrack(trackID: 1, type: .audio, codec: "aac",
                             channelCount: 2, sampleRate: 44100)
        #expect(track.detailText == "aac · 2ch · 44.1 kHz")
    }
}
