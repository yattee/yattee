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
    /// Whether the expanded player opens in a separate window (vs. an inline sheet).
    /// Default is `true`.
    var macPlayerSeparateWindow: Bool {
        get {
            if let cached = _macPlayerSeparateWindow { return cached }
            return bool(for: .macPlayerSeparateWindow, default: true)
        }
        set {
            _macPlayerSeparateWindow = newValue
            set(newValue, for: .macPlayerSeparateWindow)
        }
    }

    /// Whether the separate player window floats above other windows (always on top).
    /// Toggled live from the player's top-bar pin button and remembered across sessions.
    /// Default is `false`.
    var macPlayerFloating: Bool {
        get {
            if let cached = _macPlayerFloating { return cached }
            return bool(for: .macPlayerFloating, default: false)
        }
        set {
            _macPlayerFloating = newValue
            set(newValue, for: .macPlayerFloating)
        }
    }

    /// Normalized X offset of the macOS floating control bar from its default
    /// bottom-center position, stored as a fraction of the player container width.
    /// 0 = default docked position.
    var macControlsBarOffsetX: Double {
        get {
            if let cached = _macControlsBarOffsetX { return cached }
            return double(for: .macControlsBarOffsetX)
        }
        set {
            _macControlsBarOffsetX = newValue
            set(newValue, for: .macControlsBarOffsetX)
        }
    }

    /// Normalized Y offset of the macOS floating control bar from its default
    /// bottom-center position, stored as a fraction of the player container height.
    /// 0 = default docked position.
    var macControlsBarOffsetY: Double {
        get {
            if let cached = _macControlsBarOffsetY { return cached }
            return double(for: .macControlsBarOffsetY)
        }
        set {
            _macControlsBarOffsetY = newValue
            set(newValue, for: .macControlsBarOffsetY)
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
                return .never // Default
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
