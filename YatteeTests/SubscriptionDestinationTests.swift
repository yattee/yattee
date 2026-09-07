//
//  SubscriptionDestinationTests.swift
//  YatteeTests
//
//  Where a subscribe lands when the user names its destination, and what the
//  menu is allowed to claim about the answers it gets back.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Scripted provider

/// A ``SubscriptionProvider`` that answers from memory and records every call,
/// so a test can assert which destination a write was actually routed to.
@MainActor
private final class ScriptedSubscriptionProvider: SubscriptionProvider {
    let context: DataContext

    private(set) var subscribed: Set<String> = []
    private(set) var subscribeCalls: [String] = []
    private(set) var unsubscribeCalls: [String] = []
    private(set) var membershipCalls: [String] = []

    /// Thrown by the next write.
    var nextError: Error?

    /// While true, every call suspends until `release()`.
    var holdsCallsOpen = false
    private var parked: [CheckedContinuation<Void, Never>] = []

    init(context: DataContext, subscribed: Set<String> = []) {
        self.context = context
        self.subscribed = subscribed
    }

    func release() {
        holdsCallsOpen = false
        let waiting = parked
        parked = []
        waiting.forEach { $0.resume() }
    }

    private func park() async {
        if holdsCallsOpen {
            await withCheckedContinuation { parked.append($0) }
        }
    }

    func fetchSubscriptions() async throws -> [Channel] {
        subscribed.map { Channel(id: .global($0), name: $0) }
    }

    func subscribe(to channel: Channel) async throws {
        subscribeCalls.append(channel.id.channelID)
        await park()
        if let nextError { throw nextError }
        subscribed.insert(channel.id.channelID)
    }

    func unsubscribe(from channelID: String) async throws {
        unsubscribeCalls.append(channelID)
        await park()
        if let nextError { throw nextError }
        subscribed.remove(channelID)
    }

    func isSubscribed(to channelID: String) async -> Bool {
        membershipCalls.append(channelID)
        await park()
        return subscribed.contains(channelID)
    }

    var cachedSubscriptionCount: Int? { subscribed.count }
}

/// Hands out the scripted providers instead of building ones that would need a
/// server and a credential.
@MainActor
private final class ScriptedProviderFactory: SubscriptionProviderFactory {
    var providers: [UUID: ScriptedSubscriptionProvider] = [:]

    func provider(
        for account: Account,
        instance _: Instance,
        accountsManager _: AccountsManager
    ) -> (any SubscriptionProvider)? {
        providers[account.id]
    }
}

// MARK: - Routing

@MainActor
@Suite("Subscription destinations", .serialized)
struct SubscriptionDestinationRoutingTests {
    /// Everything one test needs: two signed-in accounts on their own
    /// instances, each with a provider that records what it was asked to do.
    @MainActor
    private struct Fixture {
        let service: SubscriptionService
        let dataManager: DataManager
        let accounts: AccountsManager
        let instances: InstancesManager
        let madeInstances: [Instance]
        let factory: ScriptedProviderFactory
        let first: Account
        let second: Account

        var firstProvider: ScriptedSubscriptionProvider { factory.providers[first.id]! }
        var secondProvider: ScriptedSubscriptionProvider { factory.providers[second.id]! }

        func tearDown() {
            for instance in madeInstances { instances.remove(instance) }
        }
    }

    private func makeFixture() throws -> Fixture {
        let instances = makeTestInstancesManager()
        let made = (0 ..< 2).map { index in
            Instance(
                type: .invidious,
                url: URL(string: "https://inv-\(index)-\(UUID().uuidString).example.com")!
            )
        }
        for instance in made { instances.add(instance) }

        let accounts = AccountsManager(
            identityScope: CredentialIdentityScope(fixedScope: "identity-A"),
            instancesManager: instances,
            defaults: UserDefaults(suiteName: "yattee.tests.\(UUID().uuidString)")!
        )
        let first = accounts.addAccount(instanceID: made[0].id)
        let second = accounts.addAccount(instanceID: made[1].id)

        let factory = ScriptedProviderFactory()
        factory.providers[first.id] = ScriptedSubscriptionProvider(context: .account(first.id))
        factory.providers[second.id] = ScriptedSubscriptionProvider(context: .account(second.id))

        let dataManager = try DataManager(inMemory: true)
        let service = SubscriptionService(dataManager: dataManager, providerFactory: factory)
        service.setAccountsManager(accounts)

        return Fixture(
            service: service,
            dataManager: dataManager,
            accounts: accounts,
            instances: instances,
            madeInstances: made,
            factory: factory,
            first: first,
            second: second
        )
    }

    private func channel(_ id: String = "UC-test") -> Channel {
        Channel(id: .global(id), name: "Channel \(id)")
    }

    @Test("A subscribe lands on the account it names, not the one selected")
    func subscribeRoutesToNamedDestination() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.accounts.setContext(.account(fixture.first.id))
        try await fixture.service.subscribe(to: channel(), in: .account(fixture.second.id))

        #expect(fixture.secondProvider.subscribeCalls == ["UC-test"])
        #expect(fixture.firstProvider.subscribeCalls.isEmpty)
    }

    @Test("An unsubscribe lands on the account it names")
    func unsubscribeRoutesToNamedDestination() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        try await fixture.service.subscribe(to: channel(), in: .account(fixture.second.id))
        try await fixture.service.unsubscribe(from: "UC-test", in: .account(fixture.second.id))

        #expect(fixture.secondProvider.unsubscribeCalls == ["UC-test"])
        #expect(fixture.firstProvider.unsubscribeCalls.isEmpty)
        #expect(await fixture.service.isSubscribed(to: "UC-test", in: .account(fixture.second.id)) == false)
    }

    @Test("The local destination writes to the device's own store")
    func localDestinationWritesLocally() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.accounts.setContext(.account(fixture.first.id))
        try await fixture.service.subscribe(to: channel(), in: .local)

        #expect(fixture.dataManager.isSubscribed(to: "UC-test"))
        #expect(fixture.firstProvider.subscribeCalls.isEmpty)
        #expect(await fixture.service.isSubscribed(to: "UC-test", in: .local) == true)
    }

    @Test("Membership is answered per destination")
    func membershipIsPerDestination() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        try await fixture.service.subscribe(to: channel(), in: .account(fixture.first.id))

        #expect(await fixture.service.isSubscribed(to: "UC-test", in: .account(fixture.first.id)) == true)
        #expect(await fixture.service.isSubscribed(to: "UC-test", in: .account(fixture.second.id)) == false)
        #expect(await fixture.service.isSubscribed(to: "UC-test", in: .local) == false)
    }

    @Test("Without a destination the current context is written")
    func implicitCallsUseTheCurrentContext() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.accounts.setContext(.account(fixture.second.id))
        try await fixture.service.subscribe(to: channel())

        #expect(fixture.secondProvider.subscribeCalls == ["UC-test"])
        #expect(fixture.firstProvider.subscribeCalls.isEmpty)
    }

    @Test("A named destination is written even while the selected account is unusable")
    func namedDestinationIgnoresTheSelectedContext() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        // An account with no instance and no provider: the selected context
        // cannot be written to at all, which is exactly when a destination row
        // is the only way to subscribe.
        let unusable = fixture.accounts.addAccount(instanceID: UUID())
        fixture.accounts.setContext(.account(unusable.id))

        await #expect(throws: Error.self) {
            try await fixture.service.subscribe(to: channel())
        }

        try await fixture.service.subscribe(to: channel(), in: .account(fixture.first.id))
        #expect(fixture.firstProvider.subscribeCalls == ["UC-test"])
    }

    @Test("A destination that cannot be served says nothing rather than 'not subscribed'")
    func unservableDestinationAnswersUnknown() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let unusable = fixture.accounts.addAccount(instanceID: UUID())

        #expect(await fixture.service.isSubscribed(to: "UC-test", in: .account(unusable.id)) == nil)
    }

    @Test("An answer that outlived its login is discarded")
    func staleMembershipAnswerIsDiscarded() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.firstProvider.holdsCallsOpen = true

        let pending = Task { await fixture.service.isSubscribed(to: "UC-test", in: .account(fixture.first.id)) }

        for _ in 0 ..< 200 where fixture.firstProvider.membershipCalls.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!fixture.firstProvider.membershipCalls.isEmpty)

        // Signing in as somebody else replaces every provider; the answer now
        // in flight belongs to the identity that left.
        fixture.service.discardAllProviders()
        fixture.firstProvider.release()

        #expect(await pending.value == nil)
    }
}

// MARK: - Membership state

@MainActor
@Suite("Subscription destination membership")
struct SubscriptionDestinationMembershipTests {
    @Test("Nothing is claimed before an answer arrives")
    func unknownUntilAnswered() {
        let membership = SubscriptionDestinationMembership()

        #expect(membership.isSubscribed(on: .local) == nil)
    }

    @Test("An answer is kept for the destination it was asked about")
    func answersAreKeptPerDestination() {
        let account = DataContext.account(UUID())
        var membership = SubscriptionDestinationMembership()

        membership.record(true, for: account, generation: membership.generation)
        membership.record(false, for: .local, generation: membership.generation)

        #expect(membership.isSubscribed(on: account) == true)
        #expect(membership.isSubscribed(on: .local) == false)
    }

    @Test("An answer with nothing to say is not stored as 'not subscribed'")
    func unknownAnswersAreNotStored() {
        var membership = SubscriptionDestinationMembership()

        membership.record(nil, for: .local, generation: membership.generation)

        #expect(membership.isSubscribed(on: .local) == nil)
    }

    @Test("A new round forgets what the last one learned")
    func invalidationForgetsAnswers() {
        var membership = SubscriptionDestinationMembership()
        membership.record(true, for: .local, generation: membership.generation)

        membership.invalidate()

        #expect(membership.isSubscribed(on: .local) == nil)
    }

    @Test("An answer from an abandoned round is dropped")
    func lateAnswersAreDropped() {
        var membership = SubscriptionDestinationMembership()
        let stale = membership.generation

        // The channel changed while the question was in flight.
        membership.invalidate()
        membership.record(true, for: .local, generation: stale)

        #expect(membership.isSubscribed(on: .local) == nil)

        membership.record(false, for: .local, generation: membership.generation)
        #expect(membership.isSubscribed(on: .local) == false)
    }
}
