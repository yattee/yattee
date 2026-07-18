//
//  TapGestureAction.swift
//  Yattee
//
//  Defines the available actions for tap gestures.
//

import Foundation

/// Action to perform when a tap gesture zone is activated.
enum TapGestureAction: Codable, Hashable, Sendable {
    /// Toggle play/pause state.
    case togglePlayPause

    /// Seek forward by the specified number of seconds.
    case seekForward(seconds: Int)

    /// Seek backward by the specified number of seconds.
    case seekBackward(seconds: Int)

    /// Toggle fullscreen mode.
    case toggleFullscreen

    /// Toggle Picture-in-Picture mode.
    case togglePiP

    /// Play next item in queue.
    case playNext

    /// Play previous item in queue.
    case playPrevious

    /// Cycle through playback speeds.
    case cyclePlaybackSpeed

    /// Toggle mute state.
    case toggleMute

    /// Display name for the action.
    var displayName: String {
        switch self {
        case .togglePlayPause:
            String(localized: "gestures.action.togglePlayPause", defaultValue: "Toggle Play/Pause")
        case .seekForward(let seconds):
            String(localized: "gestures.action.seekForward", defaultValue: "Seek Forward") + " \(seconds)s"
        case .seekBackward(let seconds):
            String(localized: "gestures.action.seekBackward", defaultValue: "Seek Backward") + " \(seconds)s"
        case .toggleFullscreen:
            String(localized: "gestures.action.toggleFullscreen", defaultValue: "Toggle Fullscreen")
        case .togglePiP:
            String(localized: "gestures.action.togglePiP", defaultValue: "Toggle PiP")
        case .playNext:
            String(localized: "gestures.action.playNext", defaultValue: "Play Next")
        case .playPrevious:
            String(localized: "gestures.action.playPrevious", defaultValue: "Play Previous")
        case .cyclePlaybackSpeed:
            String(localized: "gestures.action.cyclePlaybackSpeed", defaultValue: "Cycle Playback Speed")
        case .toggleMute:
            String(localized: "gestures.action.toggleMute", defaultValue: "Toggle Mute")
        }
    }

    /// SF Symbol name for the action icon.
    var systemImage: String {
        switch self {
        case .togglePlayPause:
            "playpause.fill"
        case .seekForward:
            "arrow.trianglehead.clockwise"
        case .seekBackward:
            "arrow.trianglehead.counterclockwise"
        case .toggleFullscreen:
            "arrow.up.left.and.arrow.down.right"
        case .togglePiP:
            "pip"
        case .playNext:
            "forward.fill"
        case .playPrevious:
            "backward.fill"
        case .cyclePlaybackSpeed:
            "gauge.with.dots.needle.67percent"
        case .toggleMute:
            "speaker.slash.fill"
        }
    }

    /// Base action type for grouping (ignoring associated values).
    var actionType: TapGestureActionType {
        switch self {
        case .togglePlayPause: .togglePlayPause
        case .seekForward: .seekForward
        case .seekBackward: .seekBackward
        case .toggleFullscreen: .toggleFullscreen
        case .togglePiP: .togglePiP
        case .playNext: .playNext
        case .playPrevious: .playPrevious
        case .cyclePlaybackSpeed: .cyclePlaybackSpeed
        case .toggleMute: .toggleMute
        }
    }

    /// Whether this action requires a seconds parameter.
    var requiresSecondsParameter: Bool {
        switch self {
        case .seekForward, .seekBackward:
            true
        default:
            false
        }
    }

    /// The seek seconds value if applicable.
    var seekSeconds: Int? {
        switch self {
        case .seekForward(let seconds), .seekBackward(let seconds):
            seconds
        default:
            nil
        }
    }
}

// MARK: - Action Type Enum

/// Base action types without associated values (for UI selection).
enum TapGestureActionType: String, CaseIterable, Identifiable, Sendable {
    case togglePlayPause
    case seekForward
    case seekBackward
    case toggleFullscreen
    case togglePiP
    case playNext
    case playPrevious
    case cyclePlaybackSpeed
    case toggleMute

    var id: String { rawValue }

    /// Display name for the action type.
    var displayName: String {
        switch self {
        case .togglePlayPause:
            String(localized: "gestures.actionType.togglePlayPause", defaultValue: "Toggle Play/Pause")
        case .seekForward:
            String(localized: "gestures.actionType.seekForward", defaultValue: "Seek Forward")
        case .seekBackward:
            String(localized: "gestures.actionType.seekBackward", defaultValue: "Seek Backward")
        case .toggleFullscreen:
            String(localized: "gestures.actionType.toggleFullscreen", defaultValue: "Toggle Fullscreen")
        case .togglePiP:
            String(localized: "gestures.actionType.togglePiP", defaultValue: "Toggle PiP")
        case .playNext:
            String(localized: "gestures.actionType.playNext", defaultValue: "Play Next")
        case .playPrevious:
            String(localized: "gestures.actionType.playPrevious", defaultValue: "Play Previous")
        case .cyclePlaybackSpeed:
            String(localized: "gestures.actionType.cyclePlaybackSpeed", defaultValue: "Cycle Playback Speed")
        case .toggleMute:
            String(localized: "gestures.actionType.toggleMute", defaultValue: "Toggle Mute")
        }
    }

    /// SF Symbol name for the action type.
    var systemImage: String {
        switch self {
        case .togglePlayPause: "playpause.fill"
        case .seekForward: "arrow.trianglehead.clockwise"
        case .seekBackward: "arrow.trianglehead.counterclockwise"
        case .toggleFullscreen: "arrow.up.left.and.arrow.down.right"
        case .togglePiP: "pip"
        case .playNext: "forward.fill"
        case .playPrevious: "backward.fill"
        case .cyclePlaybackSpeed: "gauge.with.dots.needle.67percent"
        case .toggleMute: "speaker.slash.fill"
        }
    }

    /// Whether this action type requires a seconds parameter.
    var requiresSecondsParameter: Bool {
        switch self {
        case .seekForward, .seekBackward:
            true
        default:
            false
        }
    }

    /// Creates a TapGestureAction from this type with default seconds if needed.
    func toAction(seconds: Int = 10) -> TapGestureAction {
        switch self {
        case .togglePlayPause: .togglePlayPause
        case .seekForward: .seekForward(seconds: seconds)
        case .seekBackward: .seekBackward(seconds: seconds)
        case .toggleFullscreen: .toggleFullscreen
        case .togglePiP: .togglePiP
        case .playNext: .playNext
        case .playPrevious: .playPrevious
        case .cyclePlaybackSpeed: .cyclePlaybackSpeed
        case .toggleMute: .toggleMute
        }
    }
}
