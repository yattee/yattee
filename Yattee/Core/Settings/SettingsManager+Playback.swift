//
//  SettingsManager+Playback.swift
//  Yattee
//
//  Playback-related settings: quality, audio, subtitles, volume.
//

import Foundation

extension SettingsManager {
    // MARK: - Playback Settings

    /// The player backend type. Always returns MPV as it's the only supported backend.
    var preferredBackend: PlayerBackendType {
        .mpv
    }

    var preferredQuality: VideoQuality {
        get {
            if let cached = _preferredQuality { return cached }
            return VideoQuality(rawValue: string(for: .preferredQuality) ?? "") ?? .hd1080p
        }
        set {
            _preferredQuality = newValue
            set(newValue.rawValue, for: .preferredQuality)
        }
    }

    var cellularQuality: VideoQuality {
        get {
            if let cached = _cellularQuality { return cached }
            return VideoQuality(rawValue: string(for: .cellularQuality) ?? "") ?? .hd720p
        }
        set {
            _cellularQuality = newValue
            set(newValue.rawValue, for: .cellularQuality)
        }
    }

    var backgroundPlaybackEnabled: Bool {
        get {
            if let cached = _backgroundPlaybackEnabled { return cached }
            return bool(for: .backgroundPlayback, default: true)
        }
        set {
            _backgroundPlaybackEnabled = newValue
            set(newValue, for: .backgroundPlayback)
        }
    }

    /// tvOS only: when enabled, the Siri remote Menu button closes the video
    /// (clears queue, stops playback) instead of only collapsing the player.
    /// When enabled, the explicit top-bar close button is hidden.
    var tvOSMenuButtonClosesVideo: Bool {
        get {
            if let cached = _tvOSMenuButtonClosesVideo { return cached }
            return bool(for: .tvOSMenuButtonClosesVideo, default: false)
        }
        set {
            _tvOSMenuButtonClosesVideo = newValue
            set(newValue, for: .tvOSMenuButtonClosesVideo)
        }
    }

    /// Whether DASH streams are enabled (MPV only).
    /// Disabled by default as DASH can be unreliable with some Invidious instances.
    var dashEnabled: Bool {
        get {
            if let cached = _dashEnabled { return cached }
            return bool(for: .dashEnabled, default: false)
        }
        set {
            _dashEnabled = newValue
            set(newValue, for: .dashEnabled)
        }
    }

    /// Preferred audio language code (e.g., "en", "de", "ja").
    /// When set, audio streams in this language will be auto-selected and shown first.
    /// nil means no preference (use original/default audio).
    var preferredAudioLanguage: String? {
        get {
            if let cached = _preferredAudioLanguage { return cached }
            return string(for: .preferredAudioLanguage)
        }
        set {
            _preferredAudioLanguage = newValue
            if let value = newValue {
                set(value, for: .preferredAudioLanguage)
            } else {
                // Clear the setting
                let pKey = "preferredAudioLanguage"
                localDefaults.removeObject(forKey: pKey)
                if iCloudSyncEnabled && syncSettings {
                    ubiquitousStore.removeObject(forKey: pKey)
                }
            }
        }
    }

    /// Preferred subtitles language code (e.g., "en", "de", "ja").
    /// When set, subtitles in this language will be auto-loaded when video starts (MPV only).
    /// nil means no subtitles (disabled by default).
    var preferredSubtitlesLanguage: String? {
        get {
            if let cached = _preferredSubtitlesLanguage { return cached }
            return string(for: .preferredSubtitlesLanguage)
        }
        set {
            _preferredSubtitlesLanguage = newValue
            if let value = newValue {
                set(value, for: .preferredSubtitlesLanguage)
            } else {
                // Clear the setting
                let pKey = "preferredSubtitlesLanguage"
                localDefaults.removeObject(forKey: pKey)
                if iCloudSyncEnabled && syncSettings {
                    ubiquitousStore.removeObject(forKey: pKey)
                }
            }
        }
    }

    // MARK: - Resume Behavior

    /// Action to perform when starting a partially watched video.
    /// Default is `.continueWatching` to maintain existing behavior.
    var resumeAction: ResumeAction {
        get {
            if let cached = _resumeAction { return cached }
            return ResumeAction(rawValue: string(for: .resumeAction) ?? "") ?? .ask
        }
        set {
            _resumeAction = newValue
            set(newValue.rawValue, for: .resumeAction)
        }
    }

    // MARK: - Volume Settings

    /// The persisted player volume level (0.0 - 1.0).
    /// Only used when volumeMode is .mpv.
    /// This is a local-only setting (not synced to iCloud).
    var playerVolume: Float {
        get {
            if let cached = _playerVolume { return cached }
            // Check if value exists; if not, return default of 1.0
            if localDefaults.object(forKey: "playerVolume") == nil {
                return 1.0
            }
            return localDefaults.float(forKey: "playerVolume")
        }
        set {
            _playerVolume = newValue
            localDefaults.set(newValue, forKey: "playerVolume")
        }
    }
}
