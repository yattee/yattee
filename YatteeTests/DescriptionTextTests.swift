//
//  DescriptionTextTests.swift
//  YatteeTests
//
//  Unit tests for description-text timestamp parsing.
//

import Testing
import Foundation
@testable import Yattee

@Suite("DescriptionText Timestamp Parsing")
struct DescriptionTextTimestampTests {

    // MARK: - Valid Timestamps

    @Test("Parses M:SS format")
    func parseMSS() {
        #expect(DescriptionText.parseTimestamp("0:00") == 0)
        #expect(DescriptionText.parseTimestamp("5:30") == 330)
    }

    @Test("Parses MM:SS format")
    func parseMMSS() {
        #expect(DescriptionText.parseTimestamp("00:00") == 0)
        #expect(DescriptionText.parseTimestamp("12:45") == 765)
        #expect(DescriptionText.parseTimestamp("59:59") == 3599)
    }

    @Test("Parses H:MM:SS format")
    func parseHMMSS() {
        #expect(DescriptionText.parseTimestamp("1:23:45") == 5025)
        #expect(DescriptionText.parseTimestamp("01:23:45") == 5025)
    }

    @Test("Parses long minutes in MM:SS form")
    func parseLongMinutes() {
        // A 99-minute position is valid for a long video (2-digit minutes).
        #expect(DescriptionText.parseTimestamp("99:59") == 5999)
    }

    // MARK: - Out-of-Range Rejection (regression)

    @Test("Rejects seconds >= 60 in MM:SS form")
    func rejectsInvalidSeconds() {
        // Previously returned components[0]*60 + components[1] = 60 and 159,
        // seeking the player to the wrong position.
        #expect(DescriptionText.parseTimestamp("0:60") == nil)
        #expect(DescriptionText.parseTimestamp("1:99") == nil)
        #expect(DescriptionText.parseTimestamp("5:75") == nil)
    }

    @Test("Rejects minutes or seconds >= 60 in H:MM:SS form")
    func rejectsInvalidHoursMinutesSeconds() {
        #expect(DescriptionText.parseTimestamp("1:99:30") == nil)
        #expect(DescriptionText.parseTimestamp("1:30:60") == nil)
        #expect(DescriptionText.parseTimestamp("2:60:00") == nil)
    }

    // MARK: - Boundary

    @Test("Accepts the 59 boundary in every field")
    func acceptsBoundary() {
        #expect(DescriptionText.parseTimestamp("59:59") == 3599)
        #expect(DescriptionText.parseTimestamp("1:59:59") == 7199)
    }
}
