//
//  SettingsManager+MPV.swift
//  Yattee
//
//  Custom MPV options storage (local-only, not synced to iCloud).
//

import Foundation

extension SettingsManager {
    // MARK: - Custom MPV Options

    /// Custom MPV options defined by the user.
    /// Stored as a dictionary of option name to value (both strings).
    /// These options are applied to MPV after the default options.
    /// NOT synced to iCloud - local-only storage.
    var customMPVOptions: [String: String] {
        get {
            guard let data = localDefaults.data(forKey: "customMPVOptions"),
                  let options = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return options
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                localDefaults.set(data, forKey: "customMPVOptions")
            }
        }
    }

    /// Static synchronous accessor for custom MPV options.
    /// Use this from non-MainActor contexts like MPVClient.
    /// Reads directly from UserDefaults.standard.
    nonisolated static func customMPVOptionsSync() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: "customMPVOptions"),
              let options = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return options
    }
}
