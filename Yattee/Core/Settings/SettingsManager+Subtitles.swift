//
//  SettingsManager+Subtitles.swift
//  Yattee
//
//  Subtitle appearance settings storage (local-only, not synced to iCloud).
//

import Foundation

extension SettingsManager {
    // MARK: - Subtitle Settings

    /// Subtitle appearance settings for MPV.
    /// Stored as JSON in local UserDefaults.
    /// NOT synced to iCloud - local-only storage since these are MPV-specific.
    var subtitleSettings: SubtitleSettings {
        get {
            guard let data = localDefaults.data(forKey: "subtitleSettings"),
                  let settings = try? JSONDecoder().decode(SubtitleSettings.self, from: data) else {
                return .default
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                localDefaults.set(data, forKey: "subtitleSettings")
            }
        }
    }

    /// Static synchronous accessor for subtitle settings.
    /// Use this from non-MainActor contexts like MPVClient.
    /// Reads directly from UserDefaults.standard.
    nonisolated static func subtitleSettingsSync() -> SubtitleSettings {
        guard let data = UserDefaults.standard.data(forKey: "subtitleSettings"),
              let settings = try? JSONDecoder().decode(SubtitleSettings.self, from: data) else {
            return .default
        }
        return settings
    }
}
