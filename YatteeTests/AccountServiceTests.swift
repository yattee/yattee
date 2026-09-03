//
//  AccountServiceTests.swift
//  YatteeTests
//
//  What an account is allowed to do, whose credential it did it with, and what
//  the cache does with an answer that arrived too late to matter.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Scripted transport

/// A ``RemotePlaylistTransport`` that answers from a script instead of a server.
///
/// Every call is recorded, so a test can assert what the service decided to
/// send — the privacy it dropped, the token it removed by — and any call can be
/// parked mid-flight, which is where the credential-change and generation rules
/// actually live.
private actor ScriptedPlaylistTransport: RemotePlaylistTransport {
    enum Call: Equatable, Sendable {
        case userPlaylists(credential: String)
        case snapshot(id: String, credential: String)
        case create(title: String, privacy: PlaylistPrivacy?, credential: String)
        case rename(id: String, title: String, privacy: PlaylistPrivacy?, credential: String)
        case setDescription(id: String, description: String, title: String, credential: String)
        case delete(id: String, credential: String)
        case addVideo(playlistID: String, videoID: String, credential: String)
        case remove(entryID: RemotePlaylistEntryID, credential: String)
    }

    private(set) var calls: [Call] = []

    /// Thrown by the next call of any kind, once set.
    var nextError: Error?

    /// The 1-based index of the first call that throws ``nextError``. Everything
    /// before it answers normally, which is how a write that lands and a refetch
    /// that then fails are scripted in one run.
    private var firstFailingCall = 1

    /// What ``userPlaylistSnapshot(id:instance:credential:)`` answers.
    var snapshot = RemotePlaylistSnapshot(playlist: Playlist(id: .global("pl"), title: "Playlist"), entries: [])

    /// What ``userPlaylists(instance:credential:)`` answers.
    var playlists: [Playlist] = []

    /// While true, every call suspends until `release()`.
    private var holdsCallsOpen = false
    private var parked: [CheckedContinuation<Void, Never>] = []

    func setError(_ error: Error?) { nextError = error }

    /// Fails every call from `index` on, leaving the earlier ones alone.
    func setError(_ error: Error, fromCall index: Int) {
        nextError = error
        firstFailingCall = index
    }

    func setSnapshot(_ snapshot: RemotePlaylistSnapshot) { self.snapshot = snapshot }
    func setPlaylists(_ playlists: [Playlist]) { self.playlists = playlists }
    func holdCalls() { holdsCallsOpen = true }

    /// Stops parking *new* calls without releasing the ones already parked, so
    /// a request can be left in flight while other work runs to completion.
    func stopHoldingNewCalls() { holdsCallsOpen = false }

    func release() {
        holdsCallsOpen = false
        let waiting = parked
        parked = []
        waiting.forEach { $0.resume() }
    }

    /// Waits until at least `count` calls have been entered.
    func waitForCalls(_ count: Int) async throws {
        for _ in 0 ..< 400 {
            if calls.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The transport was never entered \(count) time(s)")
    }

    var callCount: Int { calls.count }

    private func record(_ call: Call) async throws {
        calls.append(call)

        if holdsCallsOpen {
            await withCheckedContinuation { parked.append($0) }
        }

        if let error = nextError, calls.count >= firstFailingCall {
            throw error
        }
    }

    func userPlaylists(instance _: Instance, credential: String) async throws -> [Playlist] {
        try await record(.userPlaylists(credential: credential))
        return playlists
    }

    func userPlaylistSnapshot(
        id: String,
        instance _: Instance,
        credential: String
    ) async throws -> RemotePlaylistSnapshot {
        try await record(.snapshot(id: id, credential: credential))
        return snapshot
    }

    func createPlaylist(
        title: String,
        privacy: PlaylistPrivacy?,
        instance _: Instance,
        credential: String
    ) async throws -> Playlist {
        try await record(.create(title: title, privacy: privacy, credential: credential))
        return Playlist(id: .global("new-playlist"), title: title)
    }

    func renamePlaylist(
        id: String,
        title: String,
        privacy: PlaylistPrivacy?,
        instance _: Instance,
        credential: String
    ) async throws {
        try await record(.rename(id: id, title: title, privacy: privacy, credential: credential))
    }

    func setPlaylistDescription(
        id: String,
        description: String,
        title: String,
        instance _: Instance,
        credential: String
    ) async throws {
        try await record(
            .setDescription(id: id, description: description, title: title, credential: credential)
        )
    }

    func deletePlaylist(id: String, instance _: Instance, credential: String) async throws {
        try await record(.delete(id: id, credential: credential))
    }

    func addVideoToPlaylist(
        playlistID: String,
        videoID: String,
        instance _: Instance,
        credential: String
    ) async throws {
        try await record(.addVideo(playlistID: playlistID, videoID: videoID, credential: credential))
    }

    func removeEntry(_ entryID: RemotePlaylistEntryID, instance _: Instance, credential: String) async throws {
        try await record(.remove(entryID: entryID, credential: credential))
    }
}

// MARK: - Harness

/// An account on an instance, a scripted transport, and the service between
/// them. The credential lives in a mutable box so a test can replace it while a
/// call is still out.
@MainActor
private final class AccountServiceHarness {
    let instances: InstancesManager
    private(set) var instance: Instance
    let accounts: AccountsManager
    let account: Account
    let transport = ScriptedPlaylistTransport()
    private(set) var service: AccountService!

    /// What the credential reader reports right now.
    var credential: String? = "secret-original"

    /// Installed as ``credential`` the moment it is next read, so a test can
    /// place a sign-out exactly between resolving a credential and using it —
    /// the window the pre-transport recheck exists for, which is otherwise not
    /// reachable from outside on the paths that do no awaiting first.
    var credentialSwapOnNextRead: String?

    init(type: InstanceType = .invidious, isEnabled: Bool = true) {
        instances = InstancesManager()
        instance = Instance(
            type: type,
            url: URL(string: "https://accounts-\(UUID().uuidString).example.com")!,
            isEnabled: isEnabled
        )
        instances.add(instance)

        accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            instancesManager: instances,
            defaults: UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!,
            unreachableRetryInterval: 3600
        )
        account = accounts.addAccount(instanceID: instance.id)
        accounts.setStatus(.signedIn, for: account.id)

        service = AccountService(
            accountsManager: accounts,
            credentialReader: { [weak self] _ in self?.readCredential() },
            transport: transport
        )
    }

    private func readCredential() -> String? {
        let value = credential
        if let swap = credentialSwapOnNextRead {
            credential = swap
            credentialSwapOnNextRead = nil
        }
        return value
    }

    /// Instances live in the shared defaults, so each harness takes its own
    /// back out again.
    func tearDown() {
        instances.remove(instance)
    }

    var status: AccountStatus {
        accounts.status(for: account.id)
    }

    func makeCache() -> RemotePlaylistsCache {
        RemotePlaylistsCache(accountService: service)
    }
}

private func makeVideo(_ id: String) -> Video {
    Video(
        id: .global(id),
        title: "Video \(id)",
        description: nil,
        author: Author(id: "UCtest", name: "Test Channel"),
        duration: 60,
        publishedAt: nil,
        publishedText: nil,
        viewCount: nil,
        likeCount: nil,
        thumbnails: [],
        isLive: false,
        isUpcoming: false,
        scheduledStartTime: nil
    )
}

private func makeSnapshot(
    playlistID: String,
    videoIDs: [String],
    kind: InstanceType
) -> RemotePlaylistSnapshot {
    let videos = videoIDs.map(makeVideo)
    let entries = videos.enumerated().map { offset, video in
        RemotePlaylistEntry(
            id: kind == .invidious
                ? .invidious(playlistID: playlistID, indexID: "TOKEN-\(video.id.videoID)")
                : .piped(playlistID: playlistID, position: offset),
            video: video,
            position: offset,
            displayRow: offset
        )
    }

    return RemotePlaylistSnapshot(
        playlist: Playlist(id: .global(playlistID), title: "Playlist", videos: videos),
        entries: entries
    )
}

// MARK: - Tests

@Suite("Account service", .serialized)
@MainActor
struct AccountServiceTests {
    // MARK: - Capability gating

    @Test("A backend without playlist support is refused before anything is sent")
    func unsupportedBackendIsRefused() async throws {
        let harness = AccountServiceHarness(type: .peertube)
        defer { harness.tearDown() }

        await #expect(throws: AccountServiceError.notSupported) {
            _ = try await harness.service.userPlaylists(for: harness.account)
        }

        #expect(await harness.transport.callCount == 0)
    }

    @Test("A backend without playlist privacy never receives one")
    func privacyIsDroppedWhereUnsupported() async throws {
        let harness = AccountServiceHarness(type: .piped)
        defer { harness.tearDown() }

        _ = try await harness.service.createPlaylist(
            title: "Watch later",
            description: nil,
            privacy: .private,
            for: harness.account
        )

        #expect(await harness.transport.calls == [
            .create(title: "Watch later", privacy: nil, credential: "secret-original")
        ])
    }

    @Test("A backend with playlist privacy receives the one that was asked for")
    func privacyIsPassedWhereSupported() async throws {
        let harness = AccountServiceHarness(type: .invidious)
        defer { harness.tearDown() }

        _ = try await harness.service.createPlaylist(
            title: "Watch later",
            description: "Later",
            privacy: .unlisted,
            for: harness.account
        )

        // Two requests, because no backend takes a description at creation.
        #expect(await harness.transport.calls == [
            .create(title: "Watch later", privacy: .unlisted, credential: "secret-original"),
            .setDescription(
                id: "new-playlist",
                description: "Later",
                title: "Watch later",
                credential: "secret-original"
            )
        ])
    }

    // MARK: - Composite writes

    @Test("A credential replaced between a creation and its description stops the second call")
    func creationStopsDescribingWhenTheCredentialChanges() async throws {
        let harness = AccountServiceHarness(type: .invidious)
        defer { harness.tearDown() }
        await harness.transport.holdCalls()

        let creation = Task { [service = harness.service!, account = harness.account] in
            try await service.createPlaylist(
                title: "Watch later",
                description: "Later",
                privacy: .private,
                for: account
            )
        }

        // The creation is out. Somebody signs out and back in as another user
        // before it answers — the description must not go to the new login.
        try await harness.transport.waitForCalls(1)
        harness.credential = "secret-somebody-else"
        await harness.transport.release()

        await #expect(throws: AccountServiceError.notAuthenticated) {
            _ = try await creation.value
        }

        #expect(await harness.transport.calls == [
            .create(title: "Watch later", privacy: .private, credential: "secret-original")
        ])
    }

    @Test("An edit sends the description only after rechecking the credential")
    func editRechecksBetweenRenameAndDescription() async throws {
        let harness = AccountServiceHarness(type: .piped)
        defer { harness.tearDown() }
        await harness.transport.holdCalls()

        let edit = Task { [service = harness.service!, account = harness.account] in
            try await service.updatePlaylist(
                id: "pl",
                title: "Renamed",
                description: "New description",
                privacy: nil,
                for: account
            )
        }

        try await harness.transport.waitForCalls(1)
        harness.credential = "secret-somebody-else"
        await harness.transport.release()

        await #expect(throws: AccountServiceError.notAuthenticated) {
            try await edit.value
        }

        // The rename landed under the old login; the description never went.
        #expect(await harness.transport.calls == [
            .rename(id: "pl", title: "Renamed", privacy: nil, credential: "secret-original")
        ])
    }

    @Test("An edit that keeps its credential renames and then describes")
    func editSendsBothHalvesWithTheSameCredential() async throws {
        let harness = AccountServiceHarness(type: .invidious)
        defer { harness.tearDown() }

        try await harness.service.updatePlaylist(
            id: "pl",
            title: "Renamed",
            description: "New description",
            privacy: .public,
            for: harness.account
        )

        #expect(await harness.transport.calls == [
            .rename(id: "pl", title: "Renamed", privacy: .public, credential: "secret-original"),
            .setDescription(
                id: "pl",
                description: "New description",
                title: "Renamed",
                credential: "secret-original"
            )
        ])
    }

    @Test("An edit that names no visibility sends none, rather than inventing one")
    func editWithoutPrivacySendsNone() async throws {
        let harness = AccountServiceHarness(type: .invidious)
        defer { harness.tearDown() }

        try await harness.service.updatePlaylist(
            id: "pl",
            title: "Renamed",
            description: nil,
            privacy: nil,
            for: harness.account
        )

        #expect(await harness.transport.calls == [
            .rename(id: "pl", title: "Renamed", privacy: nil, credential: "secret-original")
        ])
    }

    // MARK: - Resolution

    @Test("An account with no readable credential is not sent anywhere")
    func missingCredentialIsRefused() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        harness.credential = nil

        await #expect(throws: AccountServiceError.notAuthenticated) {
            _ = try await harness.service.userPlaylists(for: harness.account)
        }

        #expect(await harness.transport.callCount == 0)
    }

    @Test("An account on a disabled instance is not sent anywhere")
    func disabledInstanceIsRefused() async throws {
        let harness = AccountServiceHarness(isEnabled: false)
        defer { harness.tearDown() }

        await #expect(throws: AccountServiceError.instanceNotConfigured) {
            _ = try await harness.service.userPlaylists(for: harness.account)
        }

        #expect(await harness.transport.callCount == 0)
    }

    // MARK: - Outcome tracking

    @Test("A successful call reports the account as signed in")
    func successRecordsSignedIn() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        harness.accounts.setStatus(.credentialMissing, for: harness.account.id)

        _ = try await harness.service.userPlaylists(for: harness.account)

        #expect(harness.status == .signedIn)
    }

    @Test("A server that cannot be reached is recorded as such")
    func failureRecordsTheError() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        await harness.transport.setError(APIError.timeout)

        await #expect(throws: APIError.timeout) {
            _ = try await harness.service.userPlaylists(for: harness.account)
        }

        #expect(harness.status == .unreachable)
    }

    @Test("An answer about a credential that has since been replaced records nothing")
    func staleCredentialRecordsNothing() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        harness.accounts.setStatus(.credentialRejected, for: harness.account.id)
        await harness.transport.holdCalls()

        let call = Task { [service = harness.service!, account = harness.account] in
            try await service.userPlaylists(for: account)
        }

        try await harness.transport.waitForCalls(1)

        // The user signs in again while the request is still out. Its answer
        // describes a secret nobody holds any more.
        harness.credential = "secret-replacement"
        await harness.transport.release()
        _ = try await call.value

        #expect(harness.status == .credentialRejected)
    }

    // MARK: - Removal

    @Test("Invidious removes by the server's own token")
    func invidiousRemovesByIndexID() async throws {
        let harness = AccountServiceHarness(type: .invidious)
        defer { harness.tearDown() }
        let snapshot = makeSnapshot(playlistID: "pl", videoIDs: ["aaa", "bbb"], kind: .invidious)

        try await harness.service.removeEntry(
            snapshot.entries[1],
            fromPlaylist: "pl",
            for: harness.account
        )

        #expect(await harness.transport.calls == [
            .remove(entryID: .invidious(playlistID: "pl", indexID: "TOKEN-bbb"), credential: "secret-original")
        ])
    }

    @Test("Piped removes by position once the position still holds the same video")
    func pipedRemovesAfterVerifying() async throws {
        let harness = AccountServiceHarness(type: .piped)
        defer { harness.tearDown() }
        let snapshot = makeSnapshot(playlistID: "pl", videoIDs: ["aaa", "bbb"], kind: .piped)
        await harness.transport.setSnapshot(snapshot)

        try await harness.service.removeEntry(
            snapshot.entries[1],
            fromPlaylist: "pl",
            for: harness.account
        )

        #expect(await harness.transport.calls == [
            .snapshot(id: "pl", credential: "secret-original"),
            .remove(entryID: .piped(playlistID: "pl", position: 1), credential: "secret-original")
        ])
    }

    @Test("Piped removes nothing when the position now holds a different video")
    func pipedRefusesToRemoveAMovedRow() async throws {
        let harness = AccountServiceHarness(type: .piped)
        defer { harness.tearDown() }
        let stale = makeSnapshot(playlistID: "pl", videoIDs: ["aaa", "bbb"], kind: .piped)
        // The row above was removed elsewhere, so position 1 is now a different
        // video entirely — removing by that position would delete the wrong one.
        await harness.transport.setSnapshot(makeSnapshot(playlistID: "pl", videoIDs: ["bbb", "ccc"], kind: .piped))

        await #expect(throws: AccountServiceError.entryMismatch) {
            try await harness.service.removeEntry(stale.entries[1], fromPlaylist: "pl", for: harness.account)
        }

        #expect(await harness.transport.calls == [.snapshot(id: "pl", credential: "secret-original")])
    }

    // MARK: - Credential recheck before a write

    @Test("A credential replaced during the Piped verify step sends no removal")
    func pipedRemovalStopsWhenTheCredentialChangesMidVerify() async throws {
        let harness = AccountServiceHarness(type: .piped)
        defer { harness.tearDown() }
        let snapshot = makeSnapshot(playlistID: "pl", videoIDs: ["aaa", "bbb"], kind: .piped)
        await harness.transport.setSnapshot(snapshot)
        await harness.transport.holdCalls()

        let removal = Task { [service = harness.service!, account = harness.account] in
            try await service.removeEntry(snapshot.entries[1], fromPlaylist: "pl", for: account)
        }

        // The verify fetch is out. Somebody signs out and back in as another
        // user before it answers.
        try await harness.transport.waitForCalls(1)
        harness.credential = "secret-somebody-else"
        await harness.transport.release()

        await #expect(throws: AccountServiceError.notAuthenticated) {
            try await removal.value
        }

        // The verify happened; the removal never did.
        #expect(await harness.transport.calls == [.snapshot(id: "pl", credential: "secret-original")])
    }

    @Test("A mutation whose credential changed since it was resolved is not sent")
    func mutationStopsWhenTheCredentialChangesBeforeTransport() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        // Resolution reads "secret-original"; the recheck immediately before the
        // write reads the replacement.
        harness.credentialSwapOnNextRead = "secret-replacement"

        await #expect(throws: AccountServiceError.notAuthenticated) {
            _ = try await harness.service.createPlaylist(
                title: "Watch later",
                description: nil,
                privacy: nil,
                for: harness.account
            )
        }

        #expect(await harness.transport.callCount == 0)
    }

    @Test("A read is not stopped by a credential change, only a write is")
    func readsAreNotRechecked() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        harness.credentialSwapOnNextRead = "secret-replacement"

        _ = try await harness.service.userPlaylists(for: harness.account)

        #expect(await harness.transport.calls == [.userPlaylists(credential: "secret-original")])
    }

    @Test("An entry minted by another playlist is refused")
    func entryFromAnotherPlaylistIsRefused() async throws {
        let harness = AccountServiceHarness(type: .invidious)
        defer { harness.tearDown() }
        let other = makeSnapshot(playlistID: "other", videoIDs: ["aaa"], kind: .invidious)

        await #expect(throws: AccountServiceError.entryMismatch) {
            try await harness.service.removeEntry(other.entries[0], fromPlaylist: "pl", for: harness.account)
        }

        #expect(await harness.transport.callCount == 0)
    }
}

// MARK: - Cache

@Suite("Remote playlists cache", .serialized)
@MainActor
struct RemotePlaylistsCacheTests {
    @Test("A result that arrives after the account was cleared is dropped")
    func generationFenceDropsStaleResults() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        await harness.transport.setPlaylists([Playlist(id: .global("pl"), title: "Playlist")])
        await harness.transport.holdCalls()

        let refresh = Task { [account = harness.account] in
            try await cache.refreshList(for: account)
        }
        try await harness.transport.waitForCalls(1)

        // Signed out while the fetch is still out: the request is not cancelled
        // by clearing, so its answer has to be refused on arrival.
        cache.clear(accountID: harness.account.id)
        await harness.transport.release()
        _ = try? await refresh.value

        #expect(cache.playlists(for: harness.account.id) == nil)
    }

    @Test("Creating a playlist republishes the list from the server")
    func createRefreshesTheList() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        await harness.transport.setPlaylists([Playlist(id: .global("new-playlist"), title: "Watch later")])

        let created = try await cache.createPlaylist(
            title: "Watch later",
            description: nil,
            privacy: nil,
            for: harness.account
        )

        #expect(created.title == "Watch later")
        #expect(cache.playlists(for: harness.account.id)?.map(\.title) == ["Watch later"])
    }

    @Test("A failed mutation still refetches what it may have changed")
    func failedMutationStillReconciles() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        await harness.transport.setSnapshot(makeSnapshot(playlistID: "pl", videoIDs: ["aaa"], kind: .invidious))

        // The write reports failure, which is not the same as not having landed.
        await harness.transport.setError(APIError.httpError(statusCode: 500, message: nil))

        await #expect(throws: APIError.self) {
            try await cache.addVideo(videoID: "bbb", toPlaylist: "pl", for: harness.account)
        }

        let calls = await harness.transport.calls
        #expect(calls.contains(.addVideo(playlistID: "pl", videoID: "bbb", credential: "secret-original")))
        #expect(calls.contains(.snapshot(id: "pl", credential: "secret-original")))
    }

    @Test("A delete that reported failure forgets a playlist the server no longer has")
    func failedDeleteForgetsAVanishedPlaylist() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        await harness.transport.setSnapshot(makeSnapshot(playlistID: "pl", videoIDs: ["aaa"], kind: .invidious))
        await harness.transport.setPlaylists([Playlist(id: .global("pl"), title: "Playlist")])

        try await cache.refreshSnapshot(id: "pl", for: harness.account)
        try await cache.refreshList(for: harness.account)
        #expect(cache.snapshot(id: "pl", for: harness.account.id) != nil)

        // The delete answers with an error, and every refetch after it 404s:
        // the playlist is gone, whatever the delete said.
        await harness.transport.setError(APIError.notFound(nil))

        await #expect(throws: APIError.self) {
            try await cache.deletePlaylist(id: "pl", for: harness.account)
        }

        #expect(cache.snapshot(id: "pl", for: harness.account.id) == nil)
        #expect(cache.snapshotFetchDate(id: "pl", for: harness.account.id) == nil)
        #expect(cache.playlists(for: harness.account.id)?.contains { $0.id.playlistID == "pl" } != true)
    }

    @Test("A refresh in flight across a delete cannot bring the playlist back")
    func inFlightRefreshCannotResurrectADeletedPlaylist() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        await harness.transport.setSnapshot(makeSnapshot(playlistID: "pl", videoIDs: ["aaa"], kind: .invidious))
        await harness.transport.setPlaylists([Playlist(id: .global("pl"), title: "Playlist")])
        await harness.transport.holdCalls()

        let refresh = Task { [account = harness.account] in
            try await cache.refreshSnapshot(id: "pl", for: account)
        }
        try await harness.transport.waitForCalls(1)

        // That fetch is parked mid-flight. The delete runs to completion around
        // it, and the server stops listing the playlist.
        await harness.transport.stopHoldingNewCalls()
        await harness.transport.setPlaylists([])
        try await cache.deletePlaylist(id: "pl", for: harness.account)

        // Only now does the older fetch answer. It describes a playlist that
        // existed when it was asked for, and arriving late does not bring it
        // back.
        await harness.transport.release()
        _ = try? await refresh.value

        #expect(cache.snapshot(id: "pl", for: harness.account.id) == nil)
        #expect(cache.playlists(for: harness.account.id)?.isEmpty == true)
    }

    @Test("A delete that landed drops the list entry even when the refetch fails")
    func successfulDeleteForgetsTheListEntryWhenTheRefetchFails() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        await harness.transport.setSnapshot(makeSnapshot(playlistID: "pl", videoIDs: ["aaa"], kind: .invidious))
        await harness.transport.setPlaylists([Playlist(id: .global("pl"), title: "Playlist")])

        try await cache.refreshSnapshot(id: "pl", for: harness.account)
        try await cache.refreshList(for: harness.account)

        // The delete itself lands; the reconciling list refetch right after it
        // cannot reach the server.
        await harness.transport.setError(APIError.noConnection, fromCall: 4)
        try await cache.deletePlaylist(id: "pl", for: harness.account)

        #expect(cache.snapshot(id: "pl", for: harness.account.id) == nil)
        #expect(cache.playlists(for: harness.account.id)?.isEmpty == true)
    }

    @Test("A delete that could not reach the server keeps the playlist it knows")
    func failedDeleteKeepsThePlaylistWhenOffline() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        await harness.transport.setSnapshot(makeSnapshot(playlistID: "pl", videoIDs: ["aaa"], kind: .invidious))
        await harness.transport.setPlaylists([Playlist(id: .global("pl"), title: "Playlist")])

        try await cache.refreshSnapshot(id: "pl", for: harness.account)
        try await cache.refreshList(for: harness.account)

        await harness.transport.setError(APIError.noConnection)

        await #expect(throws: APIError.self) {
            try await cache.deletePlaylist(id: "pl", for: harness.account)
        }

        // Not reaching the server says nothing about whether the playlist still
        // exists — the last fetch stays, as it does for every other read.
        #expect(cache.snapshot(id: "pl", for: harness.account.id) != nil)
        #expect(cache.playlists(for: harness.account.id)?.map(\.id.playlistID) == ["pl"])
    }

    @Test("Concurrent refreshes of the same list cost one round trip")
    func concurrentRefreshesAreCoalesced() async throws {
        let harness = AccountServiceHarness()
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        await harness.transport.setPlaylists([Playlist(id: .global("pl"), title: "Playlist")])
        await harness.transport.holdCalls()

        let first = Task { [account = harness.account] in try await cache.refreshList(for: account) }
        try await harness.transport.waitForCalls(1)
        let second = Task { [account = harness.account] in try await cache.refreshList(for: account) }

        // Long enough for a second request to have been made, had one been.
        try await Task.sleep(for: .milliseconds(50))
        await harness.transport.release()
        try await first.value
        try await second.value

        #expect(await harness.transport.callCount == 1)
        #expect(cache.playlists(for: harness.account.id)?.count == 1)
    }

    @Test("A second removal waits for the first one's refetch before it preflights")
    func removalsOnOnePlaylistAreSerialized() async throws {
        let harness = AccountServiceHarness(type: .piped)
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        let snapshot = makeSnapshot(playlistID: "pl", videoIDs: ["aaa", "bbb"], kind: .piped)
        await harness.transport.setSnapshot(snapshot)
        await harness.transport.holdCalls()

        let first = Task { [account = harness.account] in
            try await cache.removeEntry(snapshot.entries[0], fromPlaylist: "pl", for: account)
        }
        try await harness.transport.waitForCalls(1)

        // Tapped while the first removal's preflight is still out. Its own
        // preflight must not be sent yet: it would describe the playlist as it
        // was *before* the first removal, and a Piped position taken from that
        // names whatever shifts into the slot.
        let second = Task { [account = harness.account] in
            try await cache.removeEntry(snapshot.entries[1], fromPlaylist: "pl", for: account)
        }

        // Long enough for a second preflight to have been sent, had one been.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await harness.transport.callCount == 1)

        await harness.transport.release()
        try await first.value
        try await second.value

        // Three calls each, in order, and never interleaved: preflight, remove,
        // and the refetch that reconciles it.
        #expect(await harness.transport.calls == [
            .snapshot(id: "pl", credential: "secret-original"),
            .remove(entryID: .piped(playlistID: "pl", position: 0), credential: "secret-original"),
            .snapshot(id: "pl", credential: "secret-original"),
            .snapshot(id: "pl", credential: "secret-original"),
            .remove(entryID: .piped(playlistID: "pl", position: 1), credential: "secret-original"),
            .snapshot(id: "pl", credential: "secret-original")
        ])
    }

    @Test("Removals from different playlists do not wait for each other")
    func removalsOnDifferentPlaylistsInterleave() async throws {
        let harness = AccountServiceHarness(type: .piped)
        defer { harness.tearDown() }
        let cache = harness.makeCache()
        let one = makeSnapshot(playlistID: "one", videoIDs: ["aaa"], kind: .piped)
        let two = makeSnapshot(playlistID: "two", videoIDs: ["aaa"], kind: .piped)
        await harness.transport.setSnapshot(one)
        await harness.transport.holdCalls()

        let first = Task { [account = harness.account] in
            try await cache.removeEntry(one.entries[0], fromPlaylist: "one", for: account)
        }
        try await harness.transport.waitForCalls(1)

        let second = Task { [account = harness.account] in
            try await cache.removeEntry(two.entries[0], fromPlaylist: "two", for: account)
        }

        // Both preflights are out at once: the queue is per playlist, not one
        // for the whole account.
        try await harness.transport.waitForCalls(2)
        #expect(await harness.transport.callCount == 2)

        await harness.transport.release()
        try await first.value
        try await second.value
    }
}
