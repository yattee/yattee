//
//  WatchHistorySyncService.swift
//  Yattee
//
//  Mirrors what is being watched here into the active account's server-side
//  history — best-effort, and never in playback's way.
//

import Foundation

/// Posts each played video to the account's server history once.
///
/// The local ``WatchEntry`` remains the sole source of truth for resume and
/// progress; this is a mirror on top of it, so nothing here can fail in a way
/// playback has to notice. A post that does not land is dropped after one
/// retry and never mentioned again.
///
/// Two rules shape everything else:
///
/// - **The account is captured when playback starts.** Switching context
///   mid-video must not redirect the post to whoever is selected by the time
///   the progress save happens — the video was watched under the account that
///   was active when it began.
/// - **De-duplication is per playback session, not per app run.** One POST for
///   one watch; playing the same video again is a new session and posts again,
///   which is what moves it back to the front of the server's history.
@MainActor
final class WatchHistorySyncService {
    /// One playback of one video, under the account that was active when it
    /// started.
    private struct Session {
        let videoID: String
        let accountID: UUID
        var posted: Bool
    }

    private let accountsManager: AccountsManager
    private let accountService: AccountService
    private let contextValidator: DataContextValidator

    private var currentSession: Session?

    /// Posts still in flight, so background suspension can wait for them and an
    /// account that goes away can disown them.
    private var pendingTasks: [UUID: (accountID: UUID, task: Task<Void, Never>)] = [:]

    init(
        accountsManager: AccountsManager,
        accountService: AccountService,
        contextValidator: DataContextValidator
    ) {
        self.accountsManager = accountsManager
        self.accountService = accountService
        self.contextValidator = contextValidator
    }

    // MARK: - Session lifecycle

    /// Starts a mirroring session for a video that is about to play.
    ///
    /// Called only for a genuinely new video. Reloads of the same one — the
    /// audio-mode toggle, a quality switch, a stream retry — must not reach
    /// here, or each of them would post again.
    func beginSession(video: Video) {
        currentSession = nil

        // Only YouTube content has an ID the Invidious history endpoint can
        // take. A PeerTube video, a file from a media source or anything
        // yt-dlp extracted carries an ID that means nothing there, and the
        // server answers 400 to it. This is the same predicate `supportsComments`
        // uses to decide whether a video exists on the backend at all.
        guard case .global(let provider) = video.id.source,
              provider == ContentSource.youtubeProvider
        else { return }

        // The *effective* context, not the stored one: while the selected
        // account is unusable the app reads local data, and a video watched in
        // that state was not watched under the account.
        guard case .account(let accountID) = contextValidator.effectiveContext,
              contextValidator.allowsServerMutations,
              let account = accountsManager.account(id: accountID),
              accountsManager.capabilities(for: account)?.supportsWatchHistory == true
        else { return }

        currentSession = Session(videoID: video.id.videoID, accountID: accountID, posted: false)
    }

    /// Ends the current session without posting anything further.
    func endSession() {
        currentSession = nil
    }

    /// Mirrors the session's video the first time its progress is saved.
    ///
    /// Called from the progress-saving paths, after their incognito and
    /// save-watch-history guards — so the same two settings that stop a local
    /// entry being written stop the server one too.
    func recordProgress(videoID: String) {
        guard var session = currentSession,
              session.videoID == videoID,
              !session.posted
        else { return }

        // Marked before the request leaves, not after it answers: progress is
        // saved every few seconds, and a second save landing while the first
        // post is still out would otherwise send it twice.
        session.posted = true
        currentSession = session

        let taskID = UUID()
        let accountID = session.accountID
        let task = Task { [weak self] in
            await self?.post(videoID: videoID, accountID: accountID)
            self?.pendingTasks[taskID] = nil
        }
        pendingTasks[taskID] = (accountID: accountID, task: task)
    }

    // MARK: - Posting

    /// Sends the post, once more if the first attempt failed, then gives up.
    private func post(videoID: String, accountID: UUID) async {
        for attempt in 0 ... 1 {
            if Task.isCancelled { return }

            // Resolved at post time rather than captured: the account may have
            // been deleted while the video played, and there is nothing left to
            // mirror to.
            guard let account = accountsManager.account(id: accountID) else { return }

            do {
                try await accountService.markWatched(videoID: videoID, for: account)
                return
            } catch is CancellationError {
                // The account was discarded or the app is going away. Not a
                // failure to retry.
                return
            } catch let error as AccountServiceError {
                // Signed out, instance switched off, backend cannot do it —
                // none of which a second attempt would resolve.
                LoggingService.shared.debug(
                    "Watch history mirror skipped for \(videoID): \(error)",
                    category: .api
                )
                return
            } catch {
                guard attempt == 0 else {
                    LoggingService.shared.debug(
                        "Watch history mirror dropped for \(videoID): \(error)",
                        category: .api
                    )
                    return
                }
            }
        }
    }

    // MARK: - Draining

    /// Waits for every post still in flight.
    ///
    /// Called when the app goes to background, inside the assertion that keeps
    /// it alive, so a video watched right up to suspension still reaches the
    /// server.
    /// Drains one at a time rather than awaiting a snapshot, so a post enqueued
    /// while the flush is already running is waited for too — and so each turn
    /// of the loop removes an entry, whatever the task itself did.
    func flushPending() async {
        while let (taskID, entry) = pendingTasks.first {
            await entry.task.value
            pendingTasks[taskID] = nil
        }
    }

    /// Disowns whatever is still being posted for an account, and forgets a
    /// session that belongs to it.
    ///
    /// Reached when an account is signed out, deleted, or its credential
    /// replaced — after any of which the post would either fail or, worse,
    /// land under somebody else's login.
    func cancelPending(for accountID: UUID) {
        for (taskID, entry) in pendingTasks where entry.accountID == accountID {
            entry.task.cancel()
            pendingTasks[taskID] = nil
        }

        if currentSession?.accountID == accountID {
            currentSession = nil
        }
    }
}
