//
//  WatchHistorySyncTests.swift
//  YatteeTests
//
//  Which account a watch is mirrored to, how many times it is sent, and what
//  happens to a post nobody is waiting for.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Harness

/// An account whose instance keeps history, the scripted transport behind it,
/// and the sync service on top.
///
/// The context validator is the real one: what suppresses mirroring is the
/// *effective* context, and that is computed from the account's status and its
/// instance — both of which a test can move directly.
@MainActor
private final class WatchHistorySyncHarness {
    let instances: InstancesManager
    private(set) var instance: Instance
    let accounts: AccountsManager
    let account: Account
    let playlistTransport = ScriptedPlaylistTransport()
    let transport = ScriptedHistoryTransport()
    let validator: DataContextValidator
    private(set) var service: WatchHistorySyncService!

    /// What the credential reader reports for each account right now. Keyed by
    /// account so a post can be shown to have gone out under the login that was
    /// selected when playback started, and not the one selected since.
    var credentials: [UUID: String] = [:]

    init(type: InstanceType = .invidious) {
        instances = makeTestInstancesManager()
        instance = Instance(
            type: type,
            url: URL(string: "https://history-\(UUID().uuidString).example.com")!,
            isEnabled: true
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
        accounts.setContext(.account(account.id))
        credentials[account.id] = "secret-original"

        validator = DataContextValidator(
            accountsManager: accounts,
            instancesManager: instances,
            toastManager: ToastManager()
        )

        let accountService = AccountService(
            accountsManager: accounts,
            credentialReader: { [weak self] account in self?.credentials[account.id] },
            transport: playlistTransport,
            historyTransport: transport
        )

        service = WatchHistorySyncService(
            accountsManager: accounts,
            accountService: accountService,
            contextValidator: validator
        )
    }

    /// Instances live in the shared defaults, so each harness takes its own
    /// back out again.
    func tearDown() {
        instances.remove(instance)
    }

    /// A second account on its own instance, for the context switches.
    @discardableResult
    func addSecondAccount(type: InstanceType = .invidious) -> (Instance, Account) {
        let other = Instance(
            type: type,
            url: URL(string: "https://history-other-\(UUID().uuidString).example.com")!,
            isEnabled: true
        )
        instances.add(other)
        let otherAccount = accounts.addAccount(instanceID: other.id)
        accounts.setStatus(.signedIn, for: otherAccount.id)
        credentials[otherAccount.id] = "secret-other"
        return (other, otherAccount)
    }
}

/// A flag a test can look at from outside the task that sets it.
@MainActor
private final class Flag {
    var isSet = false
}

/// Collects what ``Notification/Name/serverWatchHistoryDidUpdate`` announced.
@MainActor
private final class UpdateAnnouncements {
    private(set) var received: [(accountID: UUID, videoID: String)] = []
    private var observer: NSObjectProtocol?

    init() {
        // No queue: delivered synchronously, on the main actor the post is made
        // from, so a test can look at it the moment the flush returns.
        observer = NotificationCenter.default.addObserver(
            forName: .serverWatchHistoryDidUpdate,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let accountID = notification.userInfo?[ServerWatchHistoryUpdate.accountIDKey] as? UUID,
                  let videoID = notification.userInfo?[ServerWatchHistoryUpdate.videoIDKey] as? String
            else { return }

            MainActor.assumeIsolated {
                self?.received.append((accountID: accountID, videoID: videoID))
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
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

/// A file from a media source: an ID no YouTube-backed history can take.
private func makeExtractedVideo(_ id: String) -> Video {
    Video(
        id: .extracted(id, extractor: "generic", originalURL: URL(string: "https://example.com/\(id).mp4")!),
        title: "File \(id)",
        description: nil,
        author: Author(id: "local", name: "Files"),
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

// MARK: - Tests

@Suite("Watch history mirroring", .serialized)
@MainActor
struct WatchHistorySyncTests {
    // MARK: - What is mirrored, and to whom

    @Test("A watch is posted once its progress is first saved")
    func progressPostsTheWatch() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(await harness.transport.calls == [
            .markWatched(videoID: "aaa", credential: "secret-original")
        ])
    }

    @Test("A context switched mid-video does not redirect the post")
    func theAccountIsCapturedWhenPlaybackStarts() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        let (_, other) = harness.addSecondAccount()

        harness.service.beginSession(video: makeVideo("aaa"))

        // The user switches accounts while the video is playing. The video was
        // still watched under the one that was selected when it started.
        harness.accounts.setContext(.account(other.id))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(await harness.transport.calls == [
            .markWatched(videoID: "aaa", credential: "secret-original")
        ])
    }

    @Test("Repeated progress saves in one session cost one post")
    func oneSessionPostsOnce() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        harness.service.recordProgress(videoID: "aaa")
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(await harness.transport.markedVideoIDs == ["aaa"])
    }

    @Test("Playing the same video again is a new watch and posts again")
    func aNewSessionForTheSameVideoPostsAgain() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        harness.service.endSession()

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(await harness.transport.markedVideoIDs == ["aaa", "aaa"])
    }

    @Test("A finished video played again is a new watch and posts again")
    func aFreshSessionForTheSameVideoPostsAgain() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")

        // The replay button, or repeat-one coming round: the same video, still
        // loaded, watched a second time.
        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(await harness.transport.markedVideoIDs == ["aaa", "aaa"])
    }

    // MARK: - Reloads of the video already playing

    @Test("Reloading the video already playing does not post it again")
    func reloadingTheSameVideoKeepsTheSession() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSessionIfNeeded(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")

        // An audio-mode toggle, a quality switch, a stream retry: the same
        // video loaded again, and the same watch.
        harness.service.beginSessionIfNeeded(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(await harness.transport.markedVideoIDs == ["aaa"])
    }

    @Test("Moving to another video starts that video's session")
    func anotherVideoReplacesTheSession() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSessionIfNeeded(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")

        harness.service.beginSessionIfNeeded(video: makeVideo("bbb"))
        harness.service.recordProgress(videoID: "bbb")
        await harness.service.flushPending()

        #expect(await harness.transport.markedVideoIDs == ["aaa", "bbb"])
    }

    @Test("The first video of a playback starts a session with nothing to compare to")
    func theFirstVideoStartsASession() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSessionIfNeeded(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(await harness.transport.markedVideoIDs == ["aaa"])
    }

    @Test("A video opened again after the player stopped is watched again")
    func theSameVideoAfterAnEndedSessionPostsAgain() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSessionIfNeeded(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        harness.service.endSession()

        harness.service.beginSessionIfNeeded(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(await harness.transport.markedVideoIDs == ["aaa", "aaa"])
    }

    @Test("Progress for a video the session is not about is ignored")
    func progressForAnotherVideoIsIgnored() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "bbb")
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 0)
    }

    @Test("Progress after the session ended is ignored")
    func progressAfterTheSessionEndedIsIgnored() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.endSession()
        harness.service.recordProgress(videoID: "aaa")
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 0)
    }

    // MARK: - What is never mirrored

    @Test("A video that is not YouTube content is never posted")
    func nonYouTubeContentIsNeverPosted() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeExtractedVideo("file"))
        harness.service.recordProgress(videoID: "file")
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 0)
    }

    @Test("Local data is nobody's history")
    func localContextIsNeverPosted() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        harness.accounts.setContext(.local)

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 0)
    }

    @Test("A backend without a history endpoint is never posted to")
    func anAccountWithoutHistorySupportIsNeverPosted() async throws {
        let harness = WatchHistorySyncHarness(type: .piped)
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 0)
    }

    @Test("A context that is only falling back to local is not mirrored either")
    func anUnavailableContextIsNeverPosted() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        // The selection is kept, but nothing may be sent under it — and the
        // reads behind the watch came from local data, not the account.
        harness.accounts.setStatus(.credentialMissing, for: harness.account.id)

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 0)
    }

    // MARK: - Failure

    @Test("A failed post is tried once more and then dropped")
    func aFailedPostIsRetriedExactlyOnce() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        await harness.transport.setError(APIError.timeout)

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 2)
    }

    @Test("A post the server refused on its merits is not tried again")
    func aNonRetryableFailureIsNotRetried() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        // An ID this server will not take is not going to take it the second
        // time either.
        await harness.transport.setError(APIError.httpError(statusCode: 400, message: "Invalid video id."))

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 1)
    }

    @Test("A post the transport itself refused is not tried again")
    func aServiceFailureFromTheTransportIsNotRetried() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        await harness.transport.setError(AccountServiceError.notSupported)

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 1)
    }

    @Test("A post that could not be resolved at all is not retried")
    func aResolutionFailureIsNotRetried() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))

        // Signed out between the session starting and the progress save: the
        // account has no credential to send, and asking again would not change
        // that.
        harness.credentials[harness.account.id] = nil
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 0)
    }

    @Test("An account deleted while the video played has nothing to mirror to")
    func aDeletedAccountDropsThePost() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.accounts.removeAccount(harness.account.id)
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()
        try await harness.transport.settle()

        #expect(await harness.transport.callCount == 0)
    }

    // MARK: - Announcing

    @Test("A post that landed says so, naming the account and the video")
    func aSuccessfulPostIsAnnounced() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        let announcements = UpdateAnnouncements()
        defer { announcements.stop() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()

        #expect(announcements.received.count == 1)
        #expect(announcements.received.first?.accountID == harness.account.id)
        #expect(announcements.received.first?.videoID == "aaa")
    }

    @Test("A post that never landed announces nothing")
    func aFailedPostIsNotAnnounced() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        let announcements = UpdateAnnouncements()
        defer { announcements.stop() }
        await harness.transport.setError(APIError.timeout)

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        await harness.service.flushPending()
        try await harness.transport.settle()

        #expect(announcements.received.isEmpty)
    }

    // MARK: - Draining and disowning

    @Test("A flush returns only once the post it is waiting for has landed")
    func flushWaitsForAPostInFlight() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        await harness.transport.holdCalls()

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        try await harness.transport.waitForCalls(1)

        let finished = Flag()
        let flush = Task { [service = harness.service!] in
            await service.flushPending()
            finished.isSet = true
        }

        // Long enough for the flush to have returned, had it not been waiting.
        try await Task.sleep(for: .milliseconds(50))
        #expect(finished.isSet == false)

        await harness.transport.release()
        await flush.value
        #expect(finished.isSet)
    }

    @Test("A flush with nothing pending returns immediately")
    func flushWithNothingPendingReturns() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        await harness.service.flushPending()

        #expect(await harness.transport.callCount == 0)
    }

    @Test("An account that goes away takes its unsent post with it")
    func cancellingPreventsThePost() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.cancelPending(for: harness.account.id)
        harness.service.recordProgress(videoID: "aaa")
        try await harness.transport.settle()

        // The session went with it, so the progress save has nothing to post.
        #expect(await harness.transport.callCount == 0)
    }

    @Test("An account that goes away disowns the post already in flight")
    func cancellingKillsAPostInFlight() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        await harness.transport.holdCalls()

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        try await harness.transport.waitForCalls(1)

        harness.service.cancelPending(for: harness.account.id)
        await harness.transport.release()

        // Nothing is left to wait for, and the cancelled attempt is never
        // repeated.
        await harness.service.flushPending()
        try await harness.transport.settle()
        #expect(await harness.transport.callCount == 1)
    }

    @Test("Another account's trouble leaves this one's post alone")
    func cancellingAnotherAccountLeavesThePost() async throws {
        let harness = WatchHistorySyncHarness()
        defer { harness.tearDown() }
        let (_, other) = harness.addSecondAccount()

        harness.service.beginSession(video: makeVideo("aaa"))
        harness.service.recordProgress(videoID: "aaa")
        harness.service.cancelPending(for: other.id)
        await harness.service.flushPending()

        #expect(await harness.transport.markedVideoIDs == ["aaa"])
    }
}
