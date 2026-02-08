//
//  SettingsManager+Player.swift
//  Yattee
//
//  Player behavior settings and platform-specific player modes.
//

import Foundation
#if os(iOS)
import UIKit
#endif

extension SettingsManager {
    // MARK: - Player Settings

    var keepPlayerPinnedEnabled: Bool {
        get {
            if let cached = _keepPlayerPinnedEnabled { return cached }
            return bool(for: .keepPlayerPinned, default: false)
        }
        set {
            _keepPlayerPinnedEnabled = newValue
            set(newValue, for: .keepPlayerPinned)
        }
    }

    #if os(iOS)
    /// Whether in-app orientation lock is enabled.
    /// When enabled, ignores accelerometer rotation detection and stays in current orientation.
    /// When disabled, uses accelerometer to detect rotation even if system lock is enabled.
    /// Only active when player sheet is expanded (visible on screen).
    var inAppOrientationLock: Bool {
        get {
            if let cached = _inAppOrientationLock { return cached }
            return bool(for: .inAppOrientationLock, default: true)
        }
        set {
            _inAppOrientationLock = newValue
            set(newValue, for: .inAppOrientationLock)
        }
    }

    /// Whether to automatically rotate to landscape when playing widescreen videos.
    var rotateToMatchAspectRatio: Bool {
        get {
            if let cached = _rotateToMatchAspectRatio { return cached }
            return bool(for: .rotateToMatchAspectRatio, default: true)
        }
        set {
            _rotateToMatchAspectRatio = newValue
            set(newValue, for: .rotateToMatchAspectRatio)
        }
    }

    /// Whether to automatically rotate to portrait when dismissing the player sheet.
    /// Only available on iPhone.
    var preferPortraitBrowsing: Bool {
        get {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
            if let cached = _preferPortraitBrowsing { return cached }
            return bool(for: .preferPortraitBrowsing, default: false)
        }
        set {
            _preferPortraitBrowsing = newValue
            set(newValue, for: .preferPortraitBrowsing)
        }
    }
    #endif

    #if os(macOS)
    var macPlayerMode: MacPlayerMode {
        get {
            if let cached = _macPlayerMode { return cached }
            return MacPlayerMode(rawValue: string(for: .macPlayerMode) ?? "") ?? .window
        }
        set {
            _macPlayerMode = newValue
            set(newValue.rawValue, for: .macPlayerMode)
        }
    }

    /// Whether the player sheet automatically resizes to match video aspect ratio.
    /// When enabled, the sheet window will resize when video loads or changes.
    /// Default is true.
    var playerSheetAutoResize: Bool {
        get {
            if let cached = _playerSheetAutoResize { return cached }
            return bool(for: .playerSheetAutoResize, default: true)
        }
        set {
            _playerSheetAutoResize = newValue
            set(newValue, for: .playerSheetAutoResize)
        }
    }
    #endif

    #if os(iOS)
    /// Behavior for minimizing the mini player. Default is onScrollDown. (iOS 26+ only)
    @available(iOS 26, *)
    var miniPlayerMinimizeBehavior: MiniPlayerMinimizeBehavior {
        get {
            if let cached = _miniPlayerMinimizeBehavior as? MiniPlayerMinimizeBehavior { return cached }
            guard let rawValue = localDefaults.string(forKey: "miniPlayerMinimizeBehavior"),
                  let behavior = MiniPlayerMinimizeBehavior(rawValue: rawValue) else {
                return .onScrollDown // Default
            }
            return behavior
        }
        set {
            _miniPlayerMinimizeBehavior = newValue
            localDefaults.set(newValue.rawValue, forKey: "miniPlayerMinimizeBehavior")
        }
    }
    #endif
}
