//
//  InstancesManager.swift
//  Yattee
//
//  Manages configured backend instances with iCloud sync.
//

import Foundation
import SwiftUI

/// Status of an instance's connectivity and authentication.
enum InstanceStatus: Equatable {
    /// Instance is online and working.
    case online
    /// Instance is offline or unreachable.
    case offline
    /// Instance requires authentication but credentials are not provided.
    case authRequired
    /// Instance authentication failed (wrong credentials).
    case authFailed
}

/// Manages the list of configured backend instances with iCloud sync.
@MainActor
@Observable
final class InstancesManager {
    // MARK: - Storage

    private let localDefaults = UserDefaults.standard
    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let instancesKey = "configuredInstances"
    private let activeInstanceKey = "activeInstanceID"

    // MARK: - Dependencies

    private weak var settingsManager: SettingsManager?

    // MARK: - State

    private(set) var instances: [Instance] = []
    private(set) var activeInstanceID: UUID?

    /// Current status of each instance, keyed by instance ID.
    private(set) var instanceStatuses: [UUID: InstanceStatus] = [:]

    // MARK: - Initialization

    init(settingsManager: SettingsManager? = nil) {
        self.settingsManager = settingsManager

        loadInstances()
        loadActiveInstance()

        // Listen for external changes from iCloud
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleiCloudChange()
            }
        }
    }

    /// Sets the settings manager reference for checking iCloud sync status.
    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
    }

    /// Whether iCloud sync is currently enabled.
    private var iCloudSyncEnabled: Bool {
        settingsManager?.iCloudSyncEnabled ?? false
    }

    /// Whether instance sync is enabled (requires both master toggle and category toggle).
    private var instanceSyncEnabled: Bool {
        iCloudSyncEnabled && (settingsManager?.syncInstances ?? true)
    }

    /// Handles external iCloud changes by replacing local data with iCloud data.
    private func handleiCloudChange() {
        // Only process iCloud changes if instance sync is enabled
        guard instanceSyncEnabled else { return }

        guard let iCloudData = ubiquitousStore.data(forKey: instancesKey),
              let iCloudInstances = try? JSONDecoder().decode([Instance].self, from: iCloudData) else {
            return
        }

        // Replace local instances with iCloud data
        instances = iCloudInstances
        // Save to local defaults for offline access
        localDefaults.set(iCloudData, forKey: instancesKey)

        // Update sync time
        settingsManager?.updateLastSyncTime()
    }

    /// Syncs local data to iCloud (called when enabling iCloud sync).
    /// Only syncs if instance sync is enabled.
    func syncToiCloud() {
        guard instanceSyncEnabled else { return }

        guard let data = try? JSONEncoder().encode(instances) else { return }
        ubiquitousStore.set(data, forKey: instancesKey)
        ubiquitousStore.synchronize()
        settingsManager?.updateLastSyncTime()
    }

    /// Replaces local data with iCloud data (called when enabling iCloud sync).
    /// Only replaces if instance sync is enabled.
    func replaceWithiCloudData() {
        guard instanceSyncEnabled else { return }

        ubiquitousStore.synchronize()

        guard let iCloudData = ubiquitousStore.data(forKey: instancesKey),
              let iCloudInstances = try? JSONDecoder().decode([Instance].self, from: iCloudData) else {
            // No iCloud data exists, sync local data to iCloud
            syncToiCloud()
            return
        }

        // Replace local with iCloud data
        instances = iCloudInstances
        localDefaults.set(iCloudData, forKey: instancesKey)
        settingsManager?.updateLastSyncTime()
    }

    // MARK: - Public Methods

    func add(_ instance: Instance) {
        instances.append(instance)
        saveInstances()
    }

    func remove(_ instance: Instance) {
        instances.removeAll { $0.id == instance.id }

        // Clear active instance if it was the removed one
        if activeInstanceID == instance.id {
            activeInstanceID = nil
            localDefaults.removeObject(forKey: activeInstanceKey)
        }

        saveInstances()
    }

    func update(_ instance: Instance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
            saveInstances()
        }
    }

    /// Alias for add method to maintain consistency.
    func addInstance(_ instance: Instance) {
        add(instance)
    }

    /// Toggles the enabled state of an instance.
    func toggleEnabled(_ instance: Instance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            var updated = instances[index]
            updated.isEnabled.toggle()
            instances[index] = updated
            saveInstances()
        }
    }

    /// Sets the given instance as the primary (first) instance.
    func setPrimary(_ instance: Instance) {
        LoggingService.shared.debug("[InstancesManager] setPrimary called for: \(instance.displayName)", category: .general)
        LoggingService.shared.debug("[InstancesManager] Current instances: \(instances.map { $0.displayName })", category: .general)

        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else {
            LoggingService.shared.debug("[InstancesManager] Instance not found in list", category: .general)
            return
        }

        if index == 0 {
            LoggingService.shared.debug("[InstancesManager] Instance already at index 0, skipping", category: .general)
            return
        }

        LoggingService.shared.debug("[InstancesManager] Moving instance from index \(index) to 0", category: .general)
        // Move to front
        let removed = instances.remove(at: index)
        instances.insert(removed, at: 0)
        saveInstances()
        LoggingService.shared.debug("[InstancesManager] After move: \(instances.map { $0.displayName })", category: .general)
    }

    // MARK: - Computed Properties

    var enabledInstances: [Instance] {
        instances.filter(\.isEnabled)
    }

    var youtubeInstances: [Instance] {
        instances.filter(\.isYouTubeInstance)
    }

    var peertubeInstances: [Instance] {
        instances.filter(\.isPeerTubeInstance)
    }

    var yatteeServerInstances: [Instance] {
        instances.filter(\.isYatteeServerInstance)
    }

    var hasYouTubeInstances: Bool {
        instances.contains { $0.isYouTubeInstance }
    }

    var hasPeerTubeInstances: Bool {
        instances.contains { $0.isPeerTubeInstance }
    }

    var hasYatteeServerInstances: Bool {
        instances.contains { $0.isYatteeServerInstance }
    }

    var invidiousPipedInstances: [Instance] {
        instances.filter { $0.type == .invidious || $0.type == .piped }
    }

    var hasInvidiousPipedInstances: Bool {
        instances.contains { $0.type == .invidious || $0.type == .piped }
    }

    var enabledYatteeServerInstances: [Instance] {
        yatteeServerInstances.filter(\.isEnabled)
    }

    /// Selects an enabled instance appropriate for the given video's content source.
    /// - For PeerTube videos: prefers the exact instance, falls back to any PeerTube instance
    /// - For YouTube/extracted content: uses YouTube-capable instance (Invidious, Piped, Yattee Server)
    func instance(for video: Video) -> Instance? {
        instance(for: video.id.source)
    }

    /// Selects an enabled instance appropriate for the given content source.
    /// - For PeerTube content: prefers the exact instance, falls back to any PeerTube instance
    /// - For extracted content: requires Yattee Server (only backend with yt-dlp)
    /// - For YouTube content: uses YouTube-capable instance (Invidious, Piped, Yattee Server)
    func instance(for contentSource: ContentSource) -> Instance? {
        switch contentSource {
        case .federated(let provider, let instanceURL) where provider == ContentSource.peertubeProvider:
            // PeerTube content - prefer the exact instance, fall back to any PeerTube instance
            return enabledInstances.first { $0.url.host == instanceURL.host }
                ?? enabledInstances.first(where: \.isPeerTubeInstance)
        case .extracted:
            // Extracted content requires Yattee Server (yt-dlp)
            return yatteeServerInstances.first
        case .global, .federated:
            // YouTube content - prefer Yattee Server, fall back to other YouTube-capable instances
            return enabledYatteeServerInstances.first
                ?? enabledInstances.first(where: \.isYouTubeInstance)
        }
    }

    /// Disables all Yattee Server instances except the specified one.
    func disableOtherYatteeServerInstances(except instanceID: UUID) {
        for instance in enabledYatteeServerInstances where instance.id != instanceID {
            var updated = instance
            updated.isEnabled = false
            update(updated)
        }
    }

    // MARK: - Instance Status

    /// Returns the current status of an instance.
    func status(for instance: Instance) -> InstanceStatus {
        instanceStatuses[instance.id] ?? .online
    }

    /// Updates the status of an instance.
    func updateStatus(_ status: InstanceStatus, for instance: Instance) {
        instanceStatuses[instance.id] = status
    }

    /// Updates status based on an API error.
    func updateStatusFromError(_ error: Error, for instance: Instance) {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                updateStatus(.authFailed, for: instance)
            case .noConnection, .timeout:
                updateStatus(.offline, for: instance)
            default:
                // Don't change status for other errors
                break
            }
        } else {
            // Generic network errors
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                updateStatus(.offline, for: instance)
            }
        }
    }

    /// Clears the status of an instance (resets to online).
    func clearStatus(for instance: Instance) {
        instanceStatuses.removeValue(forKey: instance.id)
    }

    /// Instances that have auth issues (need attention).
    var instancesWithAuthIssues: [Instance] {
        instances.filter { instanceStatuses[$0.id] == .authFailed || instanceStatuses[$0.id] == .authRequired }
    }

    /// The currently active instance for browsing content.
    /// Falls back to the first enabled instance if no active instance is set.
    var activeInstance: Instance? {
        if let id = activeInstanceID,
           let instance = enabledInstances.first(where: { $0.id == id }) {
            return instance
        }
        return enabledInstances.first
    }

    /// Sets the given instance as the active instance for browsing.
    func setActive(_ instance: Instance) {
        guard enabledInstances.contains(where: { $0.id == instance.id }) else { return }
        activeInstanceID = instance.id
        saveActiveInstance()
        NotificationCenter.default.post(name: .activeInstanceDidChange, object: nil)
    }

    /// Clears the active instance, falling back to the first enabled instance.
    func clearActiveInstance() {
        activeInstanceID = nil
        localDefaults.removeObject(forKey: activeInstanceKey)
        NotificationCenter.default.post(name: .activeInstanceDidChange, object: nil)
    }

    // MARK: - Private Methods

    private func loadInstances() {
        // Only load from local defaults - never automatically pull from iCloud
        // User must explicitly enable iCloud sync to get iCloud data
        if let data = localDefaults.data(forKey: instancesKey),
           let decoded = try? JSONDecoder().decode([Instance].self, from: data) {
            instances = decoded
        }
    }

    private func saveInstances() {
        guard let data = try? JSONEncoder().encode(instances) else { return }

        // Always write to local storage
        localDefaults.set(data, forKey: instancesKey)

        // Only write to iCloud if instance sync is enabled
        if instanceSyncEnabled {
            ubiquitousStore.set(data, forKey: instancesKey)
            settingsManager?.updateLastSyncTime()
        }

        NotificationCenter.default.post(name: .instancesDidChange, object: nil)
    }

    private func loadActiveInstance() {
        if let idString = localDefaults.string(forKey: activeInstanceKey),
           let uuid = UUID(uuidString: idString) {
            activeInstanceID = uuid
        }
    }

    private func saveActiveInstance() {
        if let id = activeInstanceID {
            localDefaults.set(id.uuidString, forKey: activeInstanceKey)
        } else {
            localDefaults.removeObject(forKey: activeInstanceKey)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let instancesDidChange = Notification.Name("stream.yattee.instancesDidChange")
    static let activeInstanceDidChange = Notification.Name("stream.yattee.activeInstanceDidChange")
}
