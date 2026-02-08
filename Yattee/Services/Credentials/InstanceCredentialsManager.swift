//
//  InstanceCredentialsManager.swift
//  Yattee
//
//  Protocol defining the common interface for instance-specific credentials management.
//  Both InvidiousCredentialsManager and PipedCredentialsManager conform to this protocol.
//

import Foundation

/// Protocol for instance-specific credentials management.
/// Provides a unified interface for storing and retrieving authentication credentials
/// across different instance types (Invidious, Piped, etc.).
@MainActor
protocol InstanceCredentialsManager: AnyObject, Observable {
    /// Set of instance IDs that are currently logged in.
    /// Used for reactive UI updates when login state changes.
    var loggedInInstanceIDs: Set<UUID> { get }

    /// Stores a credential (SID for Invidious, token for Piped) for an instance.
    /// - Parameters:
    ///   - credential: The credential value to store
    ///   - instance: The instance to associate the credential with
    func setCredential(_ credential: String, for instance: Instance)

    /// Retrieves the stored credential for an instance.
    /// - Parameter instance: The instance to retrieve the credential for
    /// - Returns: The stored credential, or nil if not logged in
    func credential(for instance: Instance) -> String?

    /// Deletes the stored credential for an instance (logout).
    /// - Parameter instance: The instance to log out from
    func deleteCredential(for instance: Instance)

    /// Checks if an instance has a stored credential.
    /// - Parameter instance: The instance to check
    /// - Returns: true if logged in, false otherwise
    func isLoggedIn(for instance: Instance) -> Bool

    /// Refreshes the login status for an instance from the Keychain.
    /// Call this when a view appears to ensure UI is in sync with stored state.
    /// - Parameter instance: The instance to refresh status for
    func refreshLoginStatus(for instance: Instance)
}
