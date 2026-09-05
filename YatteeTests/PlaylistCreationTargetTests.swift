//
//  PlaylistCreationTargetTests.swift
//  YatteeTests
//
//  Tests for where a newly created playlist is sent.
//

import Testing
import Foundation
@testable import Yattee

@Suite("Playlist Creation Target")
struct PlaylistCreationTargetTests {

    // MARK: - Helpers

    private static let account = Account(instanceID: UUID())

    private static func capabilities(playlistWrites: Bool) -> AccountCapabilities {
        AccountCapabilities(
            supportsSubscriptions: true,
            supportsFeed: true,
            supportsPlaylistReads: true,
            supportsPlaylistWrites: playlistWrites,
            supportsWatchHistory: false,
            supportsPlaylistPrivacy: false
        )
    }

    private static func resolve(
        effectiveContext: DataContext,
        account: Account? = account,
        allowsServerMutations: Bool = true,
        capabilities: AccountCapabilities? = capabilities(playlistWrites: true)
    ) -> PlaylistCreationTarget? {
        PlaylistCreationTarget.resolve(
            effectiveContext: effectiveContext,
            account: account,
            allowsServerMutations: allowsServerMutations,
            capabilities: capabilities
        )
    }

    // MARK: - Local

    @Test("The device's own context creates locally")
    func localContextCreatesLocally() {
        #expect(Self.resolve(effectiveContext: .local, account: nil) == .local)
    }

    /// The fallback case: the selected account is unusable, reads have moved to
    /// local, and the rows on screen are local — so a creation is local too.
    @Test("A context that fell back to local creates locally")
    func fallbackCreatesLocally() {
        #expect(
            Self.resolve(
                effectiveContext: .local,
                account: nil,
                allowsServerMutations: false,
                capabilities: nil
            ) == .local
        )
    }

    // MARK: - Account

    @Test("An account context creates on that account")
    func accountContextCreatesOnAccount() {
        #expect(Self.resolve(effectiveContext: .account(Self.account.id)) == .account(Self.account))
    }

    /// The defect this exists to prevent: an account context must never quietly
    /// become a local write.
    @Test("An account that may not be written to creates nowhere")
    func mutationsDisallowedCreatesNowhere() {
        #expect(Self.resolve(effectiveContext: .account(Self.account.id), allowsServerMutations: false) == nil)
    }

    @Test("A backend without playlist writes creates nowhere")
    func withoutPlaylistWritesCreatesNowhere() {
        #expect(
            Self.resolve(
                effectiveContext: .account(Self.account.id),
                capabilities: Self.capabilities(playlistWrites: false)
            ) == nil
        )
    }

    @Test("An account whose capabilities are unknown creates nowhere")
    func unknownCapabilitiesCreateNowhere() {
        #expect(Self.resolve(effectiveContext: .account(Self.account.id), capabilities: nil) == nil)
    }

    @Test("An account context that resolves to no account creates nowhere")
    func unresolvedAccountCreatesNowhere() {
        #expect(Self.resolve(effectiveContext: .account(Self.account.id), account: nil) == nil)
    }

    // MARK: - Identity

    @Test("Each destination presents as itself")
    func identityDistinguishesDestinations() {
        #expect(PlaylistCreationTarget.local.id != PlaylistCreationTarget.account(Self.account).id)
        #expect(PlaylistCreationTarget.account(Self.account).account == Self.account)
        #expect(PlaylistCreationTarget.local.account == nil)
    }
}
