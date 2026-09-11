//
//  RemotePlaylistsCache.swift
//  Yattee
//
//  What the server said about an account's playlists, the last time it was
//  asked. In memory, for this run of the app, and nowhere else.
//

import Foundation
import Observation

/// Holds server-side playlists for display, and routes every change to them.
///
/// **Never persisted, and never synced.** Two reasons, both fatal to the idea
/// of writing this to disk or into CloudKit: the data belongs to a login rather
/// than to this device, and Piped's rows are addressed by *position*, so a
/// stored entry id would be aimed at whatever occupies that slot the next time
/// the app opens. Offline the last fetch is shown and writes fail fast.
///
/// Mutations go through here rather than around it, so the refetch that
/// reconciles them cannot be forgotten: every change refetches what it touched
/// — on failure as much as on success, because a failed write may still have
/// landed — and the UI only ever shows what came back from the server. Nothing
/// is edited optimistically.
@MainActor
@Observable
final class RemotePlaylistsCache {
    private let accountService: AccountService

    init(accountService: AccountService) {
        self.accountService = accountService
    }

    // MARK: - State

    /// Last-fetched playlist lists, by account.
    private var lists: [UUID: [Playlist]] = [:]

    /// When each account's list was last fetched.
    private var listFetchDates: [UUID: Date] = [:]

    /// Last-fetched playlist snapshots, by account and playlist id.
    private var snapshots: [UUID: [String: RemotePlaylistSnapshot]] = [:]

    /// When each snapshot was last fetched.
    private var snapshotFetchDates: [UUID: [String: Date]] = [:]

    /// Which generation of an account's data the state belongs to.
    ///
    /// Clearing a cache never cancels the request that was filling it: a fetch
    /// started before a sign-out returns afterwards, and would repopulate the
    /// account it was cleared for. Every fetch captures this at the start and
    /// drops its result if it has moved.
    private var generations: [UUID: Int] = [:]

    /// In-flight list fetches, so concurrent refreshes of the same account cost
    /// one round trip and all see the same answer.
    private var listFetches: [UUID: Task<Void, Error>] = [:]

    /// In-flight snapshot fetches, keyed by account and playlist.
    private var snapshotFetches: [SnapshotKey: Task<Void, Error>] = [:]

    /// Ordering for results, so an older fetch can never overwrite a newer one.
    ///
    /// A refresh already in flight when a mutation happens describes the
    /// playlist *before* the change; the reconciling refetch starts later and
    /// must win however the two happen to return.
    private var sequence = 0
    private var appliedListSequence: [UUID: Int] = [:]
    private var appliedSnapshotSequence: [SnapshotKey: Int] = [:]

    private struct SnapshotKey: Hashable {
        let accountID: UUID
        let playlistID: String
    }

    /// What a mutation holds while it runs, so two of them cannot overlap.
    ///
    /// A change and the refetch that reconciles it are one operation, and the
    /// next change to the same playlist may not start until it is over: it
    /// plans its write against the last snapshot, and a snapshot taken before
    /// the previous change landed describes a playlist that no longer exists.
    /// Piped is where this bites — its rows are addressed by *position*, so a
    /// second removal that preflights the pre-removal snapshot passes its check
    /// and then deletes whatever shifted into the slot.
    ///
    /// Creation queues on the account's *list* instead, and deliberately not
    /// with the playlists: nothing it does depends on any playlist's contents,
    /// and the list refetches that two mutations race over are already ordered
    /// by `sequence`. One queue for the account would only make changes to
    /// unrelated playlists wait for each other.
    private enum MutationKey: Hashable {
        case list(accountID: UUID)
        case playlist(accountID: UUID, playlistID: String)
    }

    /// Who is queued behind each held key, in the order they arrived. A key
    /// present is held; absent is free.
    private var mutationWaiters: [MutationKey: [CheckedContinuation<Void, Never>]] = [:]

    // MARK: - Reads

    /// The account's playlists as last fetched, or `nil` if they never were.
    func playlists(for accountID: UUID) -> [Playlist]? {
        lists[accountID]
    }

    /// When the account's list was last fetched.
    func listFetchDate(for accountID: UUID) -> Date? {
        listFetchDates[accountID]
    }

    /// One playlist as last fetched, or `nil` if it never was.
    func snapshot(id: String, for accountID: UUID) -> RemotePlaylistSnapshot? {
        snapshots[accountID]?[id]
    }

    /// When that snapshot was last fetched.
    func snapshotFetchDate(id: String, for accountID: UUID) -> Date? {
        snapshotFetchDates[accountID]?[id]
    }

    // MARK: - Refreshing

    /// Refetches the account's playlist list, joining a refresh already running.
    func refreshList(for account: Account) async throws {
        if let inFlight = listFetches[account.id] {
            return try await inFlight.value
        }
        try await fetchList(for: account)
    }

    /// Refetches one playlist, joining a refresh already running.
    func refreshSnapshot(id: String, for account: Account) async throws {
        let key = SnapshotKey(accountID: account.id, playlistID: id)
        if let inFlight = snapshotFetches[key] {
            return try await inFlight.value
        }
        try await fetchSnapshot(id: id, for: account)
    }

    // MARK: - Mutations

    /// Creates a playlist and republishes the account's list from the server.
    @discardableResult
    func createPlaylist(
        title: String,
        description: String?,
        privacy: PlaylistPrivacy?,
        for account: Account
    ) async throws -> Playlist {
        try await serializing(.list(accountID: account.id)) {
            try await reconcilingList(for: account) {
                try await accountService.createPlaylist(
                    title: title,
                    description: description,
                    privacy: privacy,
                    for: account
                )
            }
        }
    }

    /// Edits a playlist and republishes both the list and the playlist itself.
    func updatePlaylist(
        id: String,
        title: String,
        description: String?,
        privacy: PlaylistPrivacy?,
        for account: Account
    ) async throws {
        try await serializing(.playlist(accountID: account.id, playlistID: id)) {
            try await reconciling(playlist: id, andList: true, for: account) {
                try await accountService.updatePlaylist(
                    id: id,
                    title: title,
                    description: description,
                    privacy: privacy,
                    for: account
                )
            }
        }
    }

    /// Deletes a playlist and republishes the account's list.
    func deletePlaylist(id: String, for account: Account) async throws {
        try await serializing(.playlist(accountID: account.id, playlistID: id)) {
            do {
                try await accountService.deletePlaylist(id: id, for: account)
                forgetPlaylist(id: id, for: account.id)
                await reconcileList(for: account)
            } catch {
                // The delete may have landed even though the answer did not, so
                // the snapshot is refetched rather than assumed: whichever way
                // it went, the server's answer replaces it — and a server that
                // no longer has the playlist is answering that the delete did
                // land.
                await reconcileSnapshotAfterDelete(id: id, for: account)
                await reconcileList(for: account)
                throw error
            }
        }
    }

    /// Adds a video and republishes the playlist it was added to.
    func addVideo(videoID: String, toPlaylist id: String, for account: Account) async throws {
        try await serializing(.playlist(accountID: account.id, playlistID: id)) {
            try await reconciling(playlist: id, andList: false, for: account) {
                try await accountService.addVideo(videoID: videoID, toPlaylist: id, for: account)
            }
        }
    }

    /// Removes a row and republishes the playlist it was removed from.
    func removeEntry(
        _ entry: RemotePlaylistEntry,
        fromPlaylist id: String,
        for account: Account
    ) async throws {
        try await serializing(.playlist(accountID: account.id, playlistID: id)) {
            try await reconciling(playlist: id, andList: false, for: account) {
                try await accountService.removeEntry(entry, fromPlaylist: id, for: account)
            }
        }
    }

    // MARK: - Clearing

    /// Drops everything known about one account, and disowns its in-flight
    /// fetches so none of them can put it back.
    func clear(accountID: UUID) {
        generations[accountID, default: 0] += 1

        lists[accountID] = nil
        listFetchDates[accountID] = nil
        snapshots[accountID] = nil
        snapshotFetchDates[accountID] = nil

        listFetches.removeValue(forKey: accountID)?.cancel()
        for key in snapshotFetches.keys where key.accountID == accountID {
            snapshotFetches.removeValue(forKey: key)?.cancel()
        }
    }

    /// Drops everything, for a change of Apple account or of identity scope.
    func clearAll() {
        for accountID in Set(lists.keys)
            .union(snapshots.keys)
            .union(listFetches.keys)
            .union(snapshotFetches.keys.map(\.accountID))
            .union(generations.keys) {
            clear(accountID: accountID)
        }
    }

    // MARK: - Fetching

    private func fetchList(for account: Account) async throws {
        let accountID = account.id
        let generation = generations[accountID, default: 0]
        let sequence = nextSequence()

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            let playlists = try await self.accountService.userPlaylists(for: account)

            guard self.isCurrent(generation, for: accountID),
                  sequence > self.appliedListSequence[accountID, default: 0]
            else { return }

            self.appliedListSequence[accountID] = sequence
            self.lists[accountID] = playlists
            self.listFetchDates[accountID] = Date()
        }

        listFetches[accountID] = task
        defer {
            if listFetches[accountID] == task {
                listFetches[accountID] = nil
            }
        }

        try await task.value
    }

    private func fetchSnapshot(id: String, for account: Account) async throws {
        let accountID = account.id
        let key = SnapshotKey(accountID: accountID, playlistID: id)
        let generation = generations[accountID, default: 0]
        let sequence = nextSequence()

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            let snapshot = try await self.accountService.playlistSnapshot(id: id, for: account)

            guard self.isCurrent(generation, for: accountID),
                  sequence > self.appliedSnapshotSequence[key, default: 0]
            else { return }

            self.appliedSnapshotSequence[key] = sequence
            self.snapshots[accountID, default: [:]][id] = snapshot
            self.snapshotFetchDates[accountID, default: [:]][id] = Date()
            self.carryCountToList(from: snapshot, id: id, for: accountID)
        }

        snapshotFetches[key] = task
        defer {
            if snapshotFetches[key] == task {
                snapshotFetches[key] = nil
            }
        }

        try await task.value
    }

    /// Carries a refetched playlist's video count into the account's list.
    ///
    /// The list row counts the playlist's videos, and only `fetchList` rewrites
    /// the list — so a video added or removed from the detail view left the row
    /// counting what the playlist held before, until something happened to
    /// refetch the whole list. Nothing is invented here and no request is
    /// added: the count is the one the server just answered this snapshot with,
    /// and a playlist the list does not carry is left out of it rather than
    /// put in.
    private func carryCountToList(from snapshot: RemotePlaylistSnapshot, id: String, for accountID: UUID) {
        guard let index = lists[accountID]?.firstIndex(where: { $0.id.playlistID == id }),
              let existing = lists[accountID]?[index],
              existing.videoCount != snapshot.playlist.videoCount
        else { return }

        lists[accountID]?[index] = Playlist(
            id: existing.id,
            title: existing.title,
            description: existing.description,
            author: existing.author,
            videoCount: snapshot.playlist.videoCount,
            thumbnailURL: existing.thumbnailURL,
            videos: existing.videos,
            isLocal: existing.isLocal
        )
    }

    // MARK: - Reconciliation

    /// Runs a change and refetches the playlist it touched — and the list too,
    /// when the change is one the list shows — however the change turned out.
    private func reconciling<T>(
        playlist id: String,
        andList refreshesList: Bool,
        for account: Account,
        _ mutation: () async throws -> T
    ) async throws -> T {
        do {
            let value = try await mutation()
            await reconcileSnapshot(id: id, for: account)
            if refreshesList {
                await reconcileList(for: account)
            }
            return value
        } catch {
            // A write that reported failure may still have been applied — a
            // connection dropped after the server acted looks exactly like one
            // dropped before. The refetch is what settles it.
            await reconcileSnapshot(id: id, for: account)
            if refreshesList {
                await reconcileList(for: account)
            }
            throw error
        }
    }

    private func reconcilingList<T>(
        for account: Account,
        _ mutation: () async throws -> T
    ) async throws -> T {
        do {
            let value = try await mutation()
            await reconcileList(for: account)
            return value
        } catch {
            await reconcileList(for: account)
            throw error
        }
    }

    /// Refetches after a change, always as a new request: joining one that
    /// started earlier would republish the playlist as it was *before*.
    ///
    /// Its own failure is swallowed. The mutation's outcome is what the caller
    /// is told about; a reconciling refetch that could not reach the server
    /// leaves the previous data on screen, which is what every other read does
    /// offline.
    private func reconcileList(for account: Account) async {
        try? await fetchList(for: account)
    }

    private func reconcileSnapshot(id: String, for account: Account) async {
        try? await fetchSnapshot(id: id, for: account)
    }

    /// The same refetch, after a delete that reported failure — where the
    /// refetch is also the verdict.
    ///
    /// A playlist the server says it does not have is gone, whatever the delete
    /// said, so the stored snapshot is dropped rather than left to be shown by
    /// a detail view that is still open on it. Every other failure is swallowed
    /// like any reconciling refetch: not reaching the server says nothing about
    /// whether the playlist still exists.
    private func reconcileSnapshotAfterDelete(id: String, for account: Account) async {
        do {
            try await fetchSnapshot(id: id, for: account)
        } catch let error as APIError where Self.saysPlaylistIsGone(error) {
            forgetPlaylist(id: id, for: account.id)
        } catch {
            // Swallowed: see the doc comment on `reconcileList(for:)`.
        }
    }

    private static func saysPlaylistIsGone(_ error: APIError) -> Bool {
        switch error {
        case .notFound:
            return true
        case .httpError(let statusCode, _):
            return statusCode == 404
        default:
            return false
        }
    }

    /// Drops a playlist the server is known no longer to have.
    ///
    /// Three things, and each one is load-bearing. The snapshot goes, so a
    /// detail view still open on it has nothing left to show. The list entry
    /// goes, because the list is refetched right after but that refetch is
    /// allowed to fail — offline, a playlist known to be gone would otherwise
    /// sit in the list until the next successful fetch. And both fences move
    /// past every request already in flight: a refresh that started before the
    /// delete describes a playlist that still existed, and arriving late does
    /// not make it exist again.
    private func forgetPlaylist(id: String, for accountID: UUID) {
        appliedSnapshotSequence[SnapshotKey(accountID: accountID, playlistID: id)] = nextSequence()
        appliedListSequence[accountID] = nextSequence()

        snapshots[accountID]?[id] = nil
        snapshotFetchDates[accountID]?[id] = nil
        lists[accountID]?.removeAll { $0.id.playlistID == id }
    }

    // MARK: - Serialization

    /// Runs a mutation with its key held, from the write to the end of the
    /// refetch that reconciles it, and hands the key to whoever queued behind.
    ///
    /// First come, first served: waiters are resumed in arrival order, so two
    /// removals tapped in sequence are sent in that sequence. Nothing here
    /// blocks a *read* — refreshes stay coalesced and unqueued, and only a
    /// change waits for a change.
    private func serializing<T>(_ key: MutationKey, _ body: () async throws -> T) async throws -> T {
        await acquire(key)
        defer { release(key) }
        return try await body()
    }

    private func acquire(_ key: MutationKey) async {
        guard mutationWaiters[key] != nil else {
            mutationWaiters[key] = []
            return
        }

        await withCheckedContinuation { continuation in
            mutationWaiters[key, default: []].append(continuation)
        }
    }

    private func release(_ key: MutationKey) {
        guard var waiting = mutationWaiters[key], !waiting.isEmpty else {
            mutationWaiters[key] = nil
            return
        }

        let next = waiting.removeFirst()
        mutationWaiters[key] = waiting
        next.resume()
    }

    // MARK: - Fences

    private func isCurrent(_ generation: Int, for accountID: UUID) -> Bool {
        generations[accountID, default: 0] == generation
    }

    private func nextSequence() -> Int {
        sequence += 1
        return sequence
    }
}
