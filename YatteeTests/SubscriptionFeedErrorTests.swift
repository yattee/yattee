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

    // MARK: - Asking again on a timer

    @Test("A network failure keeps trying whatever the context is doing")
    func networkErrorAlwaysRetries() {
        let state = FeedLoadState.error(.networkError("The request timed out."))
        let reasons: [DataContextUnavailability?] = [
            nil, .checking, .instancePending, .instanceDisabled,
            .credentialMissing, .credentialRejected, .unreachable
        ]

        for reason in reasons {
            #expect(state.warrantsPeriodicRetry(unavailability: reason))
        }
    }

    @Test("The Yattee Server the unreachable fallback asks for is worth asking again")
    func yatteeServerRequiredRetriesWhileUnreachable() {
        let state = FeedLoadState.error(.yatteeServerRequired)

        #expect(state.warrantsPeriodicRetry(unavailability: .unreachable))
    }

    @Test("A context that genuinely needs a Yattee Server never starts a timer")
    func yatteeServerRequiredDoesNotRetryOtherwise() {
        let state = FeedLoadState.error(.yatteeServerRequired)
        // `nil` is local data the user selected: the request is the real answer.
        // The rest lift through changes this view already reloads on, and none
        // of them is the silent status expiry the retry exists for.
        let reasons: [DataContextUnavailability?] = [
            nil, .checking, .instancePending, .instanceDisabled,
            .credentialMissing, .credentialRejected
        ]

        for reason in reasons {
            #expect(!state.warrantsPeriodicRetry(unavailability: reason))
        }
    }

    @Test("An account error is not answered by asking the feed again")
    func notAuthenticatedNeverRetries() {
        let state = FeedLoadState.error(.notAuthenticated)

        #expect(!state.warrantsPeriodicRetry(unavailability: .unreachable))
        #expect(!state.warrantsPeriodicRetry(unavailability: .credentialRejected))
        #expect(!state.warrantsPeriodicRetry(unavailability: nil))
    }

    @Test("A feed that is not sitting on an error has nothing to retry")
    func nonErrorStatesNeverRetry() {
        let states: [FeedLoadState] = [
            .idle,
            .loading,
            .loadingMore,
            .ready,
            .partiallyLoaded(readyCount: 1, pendingCount: 2, errorCount: 0)
        ]

        for state in states {
            #expect(!state.warrantsPeriodicRetry(unavailability: nil))
            #expect(!state.warrantsPeriodicRetry(unavailability: .unreachable))
        }
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
