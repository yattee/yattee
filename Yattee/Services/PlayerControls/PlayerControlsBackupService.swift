//
//  PlayerControlsBackupService.swift
//  Yattee
//
//  Manages backup and recovery of player controls layout presets.
//

import Foundation

/// Manages backup and recovery of player controls layout presets.
actor PlayerControlsBackupService {
    // MARK: - Storage

    /// URL for the backup file in Application Support.
    private var backupFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yatteeDir = appSupport.appendingPathComponent("Yattee", isDirectory: true)
        return yatteeDir.appendingPathComponent("PlayerControlsBackup.json")
    }

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Backup Operations

    /// Creates a backup of the given presets.
    /// - Parameter presets: The presets to back up.
    func createBackup(presets: [LayoutPreset]) async throws {
        // Ensure directory exists
        let directory = backupFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Encode and write
        let data = try encoder.encode(presets)
        try data.write(to: backupFileURL, options: .atomic)

        LoggingService.shared.info("Created player controls backup with \(presets.count) presets")
    }

    /// Restores presets from backup.
    /// - Returns: The restored presets, or nil if no valid backup exists.
    func restoreFromBackup() async throws -> [LayoutPreset]? {
        guard fileManager.fileExists(atPath: backupFileURL.path) else {
            LoggingService.shared.info("No player controls backup file found")
            return nil
        }

        let data = try Data(contentsOf: backupFileURL)
        let presets = try decoder.decode([LayoutPreset].self, from: data)

        LoggingService.shared.info("Restored \(presets.count) presets from backup")
        return presets
    }

    /// Checks if a valid backup exists.
    /// - Returns: True if a valid backup file exists.
    func hasValidBackup() async -> Bool {
        guard fileManager.fileExists(atPath: backupFileURL.path) else {
            return false
        }

        // Try to decode to verify it's valid
        do {
            let data = try Data(contentsOf: backupFileURL)
            _ = try decoder.decode([LayoutPreset].self, from: data)
            return true
        } catch {
            LoggingService.shared.error("Backup file exists but is invalid: \(error.localizedDescription)")
            return false
        }
    }

    /// Attempts to create a recovered preset from corrupted data.
    /// - Parameter data: The corrupted data.
    /// - Returns: A recovered preset if partial recovery is possible.
    func createRecoveredPreset(from data: Data) async -> LayoutPreset? {
        // Try to extract any valid layout from the data
        // This is a best-effort recovery attempt

        // First, try decoding as a single preset
        if let preset = try? decoder.decode(LayoutPreset.self, from: data) {
            let recovered = preset.duplicate(name: "Recovered \(formattedDate())")
            LoggingService.shared.info("Recovered single preset from corrupted data")
            return recovered
        }

        // Try decoding as an array and take the first valid one
        if let presets = try? decoder.decode([LayoutPreset].self, from: data),
           let first = presets.first {
            let recovered = first.duplicate(name: "Recovered \(formattedDate())")
            LoggingService.shared.info("Recovered preset from corrupted array data")
            return recovered
        }

        // Try decoding just the layout
        if let layout = try? decoder.decode(PlayerControlsLayout.self, from: data) {
            let recovered = LayoutPreset(
                name: "Recovered \(formattedDate())",
                layout: layout
            )
            LoggingService.shared.info("Recovered layout from corrupted data")
            return recovered
        }

        LoggingService.shared.error("Failed to recover any preset from corrupted data")
        return nil
    }

    /// Deletes the backup file.
    func deleteBackup() async throws {
        guard fileManager.fileExists(atPath: backupFileURL.path) else {
            return
        }

        try fileManager.removeItem(at: backupFileURL)
        LoggingService.shared.info("Deleted player controls backup")
    }

    // MARK: - Helpers

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}
