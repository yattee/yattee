//
//  SubscriptionFeedErrorTests.swift
//  YatteeTests
//
//  Tests for which feed errors the context banner speaks for.
//

import Testing
import Foundation
@testable import Yattee

@Suite("Subscription Feed Error Display")
struct SubscriptionFeedErrorTests {

    // MARK: - Without a banner

    @Test("Every feed error shows when no banner is up")
    func everyErrorShowsWithoutBanner() {
        let errors: [FeedLoadState.FeedLoadError] = [
            .yatteeServerRequired,
            .notAuthenticated,
            .networkError("The Internet connection appears to be offline.")
        ]

        for error in errors {
            #expect(FeedLoadState.error(error).displayedError(contextBannerVisible: false) == error)
        }
    }

    // MARK: - Under the banner

    @Test("The Yattee Server the fallback asks for stands down under the banner")
    func yatteeServerRequiredStandsDownUnderBanner() {
        let state = FeedLoadState.error(.yatteeServerRequired)

        #expect(state.displayedError(contextBannerVisible: true) == nil)
    }

    @Test("An account error stands down under the banner")
    func notAuthenticatedStandsDownUnderBanner() {
        let state = FeedLoadState.error(.notAuthenticated)

        #expect(state.displayedError(contextBannerVisible: true) == nil)
    }

    @Test("A failed refresh keeps its error under the banner")
    func networkErrorSurvivesTheBanner() {
        let state = FeedLoadState.error(.networkError("The Internet connection appears to be offline."))

        #expect(
            state.displayedError(contextBannerVisible: true)
                == .networkError("The Internet connection appears to be offline.")
        )
    }

    // MARK: - Other states

    @Test("States that are not errors have nothing to show")
    func nonErrorStatesShowNothing() {
        let states: [FeedLoadState] = [
            .idle,
            .loading,
            .loadingMore,
            .ready,
            .partiallyLoaded(readyCount: 1, pendingCount: 2, errorCount: 0)
        ]

        for state in states {
            #expect(state.displayedError(contextBannerVisible: false) == nil)
            #expect(state.displayedError(contextBannerVisible: true) == nil)
        }
    }
}
