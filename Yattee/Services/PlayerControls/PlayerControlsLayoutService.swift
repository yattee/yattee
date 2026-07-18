//
//  PlayerControlsLayoutService.swift
//  Yattee
//
//  Manages player controls layout presets with local storage and CloudKit sync.
//

import Foundation

/// Manages player controls layout presets.
actor PlayerControlsLayoutService {
    // MARK: - Dependencies

    private let backupService: PlayerControlsBackupService
    private let fileManager = FileManager.default

    /// CloudKit sync engine for syncing presets across devices.
    /// Set this after initialization to enable CloudKit sync.
    nonisolated(unsafe) weak var cloudKitSync: CloudKitSyncEngine?

    // MARK: - Storage

    /// URL for the presets file in Application Support.
    private var presetsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yatteeDir = appSupport.appendingPathComponent("Yattee", isDirectory: true)
        return yatteeDir.appendingPathComponent("PlayerControlsPresets.json")
    }

    /// UserDefaults key for active preset ID (per-device, not synced).
    private let activePresetIDKey = "playerControlsActivePresetID"

    /// UserDefaults key for last seen button version (for NEW badges).
    private let lastSeenButtonVersionKey = "playerControlsLastSeenButtonVersion"

    /// UserDefaults key for the last-applied built-in presets version.
    private let builtInPresetsVersionKey = "playerControlsBuiltInPresetsVersion"

    /// In-memory cache of presets.
    private var presets: [LayoutPreset] = []

    /// Whether presets have been loaded.
    private var isLoaded = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    init(backupService: PlayerControlsBackupService = PlayerControlsBackupService()) {
        self.backupService = backupService
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Sets the CloudKit sync engine for syncing presets across devices.
    /// - Parameter syncEngine: The CloudKit sync engine to use.
    func setCloudKitSync(_ syncEngine: CloudKitSyncEngine) {
        self.cloudKitSync = syncEngine
    }

    // MARK: - Loading

    /// Loads presets from disk.
    /// - Returns: The loaded presets.
    func loadPresets() async throws -> [LayoutPreset] {
        if isLoaded {
            return presets
        }

        // Ensure directory exists
        let directory = presetsFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Try to load from file
        if fileManager.fileExists(atPath: presetsFileURL.path) {
            do {
                let data = try Data(contentsOf: presetsFileURL)
                presets = try decoder.decode([LayoutPreset].self, from: data)
                LoggingService.shared.info("Loaded \(presets.count) player controls presets")
            } catch {
                LoggingService.shared.error("Failed to load presets, attempting recovery: \(error.localizedDescription)")

                // Try to restore from backup
                if let backupPresets = try? await backupService.restoreFromBackup() {
                    presets = backupPresets
                    try await savePresetsToDisk()
                    LoggingService.shared.info("Restored presets from backup")
                } else {
                    // Try to create recovered preset from corrupted data
                    let corruptedData = try? Data(contentsOf: presetsFileURL)
                    if let data = corruptedData,
                       let recovered = await backupService.createRecoveredPreset(from: data) {
                        presets = LayoutPreset.allBuiltIn() + [recovered]
                        try await savePresetsToDisk()
                        LoggingService.shared.info("Created recovered preset from corrupted data")
                    } else {
                        // Fall back to built-in presets
                        presets = LayoutPreset.allBuiltIn()
                        try await savePresetsToDisk()
                        LoggingService.shared.info("Reset to built-in presets after recovery failure")
                    }
                }
            }
        } else {
            // First launch - create built-in presets
            presets = LayoutPreset.allBuiltIn()
            try await savePresetsToDisk()
            LoggingService.shared.info("Created initial built-in presets")
        }

        // Update or add built-in presets as needed
        await updateBuiltInPresetsIfNeeded()

        isLoaded = true
        return presets
    }

    /// Updates built-in presets when the code version is newer than what was last applied,
    /// and ensures all built-in presets exist (in case of data corruption).
    private func updateBuiltInPresetsIfNeeded() async {
        let codeVersion = LayoutPreset.builtInPresetsVersion
        let storedVersion = UserDefaults.standard.integer(forKey: builtInPresetsVersionKey)
        let needsUpdate = storedVersion < codeVersion

        let builtIn = LayoutPreset.allBuiltIn()
        var modified = false
        let currentActiveID = activePresetID()
        var activePresetWasUpdated = false

        for preset in builtIn {
            if let index = presets.firstIndex(where: { $0.id == preset.id }) {
                // Replace existing built-in preset if version is newer
                if needsUpdate {
                    presets[index] = preset
                    modified = true
                    if preset.id == currentActiveID {
                        activePresetWasUpdated = true
                    }
                }
            } else {
                // Built-in preset is missing — add it
                presets.append(preset)
                modified = true
            }
        }

        if modified {
            try? await savePresetsToDisk()
        }

        if needsUpdate {
            UserDefaults.standard.set(codeVersion, forKey: builtInPresetsVersionKey)
            LoggingService.shared.info("Updated built-in presets to version \(codeVersion)")

            // If the active preset was a built-in that just got updated,
            // notify the UI so it picks up the new layout
            if activePresetWasUpdated {
                await MainActor.run {
                    NotificationCenter.default.post(name: .playerControlsActivePresetDidChange, object: nil)
                }
            }
        }
    }

    // MARK: - Saving

    /// Saves presets to disk and creates backup.
    private func savePresetsToDisk() async throws {
        let data = try encoder.encode(presets)
        try data.write(to: presetsFileURL, options: .atomic)

        // Create backup
        try await backupService.createBackup(presets: presets)
    }

    // MARK: - Preset Management

    /// Returns all presets for the current device class.
    func allPresets() async -> [LayoutPreset] {
        if !isLoaded {
            _ = try? await loadPresets()
        }
        return presets.filter { $0.deviceClass == .current }
    }

    /// Returns a preset by ID.
    func preset(forID id: UUID) async -> LayoutPreset? {
        if !isLoaded {
            _ = try? await loadPresets()
        }
        return presets.first { $0.id == id }
    }

    /// Saves a new or updated preset.
    func savePreset(_ preset: LayoutPreset) async throws {
        if !isLoaded {
            _ = try? await loadPresets()
        }

        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            // Update existing - but not if it's built-in
            if presets[index].isBuiltIn {
                LoggingService.shared.error("Cannot modify built-in preset")
                return
            }
            presets[index] = preset
        } else {
            // Add new
            presets.append(preset)
        }

        try await savePresetsToDisk()
        LoggingService.shared.info("Saved preset: \(preset.name)")

        // Sync to CloudKit and post notification (only for non-built-in presets)
        let syncEngine = cloudKitSync
        let shouldSync = !preset.isBuiltIn
        await MainActor.run {
            if shouldSync {
                syncEngine?.queueControlsPresetSave(preset)
            }
            NotificationCenter.default.post(name: .playerControlsPresetsDidChange, object: nil)
        }
    }

    /// Updates an existing preset's layout.
    func updatePresetLayout(_ presetID: UUID, layout: PlayerControlsLayout) async throws {
        if !isLoaded {
            _ = try? await loadPresets()
        }

        guard let index = presets.firstIndex(where: { $0.id == presetID }) else {
            LoggingService.shared.error("Preset not found: \(presetID)")
            return
        }

        // Cannot modify built-in presets
        if presets[index].isBuiltIn {
            LoggingService.shared.error("Cannot modify built-in preset")
            return
        }

        let updatedPreset = presets[index].withUpdatedLayout(layout)
        presets[index] = updatedPreset
        try await savePresetsToDisk()

        // Sync to CloudKit and post notification
        let syncEngine = cloudKitSync
        await MainActor.run {
            syncEngine?.queueControlsPresetSave(updatedPreset)
            NotificationCenter.default.post(name: .playerControlsPresetsDidChange, object: nil)
        }
    }

    /// Deletes a preset.
    func deletePreset(id: UUID) async throws {
        if !isLoaded {
            _ = try? await loadPresets()
        }

        guard let preset = presets.first(where: { $0.id == id }) else {
            return
        }

        // Cannot delete built-in presets
        if preset.isBuiltIn {
            LoggingService.shared.error("Cannot delete built-in preset")
            return
        }

        // Cannot delete active preset
        if activePresetID() == id {
            LoggingService.shared.error("Cannot delete active preset")
            return
        }

        presets.removeAll { $0.id == id }
        try await savePresetsToDisk()
        LoggingService.shared.info("Deleted preset: \(preset.name)")

        // Sync deletion to CloudKit and post notification
        let syncEngine = cloudKitSync
        await MainActor.run {
            syncEngine?.queueControlsPresetDelete(id: id)
            NotificationCenter.default.post(name: .playerControlsPresetsDidChange, object: nil)
        }
    }

    /// Duplicates a preset with a new name.
    func duplicatePreset(_ preset: LayoutPreset, newName: String) async throws -> LayoutPreset {
        let duplicate = preset.duplicate(name: newName)
        try await savePreset(duplicate)
        return duplicate
    }

    /// Renames a preset.
    func renamePreset(_ presetID: UUID, to newName: String) async throws {
        if !isLoaded {
            _ = try? await loadPresets()
        }

        guard let index = presets.firstIndex(where: { $0.id == presetID }) else {
            return
        }

        // Cannot rename built-in presets
        if presets[index].isBuiltIn {
            LoggingService.shared.error("Cannot rename built-in preset")
            return
        }

        let renamedPreset = presets[index].renamed(to: newName)
        presets[index] = renamedPreset
        try await savePresetsToDisk()

        // Sync to CloudKit and post notification
        let syncEngine = cloudKitSync
        await MainActor.run {
            syncEngine?.queueControlsPresetSave(renamedPreset)
            NotificationCenter.default.post(name: .playerControlsPresetsDidChange, object: nil)
        }
    }

    // MARK: - Active Preset

    /// Returns the ID of the active preset for this device.
    func activePresetID() -> UUID? {
        guard let string = UserDefaults.standard.string(forKey: activePresetIDKey),
              let uuid = UUID(uuidString: string) else {
            return nil
        }
        return uuid
    }

    /// Sets the active preset ID for this device.
    func setActivePresetID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activePresetIDKey)
        LoggingService.shared.info("Set active preset: \(id)")

        // Post notification
        Task { @MainActor in
            NotificationCenter.default.post(name: .playerControlsActivePresetDidChange, object: nil)
        }
    }

    /// Returns the active preset, or the default preset if none is set.
    func activePreset() async -> LayoutPreset {
        if !isLoaded {
            _ = try? await loadPresets()
        }

        // Try to find the active preset
        if let activeID = activePresetID(),
           let preset = presets.first(where: { $0.id == activeID && $0.deviceClass == .current }) {
            return preset
        }

        // Fall back to default preset
        let defaultPreset = LayoutPreset.defaultPreset()
        if !presets.contains(where: { $0.id == defaultPreset.id }) {
            presets.append(defaultPreset)
            try? await savePresetsToDisk()
        }

        // Set default as active
        setActivePresetID(defaultPreset.id)
        return defaultPreset
    }

    /// Returns the active layout and updates cached settings.
    func activeLayout() async -> PlayerControlsLayout {
        let preset = await activePreset()
        let layout = preset.layout
        GlobalLayoutSettings.cached = layout.globalSettings
        MiniPlayerSettings.cached = layout.effectiveMiniPlayerSettings
        return layout
    }

    // MARK: - Validation

    /// Checks if a preset can be deleted.
    func canDeletePreset(id: UUID) async -> Bool {
        if !isLoaded {
            _ = try? await loadPresets()
        }

        guard let preset = presets.first(where: { $0.id == id }) else {
            return false
        }

        // Cannot delete built-in presets
        if preset.isBuiltIn {
            return false
        }

        // Cannot delete active preset
        if activePresetID() == id {
            return false
        }

        return true
    }

    // MARK: - NEW Badge Support

    /// Returns the last seen button version.
    func lastSeenButtonVersion() -> Int {
        UserDefaults.standard.integer(forKey: lastSeenButtonVersionKey)
    }

    /// Updates the last seen button version.
    func updateLastSeenButtonVersion(_ version: Int) {
        UserDefaults.standard.set(version, forKey: lastSeenButtonVersionKey)
    }

    /// Returns button types that are new since the last seen version.
    func newButtonTypes() -> [ControlButtonType] {
        let lastSeen = lastSeenButtonVersion()
        return ControlButtonType.allCases.filter { $0.versionAdded > lastSeen }
    }

    /// Marks all current buttons as seen.
    func markAllButtonsAsSeen() {
        let maxVersion = ControlButtonType.allCases.map(\.versionAdded).max() ?? 1
        updateLastSeenButtonVersion(maxVersion)
    }

    // MARK: - CloudKit Support

    /// Returns all presets for CloudKit sync (filtered by device class).
    func presetsForSync() async -> [LayoutPreset] {
        if !isLoaded {
            _ = try? await loadPresets()
        }
        // Only sync non-built-in presets for current device class
        return presets.filter { !$0.isBuiltIn && $0.deviceClass == .current }
    }

    /// Imports a preset from CloudKit.
    func importPreset(_ preset: LayoutPreset) async throws {
        if !isLoaded {
            _ = try? await loadPresets()
        }

        // Only import if device class matches
        guard preset.deviceClass == .current else {
            LoggingService.shared.info("Skipping preset import - wrong device class: \(preset.deviceClass)")
            return
        }

        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            // Update existing if newer
            if preset.updatedAt > presets[index].updatedAt {
                presets[index] = preset
            }
        } else {
            // Add new
            presets.append(preset)
        }

        try await savePresetsToDisk()

        // Post notification
        await MainActor.run {
            NotificationCenter.default.post(name: .playerControlsPresetsDidChange, object: nil)
        }
    }

    /// Removes a preset by ID (from CloudKit deletion).
    func removePreset(id: UUID) async throws {
        if !isLoaded {
            _ = try? await loadPresets()
        }

        guard let preset = presets.first(where: { $0.id == id }) else {
            return
        }

        // Cannot remove built-in presets
        if preset.isBuiltIn {
            return
        }

        // If this was the active preset, revert to default
        if activePresetID() == id {
            let defaultPreset = LayoutPreset.defaultPreset()
            setActivePresetID(defaultPreset.id)
            LoggingService.shared.info("Reverted to default preset after remote deletion of active preset")
        }

        presets.removeAll { $0.id == id }
        try await savePresetsToDisk()

        // Post notification
        await MainActor.run {
            NotificationCenter.default.post(name: .playerControlsPresetsDidChange, object: nil)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when player controls presets change.
    static let playerControlsPresetsDidChange = Notification.Name("playerControlsPresetsDidChange")

    /// Posted when the active player controls preset changes.
    static let playerControlsActivePresetDidChange = Notification.Name("playerControlsActivePresetDidChange")
}
