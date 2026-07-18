//
//  InstancesManagerTests.swift
//  YatteeTests
//
//  Tests for the InstancesManager.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Instance Filtering Tests

@Suite("Instance Filtering Tests")
@MainActor
struct InstanceFilteringTests {

    @Test("Filter YouTube instances")
    func filterYouTubeInstances() {
        let instances = [
            Instance(type: .invidious, url: URL(string: "https://inv.example.com")!),
            Instance(type: .piped, url: URL(string: "https://piped.example.com")!),
            Instance(type: .peertube, url: URL(string: "https://pt.example.com")!),
        ]

        let youtubeInstances = instances.filter(\.isYouTubeInstance)
        #expect(youtubeInstances.count == 2)
        #expect(youtubeInstances.allSatisfy { $0.type == .invidious || $0.type == .piped })
    }

    @Test("Filter PeerTube instances")
    func filterPeerTubeInstances() {
        let instances = [
            Instance(type: .invidious, url: URL(string: "https://inv.example.com")!),
            Instance(type: .peertube, url: URL(string: "https://pt1.example.com")!),
            Instance(type: .peertube, url: URL(string: "https://pt2.example.com")!),
        ]

        let peertubeInstances = instances.filter(\.isPeerTubeInstance)
        #expect(peertubeInstances.count == 2)
        #expect(peertubeInstances.allSatisfy { $0.type == .peertube })
    }

    @Test("Filter enabled instances")
    func filterEnabledInstances() {
        var enabled = Instance(type: .invidious, url: URL(string: "https://enabled.example.com")!)
        enabled.isEnabled = true

        var disabled = Instance(type: .invidious, url: URL(string: "https://disabled.example.com")!)
        disabled.isEnabled = false

        let instances = [enabled, disabled]
        let enabledInstances = instances.filter(\.isEnabled)

        #expect(enabledInstances.count == 1)
        #expect(enabledInstances.first?.url.host == "enabled.example.com")
    }
}

// MARK: - Instance Type Tests

@Suite("InstanceType Tests")
@MainActor
struct InstanceTypeTests {

    @Test("InstanceType display names")
    func displayNames() {
        #expect(InstanceType.invidious.displayName == "Invidious")
        #expect(InstanceType.piped.displayName == "Piped")
        #expect(InstanceType.peertube.displayName == "PeerTube")
    }

    @Test("InstanceType is Codable")
    func codable() throws {
        for type in InstanceType.allCases {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(InstanceType.self, from: encoded)
            #expect(type == decoded)
        }
    }

    @Test("Instance is Codable")
    func instanceCodable() throws {
        let instance = Instance(
            type: .invidious,
            url: URL(string: "https://example.com")!,
            name: "Test Instance"
        )

        let encoded = try JSONEncoder().encode(instance)
        let decoded = try JSONDecoder().decode(Instance.self, from: encoded)

        #expect(instance.type == decoded.type)
        #expect(instance.url == decoded.url)
        #expect(instance.name == decoded.name)
    }

    @Test("Instance array is Codable")
    func instanceArrayCodable() throws {
        let instances = [
            Instance(type: .invidious, url: URL(string: "https://inv.example.com")!),
            Instance(type: .piped, url: URL(string: "https://piped.example.com")!),
            Instance(type: .peertube, url: URL(string: "https://pt.example.com")!, name: "My PeerTube"),
        ]

        let encoded = try JSONEncoder().encode(instances)
        let decoded = try JSONDecoder().decode([Instance].self, from: encoded)

        #expect(decoded.count == 3)
        #expect(decoded[0].type == .invidious)
        #expect(decoded[1].type == .piped)
        #expect(decoded[2].name == "My PeerTube")
    }
}

// MARK: - Instance Identity Tests

@Suite("Instance Identity Tests")
@MainActor
struct InstanceIdentityTests {

    @Test("Instances with same UUID are equal")
    func sameUUIDEqual() {
        let sharedID = UUID()
        let url = URL(string: "https://example.com")!
        let instance1 = Instance(id: sharedID, type: .invidious, url: url)
        let instance2 = Instance(id: sharedID, type: .invidious, url: url)

        #expect(instance1.id == instance2.id)
    }

    @Test("New instances have unique IDs")
    func newInstancesHaveUniqueIDs() {
        let instance1 = Instance(type: .invidious, url: URL(string: "https://example.com")!)
        let instance2 = Instance(type: .invidious, url: URL(string: "https://example.com")!)

        // Each new instance gets a unique UUID
        #expect(instance1.id != instance2.id)
    }

    @Test("Instance ID is stable across name changes")
    func idStableAcrossNameChanges() {
        var instance = Instance(type: .invidious, url: URL(string: "https://example.com")!)
        let originalID = instance.id

        instance.name = "New Name"
        #expect(instance.id == originalID)
    }
}
