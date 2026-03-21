//
//  TestConstants.swift
//  YatteeTests
//
//  Constants for integration tests.
//

import Foundation
@testable import Yattee

/// Constants for integration testing against a real Invidious instance.
enum IntegrationTestConstants {
    /// Test Invidious instance URL (from CLAUDE.md).
    static let testInstanceURL = URL(string: "https://i01.s.yattee.stream")!

    /// Test instance for API calls.
    static let testInstance = Instance(
        type: .invidious,
        url: testInstanceURL,
        name: "Test Instance"
    )

    /// A stable, popular video ID for testing (Rick Astley - Never Gonna Give You Up).
    static let testVideoID = "dQw4w9WgXcQ"

    /// Rick Astley's channel ID.
    static let testChannelID = "UCuAXFkgsw1L7xaCfnd5JJOw"

    /// A popular music playlist ID.
    static let testPlaylistID = "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"

    /// A stable search query.
    static let testSearchQuery = "never gonna give you up"

    /// Timeout for network requests (30 seconds).
    static let networkTimeout: TimeInterval = 30
}
