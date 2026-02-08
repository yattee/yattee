//
//  SettingsTests.swift
//  YatteeTests
//
//  Tests for settings and preferences types.
//

import Testing
import Foundation
import SwiftUI
@testable import Yattee

// MARK: - AppTheme Tests

@Suite("AppTheme Tests")
@MainActor
struct AppThemeTests {

    @Test("AppTheme cases")
    func allCases() {
        let cases = AppTheme.allCases
        #expect(cases.contains(.system))
        #expect(cases.contains(.light))
        #expect(cases.contains(.dark))
    }

    @Test("AppTheme colorScheme mapping")
    func colorSchemeMapping() {
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.dark.colorScheme == .dark)
    }

    @Test("AppTheme is Codable")
    func codable() throws {
        for theme in AppTheme.allCases {
            let encoded = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(AppTheme.self, from: encoded)
            #expect(theme == decoded)
        }
    }
}

// MARK: - AccentColor Tests

@Suite("AccentColor Tests")
@MainActor
struct AccentColorTests {

    @Test("AccentColor cases")
    func allCases() {
        let cases = AccentColor.allCases
        #expect(cases.contains(.default))
        #expect(cases.contains(.red))
        #expect(cases.contains(.blue))
        #expect(cases.contains(.green))
        #expect(cases.contains(.purple))
    }

    @Test("AccentColor is Codable")
    func codable() throws {
        for color in AccentColor.allCases {
            let encoded = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(AccentColor.self, from: encoded)
            #expect(color == decoded)
        }
    }
}

// MARK: - VideoQuality Tests

@Suite("VideoQuality Tests")
@MainActor
struct VideoQualityTests {

    @Test("VideoQuality cases")
    func allCases() {
        let cases = VideoQuality.allCases
        #expect(cases.contains(.auto))
        #expect(cases.contains(.hd4k))
        #expect(cases.contains(.hd1440p))
        #expect(cases.contains(.hd1080p))
        #expect(cases.contains(.hd720p))
        #expect(cases.contains(.sd480p))
        #expect(cases.contains(.sd360p))
    }

    @Test("VideoQuality raw values")
    func rawValues() {
        #expect(VideoQuality.auto.rawValue == "auto")
        #expect(VideoQuality.hd4k.rawValue == "4k")
        #expect(VideoQuality.hd1440p.rawValue == "1440p")
        #expect(VideoQuality.hd1080p.rawValue == "1080p")
    }

    @Test("VideoQuality recommendedForPlatform returns valid quality")
    func recommendedForPlatform() {
        let recommended = VideoQuality.recommendedForPlatform
        #expect(VideoQuality.allCases.contains(recommended))
    }

    @Test("VideoQuality is Codable")
    func codable() throws {
        for quality in VideoQuality.allCases {
            let encoded = try JSONEncoder().encode(quality)
            let decoded = try JSONDecoder().decode(VideoQuality.self, from: encoded)
            #expect(quality == decoded)
        }
    }
}

// MARK: - SponsorBlockCategory Tests

@Suite("SponsorBlockCategory Tests")
@MainActor
struct SponsorBlockCategoryTests {

    @Test("SponsorBlockCategory cases")
    func allCases() {
        let cases = SponsorBlockCategory.allCases
        #expect(cases.contains(.sponsor))
        #expect(cases.contains(.selfpromo))
        #expect(cases.contains(.interaction))
        #expect(cases.contains(.intro))
        #expect(cases.contains(.outro))
        #expect(cases.contains(.preview))
        #expect(cases.contains(.musicOfftopic))
        #expect(cases.contains(.filler))
        #expect(cases.contains(.highlight))
    }

    @Test("SponsorBlockCategory display names are not empty")
    func displayNames() {
        // Display names use localized strings, so we just verify they're not empty
        for category in SponsorBlockCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }

    @Test("SponsorBlockCategory raw values")
    func rawValues() {
        #expect(SponsorBlockCategory.sponsor.rawValue == "sponsor")
        #expect(SponsorBlockCategory.musicOfftopic.rawValue == "music_offtopic")
    }

    @Test("SponsorBlockCategory defaultEnabled set")
    func defaultEnabled() {
        let defaults = SponsorBlockCategory.defaultEnabled
        #expect(defaults.contains(.sponsor))
        #expect(defaults.contains(.selfpromo))
        #expect(defaults.contains(.interaction))
        #expect(defaults.contains(.intro))
        #expect(defaults.contains(.outro))
        #expect(!defaults.contains(.preview))
        #expect(!defaults.contains(.musicOfftopic))
        #expect(!defaults.contains(.filler))
    }

    @Test("SponsorBlockCategory is Codable")
    func codable() throws {
        for category in SponsorBlockCategory.allCases {
            let encoded = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(SponsorBlockCategory.self, from: encoded)
            #expect(category == decoded)
        }
    }

    @Test("SponsorBlockCategory Set is Codable")
    func setCodable() throws {
        let categories: Set<SponsorBlockCategory> = [.sponsor, .intro, .outro]
        let encoded = try JSONEncoder().encode(categories)
        let decoded = try JSONDecoder().decode(Set<SponsorBlockCategory>.self, from: encoded)
        #expect(categories == decoded)
    }
}

// MARK: - MacPlayerMode Tests (macOS only)

#if os(macOS)
@Suite("MacPlayerMode Tests")
@MainActor
struct MacPlayerModeTests {

    @Test("MacPlayerMode cases")
    func allCases() {
        let cases = MacPlayerMode.allCases
        #expect(cases.contains(.window))
        #expect(cases.contains(.inline))
    }

    @Test("MacPlayerMode display names")
    func displayNames() {
        #expect(MacPlayerMode.window.displayName == "Separate Window")
        #expect(MacPlayerMode.floatingWindow.displayName == "Floating Window")
        #expect(MacPlayerMode.inline.displayName == "Inline (Sheet)")
    }

    @Test("MacPlayerMode is Codable")
    func codable() throws {
        for mode in MacPlayerMode.allCases {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(MacPlayerMode.self, from: encoded)
            #expect(mode == decoded)
        }
    }
}
#endif

// MARK: - UserAgentGenerator Tests

@Suite("UserAgentGenerator Tests")
struct UserAgentGeneratorTests {

    @Test("Random user agent is not empty")
    func randomNotEmpty() {
        let ua = UserAgentGenerator.generateRandom()
        #expect(!ua.isEmpty)
    }

    @Test("Random user agent starts with Mozilla")
    func randomStartsWithMozilla() {
        for _ in 0..<10 {
            let ua = UserAgentGenerator.generateRandom()
            #expect(ua.hasPrefix("Mozilla/5.0"))
        }
    }

    @Test("Random user agent contains browser identifier")
    func randomContainsBrowser() {
        // Run multiple times to test randomness
        var containsChrome = false
        var containsFirefox = false
        var containsSafari = false
        var containsEdge = false

        for _ in 0..<100 {
            let ua = UserAgentGenerator.generateRandom()
            if ua.contains("Chrome/") { containsChrome = true }
            if ua.contains("Firefox/") { containsFirefox = true }
            if ua.contains("Safari/") { containsSafari = true }
            if ua.contains("Edg/") { containsEdge = true }
        }

        // At least some browser types should appear (probabilistic)
        #expect(containsChrome || containsFirefox || containsSafari || containsEdge)
    }

    @Test("Default user agent is valid")
    func defaultUserAgent() {
        let ua = UserAgentGenerator.defaultUserAgent
        #expect(!ua.isEmpty)
        #expect(ua.hasPrefix("Mozilla/5.0"))
    }

    @Test("Random user agent has reasonable length")
    func reasonableLength() {
        for _ in 0..<10 {
            let ua = UserAgentGenerator.generateRandom()
            // User agents are typically 80-200 characters
            #expect(ua.count > 50)
            #expect(ua.count < 300)
        }
    }

    @Test("Random user agent contains platform info")
    func containsPlatformInfo() {
        for _ in 0..<20 {
            let ua = UserAgentGenerator.generateRandom()
            // Should contain Windows, Macintosh, or similar
            let containsPlatform = ua.contains("Windows") || ua.contains("Macintosh") || ua.contains("Intel Mac")
            #expect(containsPlatform)
        }
    }
}

