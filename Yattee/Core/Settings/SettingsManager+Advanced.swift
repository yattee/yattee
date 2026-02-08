//
//  SettingsManager+Advanced.swift
//  Yattee
//
//  Advanced settings: debug, MPV, floating panel.
//

import Foundation
import SwiftUI

extension SettingsManager {
    // MARK: - Advanced Settings

    /// Whether to show advanced stream details (codec, bitrate, size) in quality selector.
    /// When disabled, only shows resolution/language and filters to best stream per resolution/language.
    /// Default is false (simplified view).
    var showAdvancedStreamDetails: Bool {
        get {
            if let cached = _showAdvancedStreamDetails { return cached }
            return bool(for: .showAdvancedStreamDetails, default: false)
        }
        set {
            _showAdvancedStreamDetails = newValue
            set(newValue, for: .showAdvancedStreamDetails)
        }
    }

    /// Whether to show player area debug overlays (frame borders, safe area values, layout info).
    /// Useful for troubleshooting layout issues on different devices.
    /// Default is false (hidden).
    var showPlayerAreaDebug: Bool {
        get {
            if let cached = _showPlayerAreaDebug { return cached }
            return bool(for: .showPlayerAreaDebug, default: false)
        }
        set {
            _showPlayerAreaDebug = newValue
            set(newValue, for: .showPlayerAreaDebug)
        }
    }

    /// Whether verbose MPV rendering logging is enabled.
    /// When enabled, logs detailed OpenGL context, framebuffer, and display link state
    /// to help diagnose rendering issues. Default is false (disabled).
    var verboseMPVLogging: Bool {
        get {
            if let cached = _verboseMPVLogging { return cached }
            return bool(for: .verboseMPVLogging, default: false)
        }
        set {
            _verboseMPVLogging = newValue
            set(newValue, for: .verboseMPVLogging)
        }
    }

    /// Whether verbose remote control logging is enabled.
    /// When enabled, logs detailed discovery, connection, and message state
    /// to help diagnose remote control issues. Default is false (disabled).
    var verboseRemoteControlLogging: Bool {
        get {
            if let cached = _verboseRemoteControlLogging { return cached }
            return bool(for: .verboseRemoteControlLogging, default: false)
        }
        set {
            _verboseRemoteControlLogging = newValue
            set(newValue, for: .verboseRemoteControlLogging)
        }
    }

    /// Custom device name for remote control. When empty, uses system device name.
    /// Allows users to set a custom name that appears to other devices on the network.
    var remoteControlCustomDeviceName: String {
        get {
            if let cached = _remoteControlCustomDeviceName { return cached }
            return string(for: .remoteControlCustomDeviceName) ?? ""
        }
        set {
            _remoteControlCustomDeviceName = newValue
            set(newValue, for: .remoteControlCustomDeviceName)
        }
    }

    /// Whether to hide this device from remote control when app enters background.
    /// When enabled, stops Bonjour advertising when backgrounded so device disappears
    /// from other devices' lists. Default is true (hide when backgrounded).
    /// Only applies to iOS and tvOS.
    var remoteControlHideWhenBackgrounded: Bool {
        get {
            if let cached = _remoteControlHideWhenBackgrounded { return cached }
            return bool(for: .remoteControlHideWhenBackgrounded, default: true)
        }
        set {
            _remoteControlHideWhenBackgrounded = newValue
            set(newValue, for: .remoteControlHideWhenBackgrounded)
        }
    }

    /// Minimum buffer time in seconds before video playback starts.
    /// Higher values reduce initial stuttering but increase startup delay.
    /// Default is 3.0 seconds.
    static let defaultMpvBufferSeconds: Double = 3.0

    var mpvBufferSeconds: Double {
        get {
            if let cached = _mpvBufferSeconds { return cached }
            let value = double(for: .mpvBufferSeconds)
            return value > 0 ? value : Self.defaultMpvBufferSeconds
        }
        set {
            _mpvBufferSeconds = newValue
            set(newValue, for: .mpvBufferSeconds)
        }
    }

    /// Whether to use EDL combined streams for separate video/audio.
    /// When enabled, video and audio streams are combined into a single EDL URL
    /// for unified caching and better A/V synchronization.
    /// When disabled, falls back to loading video first then adding audio via audio-add.
    /// Default is false (disabled) due to EDL demuxer issues with backward seeking.
    var mpvUseEDLStreams: Bool {
        get {
            if let cached = _mpvUseEDLStreams { return cached }
            return bool(for: .mpvUseEDLStreams, default: false)
        }
        set {
            _mpvUseEDLStreams = newValue
            set(newValue, for: .mpvUseEDLStreams)
        }
    }

    /// Whether zoom navigation transitions are enabled (iOS only).
    /// When enabled, navigating to video/channel/playlist details shows a zoom animation
    /// from the source thumbnail. Disable if experiencing visual glitches with swipe-back gestures.
    /// Default is true (enabled).
    var zoomTransitionsEnabled: Bool {
        get {
            if let cached = _zoomTransitionsEnabled { return cached }
            return bool(for: .zoomTransitionsEnabled, default: true)
        }
        set {
            _zoomTransitionsEnabled = newValue
            set(newValue, for: .zoomTransitionsEnabled)
        }
    }

    // MARK: - Details Panel Settings

    /// Which side the floating details panel appears on in landscape layout.
    /// Default is right side.
    var floatingDetailsPanelSide: FloatingPanelSide {
        get {
            if let cached = _floatingDetailsPanelSide { return cached }
            return FloatingPanelSide(rawValue: string(for: .floatingDetailsPanelSide) ?? "") ?? .left
        }
        set {
            _floatingDetailsPanelSide = newValue
            set(newValue.rawValue, for: .floatingDetailsPanelSide)
        }
    }

    /// Default panel width in wide layout.
    static let defaultFloatingDetailsPanelWidth: CGFloat = 400

    /// Width of the floating details panel in wide layout.
    /// User can resize via drag gesture. Persisted across sessions.
    var floatingDetailsPanelWidth: CGFloat {
        get {
            if let cached = _floatingDetailsPanelWidth { return cached }
            let value = double(for: .floatingDetailsPanelWidth)
            return value > 0 ? CGFloat(value) : Self.defaultFloatingDetailsPanelWidth
        }
        set {
            _floatingDetailsPanelWidth = newValue
            set(Double(newValue), for: .floatingDetailsPanelWidth)
        }
    }

    /// Whether the details panel is visible in landscape layout.
    /// Default is false (hidden). User must manually show panel.
    var landscapeDetailsPanelVisible: Bool {
        get {
            if let cached = _landscapeDetailsPanelVisible { return cached }
            return bool(for: .landscapeDetailsPanelVisible, default: false)
        }
        set {
            _landscapeDetailsPanelVisible = newValue
            set(newValue, for: .landscapeDetailsPanelVisible)
        }
    }

    /// Whether the details panel is pinned in landscape layout.
    /// Default is false (floating mode).
    var landscapeDetailsPanelPinned: Bool {
        get {
            if let cached = _landscapeDetailsPanelPinned { return cached }
            return bool(for: .landscapeDetailsPanelPinned, default: false)
        }
        set {
            _landscapeDetailsPanelPinned = newValue
            set(newValue, for: .landscapeDetailsPanelPinned)
        }
    }

    // MARK: - Appearance Settings

    /// List style for video list views.
    /// Controls whether lists use inset grouped style (card background) or plain style.
    /// Default is plain. Synced per-platform via iCloud.
    var listStyle: VideoListStyle {
        get {
            if let cached = _listStyle { return cached }
            guard let rawValue = string(for: .listStyle),
                  let style = VideoListStyle(rawValue: rawValue) else {
                return .plain
            }
            _listStyle = style
            return style
        }
        set {
            _listStyle = newValue
            set(newValue.rawValue, for: .listStyle)
        }
    }

    // MARK: - Video Swipe Actions

    #if !os(tvOS)
    /// Order of video swipe actions. Actions appear in this order from left to right.
    /// New actions are merged in at their default positions if not already present.
    var videoSwipeActionOrder: [VideoSwipeAction] {
        get {
            if let cached = _videoSwipeActionOrder { return cached }

            // Try to decode from storage
            if let data = data(for: .videoSwipeActionOrder),
               let decoded = try? JSONDecoder().decode([VideoSwipeAction].self, from: data) {
                // Merge any new actions that might have been added in an update
                var order = decoded
                for action in VideoSwipeAction.allCases {
                    if !order.contains(action) {
                        order.append(action)
                    }
                }
                _videoSwipeActionOrder = order
                return order
            }

            // Return default order with all actions
            let order = VideoSwipeAction.allCases
            _videoSwipeActionOrder = order
            return order
        }
        set {
            _videoSwipeActionOrder = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .videoSwipeActionOrder)
            }
        }
    }

    /// Visibility of each video swipe action. True = enabled, False = disabled.
    var videoSwipeActionVisibility: [VideoSwipeAction: Bool] {
        get {
            if let cached = _videoSwipeActionVisibility { return cached }

            // Try to decode from storage
            if let data = data(for: .videoSwipeActionVisibility),
               let decoded = try? JSONDecoder().decode([VideoSwipeAction: Bool].self, from: data) {
                // Merge in defaults for any new actions
                var visibility = decoded
                for action in VideoSwipeAction.allCases {
                    if visibility[action] == nil {
                        visibility[action] = VideoSwipeAction.defaultVisibility[action] ?? false
                    }
                }
                _videoSwipeActionVisibility = visibility
                return visibility
            }

            // Return default visibility
            let visibility = VideoSwipeAction.defaultVisibility
            _videoSwipeActionVisibility = visibility
            return visibility
        }
        set {
            _videoSwipeActionVisibility = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .videoSwipeActionVisibility)
            }
        }
    }

    /// Returns visible swipe actions in the configured order.
    func visibleVideoSwipeActions() -> [VideoSwipeAction] {
        videoSwipeActionOrder.filter { videoSwipeActionVisibility[$0] ?? false }
    }
    #endif
}
