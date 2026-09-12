//
//  CredentialProbeService.swift
//  Yattee
//
//  Confirms — or refuses to confirm — that a server really rejected an
//  account's credential.
//

import Foundation

/// Turns an auth-shaped failure into a verdict about the credential itself.
///
/// A raw 401 or 403 from an ordinary account request is not evidence: Invidious
/// answers 403 `{"error":"Request must be authenticated"}` for a revoked
/// session, but also for endpoints an otherwise valid session may not touch,
/// and a reverse proxy in front of either backend answers 401 for reasons that
/// have nothing to do with the account. Acting on the raw status would tell
/// users with a perfectly good login to sign in again — and drop their reads to
/// local data — on the strength of one unlucky request.
///
/// So the failure only *suspects* rejection. This service asks the question
/// again, deliberately, against an endpoint that exists purely to be
/// authenticated (the subscriptions list), and only that answer is allowed to
/// set `credentialRejected`. Everything else the probe can return maps to a
/// state that lifts by itself.
///
/// The transport and the credential lookup are injected so tests can script the
/// answer without a server, and so this file stays free of any API-client
/// knowledge.
@MainActor
final class CredentialProbeService {
    /// What a probe concluded about the credential it was given.
    enum Verdict: Equatable {
        /// The server accepted it — the original failure was about the
        /// operation, not the login.
        case authenticated
        /// The server refused it. The only verdict that marks an account.
        case rejected
        /// The server could not be asked. Says nothing about the credential.
        case unreachable
        /// The probe produced an answer that proves nothing either way — a
        /// decoding failure, a 500, a cancelled task. Status is left alone.
        case indeterminate
    }

    /// Performs one authenticated request with the given credential.
    typealias Transport = @MainActor (Instance, String) async -> Verdict

    /// The credential an account currently holds, or `nil` when there is none
    /// to be read — including while the identity scope is unresolved, which is
    /// "cannot tell yet" rather than "signed out".
    typealias CredentialReader = @MainActor (Account) -> String?

    private let accountsManager: AccountsManager
    private let credentialReader: CredentialReader
    private let transport: Transport

    /// How long an *answered* probe stands before another may run for the same
    /// account. A failing feed refresh can produce several auth-shaped failures
    /// in a row; without this each one would cost a round trip to say the same
    /// thing. Injectable so tests do not have to wait a real minute.
    private let cooldown: TimeInterval

    /// Probes currently in flight, keyed by account.
    ///
    /// Exposed because it is also the only way to await one: the probe is
    /// deliberately fire-and-forget from the caller's side — `recordServerOutcome`
    /// cannot become async — so tests need a handle to join on.
    private(set) var probeTasks: [UUID: Task<Void, Never>] = [:]

    /// When a probe last produced an answer *about the credential the account
    /// still holds*. A verdict dropped as stale never lands here: it says
    /// nothing about what is in place now, so it may not delay asking.
    private var lastProbeFinished: [UUID: Date] = [:]

    /// Bumped every time an account's credential is replaced.
    ///
    /// A probe carries the value it was spawned under and may only speak while
    /// it still matches. Cancellation alone would not do: the transport may not
    /// notice it for a while, and comparing the credential is not enough either
    /// — a replacement can happen to be the same string, and the comparison
    /// races with the gates being cleared.
    private var generations: [UUID: Int] = [:]

    init(
        accountsManager: AccountsManager,
        credentialReader: @escaping CredentialReader,
        transport: @escaping Transport,
        cooldown: TimeInterval = 60
    ) {
        self.accountsManager = accountsManager
        self.credentialReader = credentialReader
        self.transport = transport
        self.cooldown = cooldown
    }

    // MARK: - Probing

    /// Asks the server whether this account's credential is still good.
    ///
    /// Returns immediately; the verdict is applied to `AccountsManager` when the
    /// answer arrives, and only if it still describes the same credential on the
    /// same account.
    func probeSuspectedRejection(for account: Account) {
        guard probeTasks[account.id] == nil else { return }

        if let finished = lastProbeFinished[account.id],
           Date().timeIntervalSince(finished) < cooldown {
            return
        }

        // No credential to test. `refreshAccountStatuses` owns that verdict —
        // it can tell a missing credential from an unresolved identity scope,
        // and this service deliberately cannot.
        guard let credential = credentialReader(account) else { return }

        // An account whose instance has not arrived (or is already gone) has
        // nothing to probe against.
        guard let instance = accountsManager.instance(for: account) else { return }

        let accountID = account.id
        let generation = generations[accountID, default: 0]

        probeTasks[accountID] = Task { [weak self] in
            let verdict = await self?.transport(instance, credential)

            guard let self else { return }
            defer {
                // Only if this probe is still the one on record. A credential
                // change takes the slot away and a fresh probe may already be
                // using it; clearing it here would strand that one's dedup.
                if self.generations[accountID, default: 0] == generation {
                    self.probeTasks[accountID] = nil
                }
            }

            guard let verdict else { return }

            // The world may have moved while the probe was out. A verdict about
            // a credential that has since been replaced — or read under an
            // identity scope that has since flipped, which makes the reader
            // return `nil` — describes nothing that is still true, and applying
            // it would reject a login the user just fixed.
            guard self.generations[accountID, default: 0] == generation,
                  let current = self.accountsManager.account(id: accountID),
                  self.credentialReader(current) == credential
            else {
                LoggingService.shared.debug(
                    "Dropped a credential probe verdict — the account or its credential changed",
                    category: .general,
                    details: "accountID=\(accountID)"
                )
                return
            }

            // Stamped only here, on the one path where an answer about the
            // credential now in place was actually obtained. A dropped verdict
            // describes a secret that is gone, so it may not silence the first
            // probe of its replacement — the login the user just fixed is
            // exactly the one whose rejection has to be found quickly. Probe
            // storms are held off by the in-flight guard regardless.
            self.lastProbeFinished[accountID] = Date()

            self.apply(verdict, to: accountID)
        }
    }

    /// Retires everything this service knows about an account's *previous*
    /// credential.
    ///
    /// Both gates in `probeSuspectedRejection` are keyed by account alone and
    /// are checked before the credential is even read, so without this a
    /// replacement inherits the old secret's dedup: a finished probe would
    /// silence the new login's first failure for the whole cooldown, and one
    /// still in flight would silence it until that round trip returned. The
    /// replacement is the login the user just fixed — a rejection of *it* is
    /// the one worth finding immediately.
    ///
    /// The in-flight probe is cancelled as well as disowned, so a network call
    /// nobody will listen to is not left running.
    func credentialDidChange(for accountID: UUID) {
        generations[accountID, default: 0] += 1
        lastProbeFinished[accountID] = nil
        probeTasks.removeValue(forKey: accountID)?.cancel()
    }

    private func apply(_ verdict: Verdict, to accountID: UUID) {
        switch verdict {
        case .authenticated:
            // The credential works; whatever failed was about the request.
            accountsManager.setStatus(.signedIn, for: accountID)
        case .rejected:
            LoggingService.shared.info(
                "A credential probe confirmed the server rejects this account's login",
                category: .general,
                details: "accountID=\(accountID)"
            )
            accountsManager.setStatus(.credentialRejected, for: accountID)
        case .unreachable:
            // Recorded rather than ignored so reads fall back to local data,
            // and lifted again by the manager's own retry timer.
            accountsManager.setStatus(.unreachable, for: accountID)
        case .indeterminate:
            break
        }
    }

    // MARK: - Classification

    /// Maps a probe's outcome onto a verdict.
    ///
    /// `nil` means the request succeeded. Only the two auth statuses reject:
    /// 403 is included because Invidious answers it — not 401 — for a session
    /// that has been revoked, and it reaches here as a plain `httpError`
    /// because the global 403 mapping in `HTTPClient` is shared with
    /// unauthenticated call sites that read it as "blocked", not "signed out".
    static func classify(_ error: Error?) -> Verdict {
        guard let error else { return .authenticated }

        switch error {
        case APIError.unauthorized:
            return .rejected
        case let APIError.httpError(statusCode, _) where statusCode == 401 || statusCode == 403:
            return .rejected
        case APIError.timeout, APIError.noConnection, APIError.connectionFailed:
            // A refused connection or an unresolvable host answers the probe no
            // better than silence does: the question never reached anything
            // that could judge the credential.
            return .unreachable
        default:
            // Cancellation included: a probe that was torn down never asked the
            // question, so it may not answer it either.
            return .indeterminate
        }
    }
}
