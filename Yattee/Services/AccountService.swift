//
//  AccountService.swift
//  Yattee
//
//  The account-first facade for server-side playlists: everything a view needs
//  to read or change a playlist that lives on an instance, addressed by the
//  account it belongs to rather than by an instance and a secret.
//

import Foundation

/// The authenticated playlist surface ``AccountService`` talks to.
///
/// Exists so the service can be exercised without a server: `ContentService`
/// conforms to it, and tests script it. Deliberately stateless and
/// credential-carrying — resolving *which* credential is this service's job,
/// and the transport must never guess.
///
/// **Every method here is exactly one request to the server.** Nothing composes
/// two of them, because the credential can be replaced between any two requests
/// and only this service can tell: a composite that awaited its own first call
/// would send the second with a secret that has since changed hands. Backends
/// that need several writes to change one playlist are sequenced above, with a
/// recheck between each pair.
protocol RemotePlaylistTransport: Sendable {
    func userPlaylists(instance: Instance, credential: String) async throws -> [Playlist]

    func userPlaylistSnapshot(
        id: String,
        instance: Instance,
        credential: String
    ) async throws -> RemotePlaylistSnapshot

    func createPlaylist(
        title: String,
        privacy: PlaylistPrivacy?,
        instance: Instance,
        credential: String
    ) async throws -> Playlist

    func renamePlaylist(
        id: String,
        title: String,
        privacy: PlaylistPrivacy?,
        instance: Instance,
        credential: String
    ) async throws

    func setPlaylistDescription(
        id: String,
        description: String,
        title: String,
        instance: Instance,
        credential: String
    ) async throws

    func deletePlaylist(id: String, instance: Instance, credential: String) async throws

    func addVideoToPlaylist(
        playlistID: String,
        videoID: String,
        instance: Instance,
        credential: String
    ) async throws

    func removeEntry(_ entryID: RemotePlaylistEntryID, instance: Instance, credential: String) async throws
}

/// Why an account could not do what was asked of it.
enum AccountServiceError: Error, LocalizedError, Equatable, Sendable {
    /// No credential is readable for this account right now.
    case notAuthenticated

    /// The account's instance is unknown or switched off.
    case instanceNotConfigured

    /// The backend has no such feature.
    case notSupported

    /// The row that was going to be removed is no longer the row it was.
    case entryMismatch

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return String(localized: "accounts.playlists.error.notAuthenticated")
        case .instanceNotConfigured:
            return String(localized: "accounts.playlists.error.instanceNotConfigured")
        case .notSupported:
            return String(localized: "accounts.playlists.error.notSupported")
        case .entryMismatch:
            return String(localized: "accounts.playlists.error.entryMismatch")
        }
    }
}

/// Reads and changes the playlists an account has on its instance.
///
/// Views hand it an ``Account`` and nothing else. It resolves the instance and
/// the credential, refuses what the backend cannot do, and records what every
/// answer implies about the login — which is what eventually marks an account
/// as rejected, and what stops it being marked by somebody else's failure.
///
/// Nothing is cached here. ``RemotePlaylistsCache`` is what holds results, and
/// it is the layer that refetches after a change.
@MainActor
final class AccountService {
    /// The credential an account currently holds, or `nil` when there is none
    /// to be read — including while the identity scope is unresolved, which is
    /// "cannot tell yet" rather than "signed out".
    typealias CredentialReader = @MainActor (Account) -> String?

    private let accountsManager: AccountsManager
    private let credentialReader: CredentialReader
    private let transport: any RemotePlaylistTransport

    init(
        accountsManager: AccountsManager,
        credentialReader: @escaping CredentialReader,
        transport: any RemotePlaylistTransport
    ) {
        self.accountsManager = accountsManager
        self.credentialReader = credentialReader
        self.transport = transport
    }

    // MARK: - Reads

    /// The playlists this account has on its instance.
    func userPlaylists(for account: Account) async throws -> [Playlist] {
        let (instance, credential) = try resolve(account, requiring: \.supportsPlaylistReads)
        return try await tracking(account, credential: credential) {
            try await transport.userPlaylists(instance: instance, credential: credential)
        }
    }

    /// One playlist, together with the identities its rows can be removed by.
    func playlistSnapshot(id: String, for account: Account) async throws -> RemotePlaylistSnapshot {
        let (instance, credential) = try resolve(account, requiring: \.supportsPlaylistReads)
        return try await tracking(account, credential: credential) {
            try await transport.userPlaylistSnapshot(id: id, instance: instance, credential: credential)
        }
    }

    // MARK: - Writes

    /// Creates a playlist on the account's instance.
    ///
    /// Two requests when a description was asked for, because no backend takes
    /// one at creation — and the credential is checked again in between, since
    /// it can be replaced while the first one is out. The second request's
    /// failure is the caller's to see: a playlist that exists with the wrong
    /// description is not a silent success.
    ///
    /// - Parameter privacy: dropped on backends without a visibility concept,
    ///   rather than refused: the playlist is still perfectly creatable there,
    ///   and failing the whole call over a setting the server does not have
    ///   would be a worse answer than making it.
    func createPlaylist(
        title: String,
        description: String?,
        privacy: PlaylistPrivacy?,
        for account: Account
    ) async throws -> Playlist {
        let (instance, credential) = try resolve(account, requiring: \.supportsPlaylistWrites)
        let privacy = supportedPrivacy(privacy, for: account)

        try requireStillCurrent(credential, for: account)
        let playlist = try await tracking(account, credential: credential) {
            try await transport.createPlaylist(
                title: title,
                privacy: privacy,
                instance: instance,
                credential: credential
            )
        }

        if let description, !description.isEmpty {
            try requireStillCurrent(credential, for: account)
            try await tracking(account, credential: credential) {
                try await transport.setPlaylistDescription(
                    id: playlist.id.playlistID,
                    description: description,
                    title: title,
                    instance: instance,
                    credential: credential
                )
            }
        }

        return playlist
    }

    /// Edits a playlist on the account's instance.
    ///
    /// Two requests, no transaction, when the description is part of the edit:
    /// Piped stores the name and the description behind separate endpoints, and
    /// Invidious refuses to take a description without a title. The rename goes
    /// first so a failure of the second leaves the visible half applied, and the
    /// caller's refetch shows exactly what landed — with the credential checked
    /// again in between, because it can be replaced while the rename is out.
    ///
    /// - Parameters:
    ///   - description: `nil` leaves whatever the playlist has.
    ///   - privacy: `nil` leaves whatever visibility the playlist has; ignored
    ///     entirely on backends without one.
    func updatePlaylist(
        id: String,
        title: String,
        description: String?,
        privacy: PlaylistPrivacy?,
        for account: Account
    ) async throws {
        let (instance, credential) = try resolve(account, requiring: \.supportsPlaylistWrites)
        let privacy = supportedPrivacy(privacy, for: account)

        try requireStillCurrent(credential, for: account)
        try await tracking(account, credential: credential) {
            try await transport.renamePlaylist(
                id: id,
                title: title,
                privacy: privacy,
                instance: instance,
                credential: credential
            )
        }

        if let description {
            try requireStillCurrent(credential, for: account)
            try await tracking(account, credential: credential) {
                try await transport.setPlaylistDescription(
                    id: id,
                    description: description,
                    title: title,
                    instance: instance,
                    credential: credential
                )
            }
        }
    }

    /// Deletes a playlist from the account's instance.
    func deletePlaylist(id: String, for account: Account) async throws {
        let (instance, credential) = try resolve(account, requiring: \.supportsPlaylistWrites)

        try requireStillCurrent(credential, for: account)
        try await tracking(account, credential: credential) {
            try await transport.deletePlaylist(id: id, instance: instance, credential: credential)
        }
    }

    /// Appends a video to one of the account's playlists.
    func addVideo(videoID: String, toPlaylist id: String, for account: Account) async throws {
        let (instance, credential) = try resolve(account, requiring: \.supportsPlaylistWrites)

        try requireStillCurrent(credential, for: account)
        try await tracking(account, credential: credential) {
            try await transport.addVideoToPlaylist(
                playlistID: id,
                videoID: videoID,
                instance: instance,
                credential: credential
            )
        }
    }

    /// Removes one row from one of the account's playlists.
    ///
    /// A Piped entry names a *position*, and the playlist may have moved since
    /// the snapshot that minted it — so the playlist is refetched and the
    /// position checked to still hold the same video before anything is
    /// removed. That narrows the window; it cannot close it. Between the check
    /// and the removal the playlist can still change, and only the caller's
    /// refetch afterwards can show what actually happened. Invidious needs none
    /// of this: its `indexId` names the row itself, whatever moved around it.
    ///
    /// The preflight is also where the credential can change out from under the
    /// removal — it is the one place here that awaits a server before writing —
    /// so the credential is read again before the removal is sent.
    func removeEntry(
        _ entry: RemotePlaylistEntry,
        fromPlaylist id: String,
        for account: Account
    ) async throws {
        let (instance, credential) = try resolve(account, requiring: \.supportsPlaylistWrites)

        switch entry.id {
        case .invidious(let playlistID, _):
            guard playlistID == id else { throw AccountServiceError.entryMismatch }

        case .piped(let playlistID, let position):
            guard playlistID == id else { throw AccountServiceError.entryMismatch }

            let snapshot = try await tracking(account, credential: credential) {
                try await transport.userPlaylistSnapshot(id: id, instance: instance, credential: credential)
            }

            guard let current = snapshot.entries.first(where: { $0.position == position }),
                  current.video.id.videoID == entry.video.id.videoID
            else {
                throw AccountServiceError.entryMismatch
            }
        }

        try requireStillCurrent(credential, for: account)
        try await tracking(account, credential: credential) {
            try await transport.removeEntry(entry.id, instance: instance, credential: credential)
        }
    }

    // MARK: - Resolution

    /// The instance and credential to talk to on this account's behalf, once
    /// the backend has been confirmed to support the operation.
    private func resolve(
        _ account: Account,
        requiring capability: KeyPath<AccountCapabilities, Bool>
    ) throws -> (Instance, String) {
        // The account names its instance directly — never "some enabled
        // instance of the right type", which could send one account's request
        // to a server it has no credential for.
        guard let instance = accountsManager.instance(for: account), instance.isEnabled else {
            throw AccountServiceError.instanceNotConfigured
        }

        // Capabilities are the one place that decides what a backend can do; no
        // caller here switches on the instance type to find out.
        guard let capabilities = accountsManager.capabilities(for: account) else {
            throw AccountServiceError.instanceNotConfigured
        }

        guard capabilities[keyPath: capability] else {
            throw AccountServiceError.notSupported
        }

        guard let credential = credentialReader(account) else {
            throw AccountServiceError.notAuthenticated
        }

        return (instance, credential)
    }

    /// Refuses to send a write with a credential that is no longer the
    /// account's.
    ///
    /// Resolving a credential and sending the request are not the same instant:
    /// a sign-out and a sign-in as somebody else can both happen in between —
    /// Piped's removals in particular await a whole playlist fetch first. A
    /// stale *read* is merely wasted; a stale *write* changes the previous
    /// user's data, so every mutation checks again immediately before it goes.
    private func requireStillCurrent(_ credential: String, for account: Account) throws {
        guard credentialReader(account) == credential else {
            throw AccountServiceError.notAuthenticated
        }
    }

    /// The privacy to send, or `nil` where the backend has no such setting.
    private func supportedPrivacy(_ privacy: PlaylistPrivacy?, for account: Account) -> PlaylistPrivacy? {
        guard accountsManager.capabilities(for: account)?.supportsPlaylistPrivacy == true else { return nil }
        return privacy
    }

    // MARK: - Outcome tracking

    /// Runs a server call and records what it implies about the credential.
    private func tracking<T>(
        _ account: Account,
        credential: String,
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            let value = try await operation()
            recordOutcome(nil, for: account, credential: credential)
            return value
        } catch {
            recordOutcome(error, for: account, credential: credential)
            throw error
        }
    }

    /// Records an outcome against the account, but only for the secret the
    /// request actually used.
    ///
    /// Signing in again — or a switch of Apple account — replaces the
    /// credential under the same key while a request is still out, and a late
    /// 401 would otherwise reject the replacement, or a late success clear a
    /// rejection it never earned.
    private func recordOutcome(_ error: Error?, for account: Account, credential: String) {
        guard let current = accountsManager.account(id: account.id),
              credentialReader(current) == credential
        else { return }

        accountsManager.recordServerOutcome(error, for: current)
    }
}
