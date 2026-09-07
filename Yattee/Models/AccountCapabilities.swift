//
//  AccountCapabilities.swift
//  Yattee
//
//  What a given backend lets a signed-in account do.
//

import Foundation

/// What server-side features an account supports.
///
/// Call sites ask for capabilities rather than switching on `instance.type`, so
/// adding a backend — the planned per-user Yattee Server accounts, say — means
/// adding one row in ``InstanceType/accountCapabilities`` instead of hunting
/// down every `case .invidious` in the app.
struct AccountCapabilities: Hashable, Sendable {
    var supportsSubscriptions: Bool
    var supportsFeed: Bool
    var supportsPlaylistReads: Bool
    var supportsPlaylistWrites: Bool
    var supportsWatchHistory: Bool
    /// Whether playlists carry a visibility setting (public/unlisted/private).
    var supportsPlaylistPrivacy: Bool

    static let none = AccountCapabilities(
        supportsSubscriptions: false,
        supportsFeed: false,
        supportsPlaylistReads: false,
        supportsPlaylistWrites: false,
        supportsWatchHistory: false,
        supportsPlaylistPrivacy: false
    )

    /// Whether the backend has accounts at all — true as soon as an account
    /// could do anything on it. This is what decides whether an instance offers
    /// a sign-in; it is deliberately broader than ``isSelectableContext``, which
    /// asks the narrower question of whether an account is worth switching *to*.
    var supportsAccounts: Bool {
        supportsSubscriptions
            || supportsFeed
            || supportsPlaylistReads
            || supportsPlaylistWrites
            || supportsWatchHistory
            || supportsPlaylistPrivacy
    }

    /// Whether this account can act as a `DataContext` at all. An account with
    /// nothing to offer is never listed as a switch target.
    var isSelectableContext: Bool {
        supportsSubscriptions || supportsPlaylistReads
    }
}

extension InstanceType {
    /// **The** capability switch. Verified against each backend's API surface.
    ///
    /// Adding a case here is the whole job of supporting a new account type;
    /// nothing else in the app is allowed to decide what an account can do.
    /// (Routing to the right API client, picking a credential manager and
    /// choosing a presentation still switch on `type` legitimately — those are
    /// about *how* to talk to a server, not what it supports.)
    var accountCapabilities: AccountCapabilities {
        switch self {
        case .invidious:
            // Full CRUD with privacy; removal by a stable per-entry indexId
            // token; history is a boolean watched marker.
            AccountCapabilities(
                supportsSubscriptions: true,
                supportsFeed: true,
                supportsPlaylistReads: true,
                supportsPlaylistWrites: true,
                supportsWatchHistory: true,
                supportsPlaylistPrivacy: true
            )

        case .piped:
            // Full CRUD but no privacy setting, removal is positional, and
            // there is no history endpoint at all.
            AccountCapabilities(
                supportsSubscriptions: true,
                supportsFeed: true,
                supportsPlaylistReads: true,
                supportsPlaylistWrites: true,
                supportsWatchHistory: false,
                supportsPlaylistPrivacy: false
            )

        case .peertube:
            // Yattee has no PeerTube account concept — instances are browsed
            // anonymously.
            .none

        case .yatteeServer:
            // Stateless today: the client posts its own subscription list and
            // gets a merged feed back, with HTTP Basic as the only auth. Per-user
            // accounts are planned server-side; this row is where they land.
            .none
        }
    }
}
