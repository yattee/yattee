//
//  PlaylistCreationTarget.swift
//  Yattee
//
//  Where a newly created playlist goes.
//

import Foundation

/// Where the playlists screen would put a playlist it is asked to create.
///
/// Kept as a value rather than left to be re-derived at save time: a creation
/// travels with the sheet that collects it, so the destination cannot move
/// while the form is open — and cannot be read one update late, which is how a
/// creation on an account ended up in local data with its visibility picker
/// missing.
enum PlaylistCreationTarget: Identifiable, Equatable {
    /// The device's own playlists.
    case local
    /// A server-side playlist on this account.
    case account(Account)

    var id: String {
        switch self {
        case .local: "local"
        case let .account(account): account.id.uuidString
        }
    }

    /// The account to create on, or `nil` when the device is the destination.
    var account: Account? {
        switch self {
        case .local: nil
        case let .account(account): account
        }
    }

    /// Where a creation started right now would go, or `nil` when there is
    /// nowhere to put one and the affordance must not be offered.
    ///
    /// Follows the *effective* context, which is what the rows on screen came
    /// from: a selected account that cannot be used falls back to local reads,
    /// and creating locally is then the same answer the list is already giving
    /// — with the banner above it saying why. What never happens is the other
    /// direction: an account context whose server cannot be written to right
    /// now creates nothing at all, rather than quietly retargeting the write at
    /// local data the user did not choose.
    ///
    /// - Parameters:
    ///   - account: the account `effectiveContext` names, when it resolves.
    ///   - allowsServerMutations: the validator's write gate.
    ///   - capabilities: what that account's backend can do.
    static func resolve(
        effectiveContext: DataContext,
        account: Account?,
        allowsServerMutations: Bool,
        capabilities: AccountCapabilities?
    ) -> PlaylistCreationTarget? {
        switch effectiveContext {
        case .local:
            return .local

        case .account:
            guard let account,
                  allowsServerMutations,
                  capabilities?.supportsPlaylistWrites == true
            else { return nil }

            return .account(account)
        }
    }
}
