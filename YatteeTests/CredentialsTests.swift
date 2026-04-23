//
//  CredentialsTests.swift
//  YatteeTests
//
//  Tests for credential managers (Invidious and Piped).
//

import Testing
import Foundation
@testable import Yattee

// MARK: - PipedCredentialsManager Tests

@Suite("PipedCredentialsManager Tests")
@MainActor
struct PipedCredentialsManagerTests {

    private func createTestInstance() -> Instance {
        Instance(type: .piped, url: URL(string: "https://piped.test.example")!)
    }

    @Test("setCredential stores token and updates loggedInInstanceIDs")
    func setCredentialStoresToken() {
        let manager = PipedCredentialsManager()
        let instance = createTestInstance()
        let token = "test-auth-token-\(UUID().uuidString)"

        manager.setCredential(token, for: instance)

        #expect(manager.loggedInInstanceIDs.contains(instance.id))

        // Cleanup
        manager.deleteCredential(for: instance)
    }

    @Test("credential retrieves stored token")
    func credentialRetrievesToken() {
        let manager = PipedCredentialsManager()
        let instance = createTestInstance()
        let token = "test-auth-token-\(UUID().uuidString)"

        manager.setCredential(token, for: instance)
        let retrieved = manager.credential(for: instance)

        #expect(retrieved == token)

        // Cleanup
        manager.deleteCredential(for: instance)
    }

    @Test("credential returns nil for unknown instance")
    func credentialReturnsNilForUnknown() {
        let manager = PipedCredentialsManager()
        let instance = createTestInstance()

        let retrieved = manager.credential(for: instance)

        #expect(retrieved == nil)
    }

    @Test("deleteCredential removes token and updates loggedInInstanceIDs")
    func deleteCredentialRemovesToken() {
        let manager = PipedCredentialsManager()
        let instance = createTestInstance()
        let token = "test-auth-token-\(UUID().uuidString)"

        manager.setCredential(token, for: instance)
        #expect(manager.loggedInInstanceIDs.contains(instance.id))

        manager.deleteCredential(for: instance)

        #expect(!manager.loggedInInstanceIDs.contains(instance.id))
        #expect(manager.credential(for: instance) == nil)
    }

    @Test("isLoggedIn returns true when logged in")
    func isLoggedInReturnsTrue() {
        let manager = PipedCredentialsManager()
        let instance = createTestInstance()
        let token = "test-auth-token-\(UUID().uuidString)"

        manager.setCredential(token, for: instance)

        #expect(manager.isLoggedIn(for: instance) == true)

        // Cleanup
        manager.deleteCredential(for: instance)
    }

    @Test("isLoggedIn returns false when not logged in")
    func isLoggedInReturnsFalse() {
        let manager = PipedCredentialsManager()
        let instance = createTestInstance()

        #expect(manager.isLoggedIn(for: instance) == false)
    }

    @Test("refreshLoginStatus syncs loggedInInstanceIDs with Keychain")
    func refreshLoginStatusSyncs() {
        let manager = PipedCredentialsManager()
        let instance = createTestInstance()
        let token = "test-auth-token-\(UUID().uuidString)"

        // Store credential
        manager.setCredential(token, for: instance)

        // Simulate stale state by manually removing from tracked set
        // (This tests the refresh mechanism)
        let freshManager = PipedCredentialsManager()
        #expect(!freshManager.loggedInInstanceIDs.contains(instance.id))

        freshManager.refreshLoginStatus(for: instance)
        #expect(freshManager.loggedInInstanceIDs.contains(instance.id))

        // Cleanup
        manager.deleteCredential(for: instance)
    }

    @Test("setCredential updates existing token")
    func setCredentialUpdatesExisting() {
        let manager = PipedCredentialsManager()
        let instance = createTestInstance()
        let token1 = "test-auth-token-1-\(UUID().uuidString)"
        let token2 = "test-auth-token-2-\(UUID().uuidString)"

        manager.setCredential(token1, for: instance)
        #expect(manager.credential(for: instance) == token1)

        manager.setCredential(token2, for: instance)
        #expect(manager.credential(for: instance) == token2)

        // Cleanup
        manager.deleteCredential(for: instance)
    }

    @Test("Multiple instances have separate credentials")
    func multipleInstancesSeparateCredentials() {
        let manager = PipedCredentialsManager()
        let instance1 = Instance(type: .piped, url: URL(string: "https://piped1.test.example")!)
        let instance2 = Instance(type: .piped, url: URL(string: "https://piped2.test.example")!)
        let token1 = "token-1-\(UUID().uuidString)"
        let token2 = "token-2-\(UUID().uuidString)"

        manager.setCredential(token1, for: instance1)
        manager.setCredential(token2, for: instance2)

        #expect(manager.credential(for: instance1) == token1)
        #expect(manager.credential(for: instance2) == token2)
        #expect(manager.loggedInInstanceIDs.count >= 2)

        // Cleanup
        manager.deleteCredential(for: instance1)
        manager.deleteCredential(for: instance2)
    }
}

// MARK: - InvidiousCredentialsManager Tests

@Suite("InvidiousCredentialsManager Tests")
@MainActor
struct InvidiousCredentialsManagerTests {

    private func createTestInstance() -> Instance {
        Instance(type: .invidious, url: URL(string: "https://invidious.test.example")!)
    }

    @Test("setSID stores session and updates loggedInInstanceIDs")
    func setSIDStoresSession() {
        let manager = InvidiousCredentialsManager()
        let instance = createTestInstance()
        let sid = "test-session-id-\(UUID().uuidString)"

        manager.setSID(sid, for: instance)

        #expect(manager.loggedInInstanceIDs.contains(instance.id))

        // Cleanup
        manager.deleteSID(for: instance)
    }

    @Test("sid retrieves stored session")
    func sidRetrievesSession() {
        let manager = InvidiousCredentialsManager()
        let instance = createTestInstance()
        let sid = "test-session-id-\(UUID().uuidString)"

        manager.setSID(sid, for: instance)
        let retrieved = manager.sid(for: instance)

        #expect(retrieved == sid)

        // Cleanup
        manager.deleteSID(for: instance)
    }

    @Test("sid returns nil for unknown instance")
    func sidReturnsNilForUnknown() {
        let manager = InvidiousCredentialsManager()
        let instance = createTestInstance()

        let retrieved = manager.sid(for: instance)

        #expect(retrieved == nil)
    }

    @Test("deleteSID removes session and updates loggedInInstanceIDs")
    func deleteSIDRemovesSession() {
        let manager = InvidiousCredentialsManager()
        let instance = createTestInstance()
        let sid = "test-session-id-\(UUID().uuidString)"

        manager.setSID(sid, for: instance)
        #expect(manager.loggedInInstanceIDs.contains(instance.id))

        manager.deleteSID(for: instance)

        #expect(!manager.loggedInInstanceIDs.contains(instance.id))
        #expect(manager.sid(for: instance) == nil)
    }

    @Test("Protocol methods delegate correctly")
    func protocolMethodsDelegate() {
        let manager = InvidiousCredentialsManager()
        let instance = createTestInstance()
        let sid = "test-session-id-\(UUID().uuidString)"

        // Test setCredential -> setSID
        manager.setCredential(sid, for: instance)
        #expect(manager.sid(for: instance) == sid)

        // Test credential -> sid
        #expect(manager.credential(for: instance) == sid)

        // Test deleteCredential -> deleteSID
        manager.deleteCredential(for: instance)
        #expect(manager.sid(for: instance) == nil)
    }

    @Test("isLoggedIn returns correct state")
    func isLoggedInReturnsCorrectState() {
        let manager = InvidiousCredentialsManager()
        let instance = createTestInstance()
        let sid = "test-session-id-\(UUID().uuidString)"

        #expect(manager.isLoggedIn(for: instance) == false)

        manager.setSID(sid, for: instance)
        #expect(manager.isLoggedIn(for: instance) == true)

        manager.deleteSID(for: instance)
        #expect(manager.isLoggedIn(for: instance) == false)
    }

    @Test("Thumbnail cache stores and retrieves URLs")
    func thumbnailCacheWorks() {
        let manager = InvidiousCredentialsManager()
        let channelID = "UC\(UUID().uuidString.prefix(22))"
        let thumbnailURL = URL(string: "https://example.com/thumb.jpg")!

        manager.setThumbnailURL(thumbnailURL, forChannelID: channelID)
        let retrieved = manager.thumbnailURL(forChannelID: channelID)

        #expect(retrieved == thumbnailURL)

        // Cleanup
        manager.clearThumbnailCache()
    }

    @Test("uncachedChannelIDs filters correctly")
    func uncachedChannelIDsFilters() {
        let manager = InvidiousCredentialsManager()
        let cachedID = "UCcached\(UUID().uuidString.prefix(16))"
        let uncachedID = "UCuncached\(UUID().uuidString.prefix(14))"

        manager.setThumbnailURL(URL(string: "https://example.com/thumb.jpg")!, forChannelID: cachedID)

        let uncached = manager.uncachedChannelIDs(from: [cachedID, uncachedID])

        #expect(uncached.count == 1)
        #expect(uncached.contains(uncachedID))
        #expect(!uncached.contains(cachedID))

        // Cleanup
        manager.clearThumbnailCache()
    }

    @Test("setThumbnailURLs batches correctly")
    func setThumbnailURLsBatches() {
        let manager = InvidiousCredentialsManager()
        let id1 = "UC1\(UUID().uuidString.prefix(19))"
        let id2 = "UC2\(UUID().uuidString.prefix(19))"
        let url1 = URL(string: "https://example.com/thumb1.jpg")!
        let url2 = URL(string: "https://example.com/thumb2.jpg")!

        manager.setThumbnailURLs([id1: url1, id2: url2])

        #expect(manager.thumbnailURL(forChannelID: id1) == url1)
        #expect(manager.thumbnailURL(forChannelID: id2) == url2)

        // Cleanup
        manager.clearThumbnailCache()
    }
}

// MARK: - InstanceCredentialsManager Protocol Tests

@Suite("InstanceCredentialsManager Protocol Tests")
@MainActor
struct InstanceCredentialsManagerProtocolTests {

    @Test("PipedCredentialsManager conforms to protocol")
    func pipedConformsToProtocol() {
        let manager: InstanceCredentialsManager = PipedCredentialsManager()
        let instance = Instance(type: .piped, url: URL(string: "https://piped.test.example")!)
        let token = "protocol-test-\(UUID().uuidString)"

        manager.setCredential(token, for: instance)
        #expect(manager.credential(for: instance) == token)
        #expect(manager.isLoggedIn(for: instance) == true)

        manager.deleteCredential(for: instance)
        #expect(manager.isLoggedIn(for: instance) == false)
    }

    @Test("InvidiousCredentialsManager conforms to protocol")
    func invidiousConformsToProtocol() {
        let manager: InstanceCredentialsManager = InvidiousCredentialsManager()
        let instance = Instance(type: .invidious, url: URL(string: "https://invidious.test.example")!)
        let sid = "protocol-test-\(UUID().uuidString)"

        manager.setCredential(sid, for: instance)
        #expect(manager.credential(for: instance) == sid)
        #expect(manager.isLoggedIn(for: instance) == true)

        manager.deleteCredential(for: instance)
        #expect(manager.isLoggedIn(for: instance) == false)
    }
}
