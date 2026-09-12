//
//  CredentialProbeTests.swift
//  YatteeTests
//
//  The two-stage rule: an auth-shaped failure only ever *suspects* rejection,
//  and nothing but a deliberate probe may confirm it.
//

import Testing
import Foundation
@testable import Yattee

/// A probe service wired to a scripted transport instead of a server.
///
/// Holds the credential in a mutable box so a test can replace it mid-probe,
/// and can park every probe inside the transport so the window between "the
/// request failed" and "the probe answered" can be inspected — that window is
/// where the whole design lives.
@MainActor
private final class ProbeHarness {
    let instances: InstancesManager
    let instance: Instance
    let accounts: AccountsManager
    let account: Account
    private(set) var service: CredentialProbeService!

    /// What the credential reader reports right now.
    var credential: String? = "sid-original"

    /// What the next probe concludes.
    var verdict: CredentialProbeService.Verdict = .authenticated

    /// Per-credential answers, for the tests where two probes overlap and each
    /// has to conclude something different.
    var verdictsByCredential: [String: CredentialProbeService.Verdict] = [:]

    private(set) var transportCalls = 0
    private(set) var probedCredentials: [String] = []

    /// While true, every probe suspends inside the transport until `release()`.
    var holdsProbesOpen = false
    private var parked: [(credential: String, continuation: CheckedContinuation<Void, Never>)] = []

    init(
        type: InstanceType = .invidious,
        usesBasicAuth: Bool = false,
        cooldown: TimeInterval = 0,
        unreachableRetryInterval: TimeInterval = 60
    ) {
        instances = makeTestInstancesManager()
        instance = Instance(
            type: type,
            url: URL(string: "https://probe-\(UUID().uuidString).example.com")!,
            usesBasicAuth: usesBasicAuth
        )
        instances.add(instance)

        accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            instancesManager: instances,
            defaults: UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!,
            unreachableRetryInterval: unreachableRetryInterval
        )
        account = accounts.addAccount(instanceID: instance.id)
        accounts.setStatus(.signedIn, for: account.id)

        service = CredentialProbeService(
            accountsManager: accounts,
            credentialReader: { [weak self] _ in self?.credential },
            transport: { [weak self] _, credential in
                guard let self else { return .indeterminate }
                return await self.runProbe(credential)
            },
            cooldown: cooldown
        )

        accounts.onSuspectedCredentialRejection = { [weak self] account in
            self?.service.probeSuspectedRejection(for: account)
        }
    }

    /// Instances live in the shared defaults, so each harness has to take its
    /// own back out again.
    func tearDown() {
        instances.remove(instance)
    }

    var status: AccountStatus {
        accounts.status(for: account.id)
    }

    var probeTask: Task<Void, Never>? {
        service.probeTasks[account.id]
    }

    func record(_ error: Error?) {
        accounts.recordServerOutcome(error, for: account)
    }

    private func runProbe(_ credential: String) async -> CredentialProbeService.Verdict {
        transportCalls += 1
        probedCredentials.append(credential)

        if holdsProbesOpen {
            await withCheckedContinuation { parked.append((credential, $0)) }
        }

        return verdictsByCredential[credential] ?? verdict
    }

    /// Lets parked probes finish — the one probing `credential`, or every one
    /// of them when it is `nil`, which also stops new probes being parked.
    func release(credential: String? = nil) {
        guard let credential else {
            holdsProbesOpen = false
            let waiting = parked
            parked = []
            waiting.forEach { $0.continuation.resume() }
            return
        }

        let matching = parked.filter { $0.credential == credential }
        parked.removeAll { $0.credential == credential }
        matching.forEach { $0.continuation.resume() }
    }

    /// Waits until the transport has been entered at least `count` times.
    func waitForTransport(count: Int) async throws {
        for _ in 0 ..< 200 {
            if transportCalls >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The transport was never entered \(count) time(s)")
    }
}

@Suite("Credential probe", .serialized)
@MainActor
struct CredentialProbeTests {
    // MARK: - The raw status never decides

    @Test("A 403 asks the server again instead of rejecting the login")
    func forbiddenNeverRejectsDirectly() async throws {
        let harness = ProbeHarness()
        defer { harness.tearDown() }
        harness.holdsProbesOpen = true
        harness.verdict = .rejected

        harness.record(APIError.httpError(statusCode: 403, message: "Request must be authenticated"))

        // Invidious answers exactly this for a revoked session — and for
        // several things that are not one. The failed request may not conclude
        // anything by itself.
        #expect(harness.status == .signedIn)

        try await harness.waitForTransport(count: 1)
        #expect(harness.status == .signedIn)

        let task = try #require(harness.probeTask)
        harness.release()
        await task.value

        // Only the probe's own answer marks the account.
        #expect(harness.status == .credentialRejected)
    }

    @Test("An unauthorized error goes through the probe as well")
    func unauthorizedRoutesThroughTheProbe() async throws {
        let harness = ProbeHarness()
        defer { harness.tearDown() }
        harness.holdsProbesOpen = true
        harness.verdict = .rejected

        harness.record(APIError.unauthorized)

        // A bare 401 used to reject on the spot. A reverse proxy answers it too.
        #expect(harness.status == .signedIn)

        try await harness.waitForTransport(count: 1)
        let task = try #require(harness.probeTask)
        harness.release()
        await task.value

        #expect(harness.status == .credentialRejected)
    }

    // MARK: - Verdicts

    @Test("A confirmed rejection makes the selected context fall back to local")
    func confirmedRejectionEngagesTheFallback() async throws {
        let harness = ProbeHarness()
        defer { harness.tearDown() }
        harness.verdict = .rejected

        let validator = DataContextValidator(
            accountsManager: harness.accounts,
            instancesManager: harness.instances,
            toastManager: ToastManager()
        )
        harness.accounts.setContext(.account(harness.account.id))
        #expect(validator.validity == .valid)

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        await harness.probeTask?.value

        #expect(harness.status == .credentialRejected)

        // The point of the whole exercise: reads stop going to a server that
        // will not answer them, without the user's choice being thrown away.
        #expect(validator.validity == .temporarilyUnavailable(.credentialRejected))
        #expect(validator.effectiveContext == .local)
        #expect(!validator.allowsServerMutations)
        #expect(harness.accounts.currentContext == .account(harness.account.id))
    }

    @Test("A probe the server accepts leaves the account signed in")
    func acceptedProbeKeepsTheAccountUsable() async throws {
        let harness = ProbeHarness()
        defer { harness.tearDown() }
        harness.verdict = .authenticated

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        await harness.probeTask?.value

        // The credential is fine; the operation that failed was not allowed.
        #expect(harness.transportCalls == 1)
        #expect(harness.status == .signedIn)
    }

    @Test("A probe that cannot reach the server is retried, not written off")
    func unreachableProbeLiftsItself() async throws {
        let harness = ProbeHarness(unreachableRetryInterval: 0.05)
        defer { harness.tearDown() }
        harness.verdict = .unreachable

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        await harness.probeTask?.value

        #expect(harness.status == .unreachable)

        // Nothing about the credential was learned, so the state has to expire
        // on its own — the same auto-expiry every unreachable account gets.
        try await Task.sleep(for: .seconds(0.5))
        #expect(harness.status == .signedIn)
    }

    @Test("A refused connection marks the account unreachable and lifts again")
    func refusedConnectionMarksUnreachable() async throws {
        let harness = ProbeHarness(unreachableRetryInterval: 0.05)
        defer { harness.tearDown() }

        // A server that answers "no" instantly used to arrive as an unknown
        // error, which nothing classified: the account went on calling itself
        // signed in, reads never fell back and no retry was ever scheduled.
        harness.record(APIError.connectionFailed("Could not connect to the server."))
        #expect(harness.status == .unreachable)

        // Nothing was learned about the credential, so it rides the same expiry.
        try await Task.sleep(for: .seconds(0.5))
        #expect(harness.status == .signedIn)

        // And it is not an auth question: no probe was spent on it.
        #expect(harness.transportCalls == 0)
    }

    @Test("A host that does not resolve is unreachable too")
    func unresolvableHostMarksUnreachable() async throws {
        let harness = ProbeHarness()
        defer { harness.tearDown() }

        harness.record(
            APIError.connectionFailed("A server with the specified hostname could not be found.")
        )
        #expect(harness.status == .unreachable)
    }

    // MARK: - What must not be probed

    @Test("An instance behind basic auth is never probed")
    func basicAuthInstanceIsNotProbed() async throws {
        let harness = ProbeHarness(usesBasicAuth: true)
        defer { harness.tearDown() }
        harness.verdict = .rejected

        harness.record(APIError.httpError(statusCode: 401, message: nil))
        harness.record(APIError.unauthorized)

        try await Task.sleep(for: .milliseconds(50))

        // The proxy answers 401 for every request to this instance whoever
        // makes it, and would answer the probe identically.
        #expect(harness.transportCalls == 0)
        #expect(harness.probeTask == nil)
        #expect(harness.status == .signedIn)
    }

    @Test("Errors that are not about authentication start no probe")
    func nonAuthErrorsDoNotProbe() async throws {
        let harness = ProbeHarness()
        defer { harness.tearDown() }
        harness.verdict = .rejected

        harness.record(APIError.httpError(statusCode: 500, message: "Internal Server Error"))
        #expect(harness.probeTask == nil)

        harness.record(APIError.decodingError("unexpected shape"))
        #expect(harness.probeTask == nil)

        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.transportCalls == 0)
        #expect(harness.status == .signedIn)
    }

    // MARK: - Staleness and dedup

    @Test("A verdict about a credential that has since been replaced is dropped")
    func replacedCredentialDropsTheVerdict() async throws {
        let harness = ProbeHarness()
        defer { harness.tearDown() }
        harness.holdsProbesOpen = true
        harness.verdict = .rejected

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        try await harness.waitForTransport(count: 1)

        // A replacement arriving over iCloud Keychain — or the user signing in
        // again — while the probe was out. The answer describes the old secret.
        harness.credential = "sid-replacement"

        let task = try #require(harness.probeTask)
        harness.release()
        await task.value

        #expect(harness.probedCredentials == ["sid-original"])
        #expect(harness.status == .signedIn)
    }

    @Test("A dropped verdict never silences the replacement credential's first probe")
    func droppedVerdictStartsNoCooldown() async throws {
        let harness = ProbeHarness(cooldown: 60)
        defer { harness.tearDown() }
        harness.holdsProbesOpen = true
        harness.verdict = .rejected

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        try await harness.waitForTransport(count: 1)

        harness.credential = "sid-replacement"
        let dropped = try #require(harness.probeTask)
        harness.release()
        await dropped.value
        #expect(harness.status == .signedIn)

        // The replacement can be rejected too, and nothing has asked about it
        // yet — the login the user just fixed is exactly the one whose failure
        // has to be found quickly, not a minute later.
        harness.record(APIError.httpError(statusCode: 403, message: nil))
        let second = try #require(harness.probeTask)
        await second.value

        #expect(harness.transportCalls == 2)
        #expect(harness.probedCredentials == ["sid-original", "sid-replacement"])
        #expect(harness.status == .credentialRejected)
    }

    @Test("Replacing the credential retires the cooldown the old one earned")
    func credentialChangeClearsTheCooldown() async throws {
        let harness = ProbeHarness(cooldown: 60)
        defer { harness.tearDown() }
        harness.verdict = .authenticated

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        await harness.probeTask?.value
        #expect(harness.transportCalls == 1)

        // Both gates are keyed by account alone and are checked before the
        // credential is even read, so the new login would otherwise inherit the
        // old one's silence for a full minute.
        harness.credential = "sid-replacement"
        harness.service.credentialDidChange(for: harness.account.id)
        harness.verdict = .rejected

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        let second = try #require(harness.probeTask)
        await second.value

        #expect(harness.transportCalls == 2)
        #expect(harness.probedCredentials == ["sid-original", "sid-replacement"])
        #expect(harness.status == .credentialRejected)
    }

    @Test("A probe left over from a replaced credential is disowned, not merely stale")
    func credentialChangeInvalidatesAProbeInFlight() async throws {
        let harness = ProbeHarness(cooldown: 60)
        defer { harness.tearDown() }
        harness.holdsProbesOpen = true
        harness.verdictsByCredential = [
            "sid-original": .rejected,
            "sid-replacement": .authenticated
        ]

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        try await harness.waitForTransport(count: 1)
        let stale = try #require(harness.probeTask)

        harness.credential = "sid-replacement"
        harness.service.credentialDidChange(for: harness.account.id)

        // Disowned and cancelled: nobody is going to listen to its answer.
        #expect(harness.probeTask == nil)
        #expect(stale.isCancelled)

        // The replacement's own failure is examined at once rather than waiting
        // out a round trip that is about a secret nobody holds any more.
        harness.record(APIError.httpError(statusCode: 403, message: nil))
        let fresh = try #require(harness.probeTask)
        #expect(fresh != stale)
        try await harness.waitForTransport(count: 2)

        harness.release(credential: "sid-original")
        await stale.value

        // The late rejection belongs to the old secret and may not be spoken —
        // nor may finishing evict the probe that has taken its place.
        #expect(harness.status == .signedIn)
        #expect(harness.probeTask == fresh)

        harness.release(credential: "sid-replacement")
        await fresh.value

        #expect(harness.transportCalls == 2)
        #expect(harness.probedCredentials == ["sid-original", "sid-replacement"])
        #expect(harness.status == .signedIn)
        #expect(harness.probeTask == nil)
    }

    @Test("Repeated failures while a probe is in flight cost one round trip")
    func concurrentTriggersDedupe() async throws {
        let harness = ProbeHarness()
        defer { harness.tearDown() }
        harness.holdsProbesOpen = true
        harness.verdict = .rejected

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        try await harness.waitForTransport(count: 1)

        // A feed refresh produces a burst of these.
        harness.record(APIError.httpError(statusCode: 403, message: nil))
        harness.record(APIError.unauthorized)

        let task = try #require(harness.probeTask)
        harness.release()
        await task.value

        #expect(harness.transportCalls == 1)
        #expect(harness.status == .credentialRejected)
    }

    @Test("A finished probe stands for the cooldown")
    func cooldownSuppressesAnImmediateReprobe() async throws {
        let harness = ProbeHarness(cooldown: 60)
        defer { harness.tearDown() }
        harness.verdict = .authenticated

        harness.record(APIError.httpError(statusCode: 403, message: nil))
        await harness.probeTask?.value
        #expect(harness.transportCalls == 1)

        // The next failed request arrives moments later and asks the same
        // question; the answer cannot have changed.
        harness.record(APIError.httpError(statusCode: 403, message: nil))
        #expect(harness.probeTask == nil)

        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.transportCalls == 1)
        #expect(harness.status == .signedIn)
    }

    // MARK: - Classification

    @Test("Only the two authentication statuses reject")
    func classifyMapsOutcomes() {
        #expect(CredentialProbeService.classify(nil) == .authenticated)

        #expect(CredentialProbeService.classify(APIError.unauthorized) == .rejected)
        #expect(CredentialProbeService.classify(
            APIError.httpError(statusCode: 401, message: nil)
        ) == .rejected)
        // The one the shared HTTP mapping leaves untranslated.
        #expect(CredentialProbeService.classify(
            APIError.httpError(statusCode: 403, message: "Request must be authenticated")
        ) == .rejected)

        #expect(CredentialProbeService.classify(APIError.timeout) == .unreachable)
        #expect(CredentialProbeService.classify(APIError.noConnection) == .unreachable)
        // A host that refuses the connection, or does not resolve, answered
        // nothing about the credential either.
        #expect(CredentialProbeService.classify(
            APIError.connectionFailed("Could not connect to the server.")
        ) == .unreachable)

        // A probe that never completed answers nothing.
        #expect(CredentialProbeService.classify(APIError.cancelled) == .indeterminate)
        #expect(CredentialProbeService.classify(
            APIError.httpError(statusCode: 500, message: nil)
        ) == .indeterminate)
    }

    // MARK: - Regression

    @Test("A successful request still lifts a rejection")
    func successLiftsARejection() {
        let harness = ProbeHarness()
        defer { harness.tearDown() }

        harness.accounts.setStatus(.credentialRejected, for: harness.account.id)
        harness.record(nil)

        #expect(harness.status == .signedIn)
    }
}
