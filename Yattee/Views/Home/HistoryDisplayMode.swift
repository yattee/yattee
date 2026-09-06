//
//  HistoryDisplayMode.swift
//  Yattee
//
//  Whose watch history the history screen is showing.
//

import Foundation

/// Which history the screen reads — the device's own, or an account's.
///
/// A value rather than a scattering of checks, so the list, the row actions and
/// the clear menu can never disagree about which store they are looking at: the
/// rows come from one of them, and a deletion goes to the same one.
enum HistoryDisplayMode: Equatable {
    /// The device's own ``WatchEntry`` store.
    case local
    /// The server-side history of this account.
    case server(Account)

    /// The account whose history is on screen, or `nil` when it is the device's.
    var account: Account? {
        switch self {
        case .local: nil
        case let .server(account): account
        }
    }

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    /// Which history a screen opened right now would show.
    ///
    /// Follows the *effective* context, so a selected account that cannot be
    /// used falls back to the local list — with the banner above it saying why —
    /// rather than to an empty server list nobody can explain.
    ///
    /// An account whose backend has no history to read is local too, and
    /// deliberately so: Piped stores watch history on the device only, so the
    /// screen there is the same screen it has always been rather than a feature
    /// that appears to be missing.
    ///
    /// - Parameters:
    ///   - account: the account `effectiveContext` names, when it resolves.
    ///   - capabilities: what that account's backend can do.
    static func resolve(
        effectiveContext: DataContext,
        account: Account?,
        capabilities: AccountCapabilities?
    ) -> HistoryDisplayMode {
        switch effectiveContext {
        case .local:
            return .local

        case .account:
            guard let account, capabilities?.supportsWatchHistory == true else { return .local }
            return .server(account)
        }
    }
}
