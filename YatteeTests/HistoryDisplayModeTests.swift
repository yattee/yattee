//
//  HistoryDisplayModeTests.swift
//  YatteeTests
//
//  Tests for whose watch history the history screen shows.
//

import Testing
import Foundation
@testable import Yattee

@Suite("History Display Mode")
struct HistoryDisplayModeTests {

    // MARK: - Helpers

    private static let account = Account(instanceID: UUID())

    private static func capabilities(watchHistory: Bool) -> AccountCapabilities {
        AccountCapabilities(
            supportsSubscriptions: true,
            supportsFeed: true,
            supportsPlaylistReads: true,
            supportsPlaylistWrites: true,
            supportsWatchHistory: watchHistory,
            supportsPlaylistPrivacy: false
        )
    }

    private static func resolve(
        effectiveContext: DataContext,
        account: Account? = account,
        capabilities: AccountCapabilities? = capabilities(watchHistory: true)
    ) -> HistoryDisplayMode {
        HistoryDisplayMode.resolve(
            effectiveContext: effectiveContext,
            account: account,
            capabilities: capabilities
        )
    }

    // MARK: - Local

    @Test("The device's own context shows the local history")
    func localContextShowsLocalHistory() {
        #expect(Self.resolve(effectiveContext: .local, account: nil, capabilities: nil) == .local)
    }

    /// The fallback case: the selected account is unusable, reads have moved to
    /// local, and the history on screen is the device's — with the banner above
    /// it saying why.
    @Test("A context that fell back to local shows the local history")
    func fallbackShowsLocalHistory() {
        #expect(Self.resolve(effectiveContext: .local) == .local)
    }

    /// Piped keeps no server-side history, so its accounts get exactly the
    /// screen they have always had rather than an empty server list.
    @Test("An account whose backend has no history shows the local one")
    func withoutWatchHistorySupportShowsLocalHistory() {
        #expect(
            Self.resolve(
                effectiveContext: .account(Self.account.id),
                capabilities: Self.capabilities(watchHistory: false)
            ) == .local
        )
    }

    @Test("An account whose capabilities are unknown shows the local history")
    func unknownCapabilitiesShowLocalHistory() {
        #expect(Self.resolve(effectiveContext: .account(Self.account.id), capabilities: nil) == .local)
    }

    @Test("An account context that resolves to no account shows the local history")
    func unresolvedAccountShowsLocalHistory() {
        #expect(Self.resolve(effectiveContext: .account(Self.account.id), account: nil) == .local)
    }

    // MARK: - Server

    @Test("An account with watch history shows that account's history")
    func accountContextShowsServerHistory() {
        #expect(Self.resolve(effectiveContext: .account(Self.account.id)) == .server(Self.account))
    }

    // MARK: - Identity

    @Test("Each mode names the store it reads")
    func modeNamesItsStore() {
        #expect(HistoryDisplayMode.local.account == nil)
        #expect(HistoryDisplayMode.local.isLocal)
        #expect(HistoryDisplayMode.server(Self.account).account == Self.account)
        #expect(HistoryDisplayMode.server(Self.account).isLocal == false)
    }
}
