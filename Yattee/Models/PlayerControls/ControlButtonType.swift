//
//  ControlButtonType.swift
//  Yattee
//
//  Defines all available control button types for player customization.
//

import Foundation

/// All available control button types for player layout customization.
enum ControlButtonType: String, Codable, Hashable, Sendable, CaseIterable {
    case close
    case airplay
    case mpvDebug
    case brightness
    case volume
    case pictureInPicture
    case fullscreen
    case playbackSpeed
    case videoTrack
    case audioTrack
    case captions
    case chapters
    case share
    case addToPlaylist
    case contextMenu
    case spacer
    case timeDisplay
    case seekBackward
    case seekForward
    case playPause
    case orientationLock
    case panelToggle
    case playPrevious
    case playNext
    case queue
    case settings
    case controlsLock
    case titleAuthor
    case panscan
    case autoPlayNext
    case seek

    // MARK: - Version Tracking

    /// The app version when this button was added.
    /// Used for showing "NEW" badges on recently added buttons.
    var versionAdded: Int {
        // No need to add versions yet
        return 1
    }

    // MARK: - Display Properties

    /// Localized display name for the button.
    var displayName: String {
        switch self {
        case .close:
            return String(localized: "controls.button.close")
        case .airplay:
            return String(localized: "controls.button.airplay")
        case .mpvDebug:
            return String(localized: "controls.button.debug")
        case .brightness:
            return String(localized: "controls.button.brightness")
        case .volume:
            return String(localized: "controls.button.volume")
        case .pictureInPicture:
            return String(localized: "controls.button.pip")
        case .fullscreen:
            return String(localized: "controls.button.fullscreen")
        case .playbackSpeed:
            return String(localized: "controls.button.speed")
        case .videoTrack:
            return String(localized: "controls.button.videoTrack")
        case .audioTrack:
            return String(localized: "controls.button.audioTrack")
        case .captions:
            return String(localized: "controls.button.captions")
        case .chapters:
            return String(localized: "controls.button.chapters")
        case .share:
            return String(localized: "controls.button.share")
        case .addToPlaylist:
            return String(localized: "controls.button.addToPlaylist")
        case .contextMenu:
            return String(localized: "controls.button.more")
        case .spacer:
            return String(localized: "controls.button.spacer")
        case .timeDisplay:
            return String(localized: "controls.button.time")
        case .seekBackward:
            return String(localized: "controls.button.seekBackward")
        case .seekForward:
            return String(localized: "controls.button.seekForward")
        case .playPause:
            return String(localized: "controls.button.playPause")
        case .orientationLock:
            return String(localized: "controls.button.orientationLock")
        case .panelToggle:
            return String(localized: "controls.button.panelToggle")
        case .playPrevious:
            return String(localized: "controls.button.playPrevious")
        case .playNext:
            return String(localized: "controls.button.playNext")
        case .queue:
            return String(localized: "controls.button.queue")
        case .settings:
            return String(localized: "controls.button.settings")
        case .controlsLock:
            return String(localized: "controls.button.controlsLock")
        case .titleAuthor:
            return String(localized: "controls.button.titleAuthor")
        case .panscan:
            return String(localized: "controls.button.panscan")
        case .autoPlayNext:
            return String(localized: "controls.button.autoPlayNext")
        case .seek:
            return String(localized: "controls.button.seek")
        }
    }

    /// SF Symbol name for the button icon.
    var systemImage: String {
        switch self {
        case .close:
            return "xmark"
        case .airplay:
            return "airplayaudio"
        case .mpvDebug:
            return "info.circle"
        case .brightness:
            return "sun.max.fill"
        case .volume:
            return "speaker.wave.2.fill"
        case .pictureInPicture:
            return "pip.enter"
        case .fullscreen:
            return "arrow.up.left.and.arrow.down.right"
        case .playbackSpeed:
            return "gauge.with.needle"
        case .videoTrack:
            return "film"
        case .audioTrack:
            return "waveform"
        case .captions:
            return "captions.bubble"
        case .chapters:
            return "list.bullet.rectangle"
        case .share:
            return "square.and.arrow.up"
        case .addToPlaylist:
            return "text.badge.plus"
        case .contextMenu:
            return "ellipsis"
        case .spacer:
            return "arrow.left.and.right"
        case .timeDisplay:
            return "clock"
        case .seekBackward:
            return "10.arrow.trianglehead.counterclockwise"
        case .seekForward:
            return "10.arrow.trianglehead.clockwise"
        case .playPause:
            return "play.fill"
        case .orientationLock:
            return "lock.rotation"
        case .panelToggle:
            return "sidebar.trailing"
        case .playPrevious:
            return "backward.fill"
        case .playNext:
            return "forward.fill"
        case .queue:
            return "list.bullet"
        case .settings:
            return "gearshape"
        case .controlsLock:
            return "lock"
        case .titleAuthor:
            return "text.below.photo"
        case .panscan:
            return "arrow.left.and.right.square"
        case .autoPlayNext:
            return "play.square.stack.fill"
        case .seek:
            return "goforward.10" // Default icon, actual icon is determined by settings
        }
    }

    // MARK: - Configuration

    /// Whether this button type has configurable settings.
    var hasSettings: Bool {
        switch self {
        case .spacer, .brightness, .volume, .seekBackward, .seekForward, .timeDisplay, .titleAuthor, .seek:
            return true
        default:
            return false
        }
    }

    /// Default settings for this button type, if applicable.
    var defaultSettings: ButtonSettings? {
        switch self {
        case .spacer:
            return .spacer(SpacerSettings())
        case .brightness, .volume:
            return .slider(SliderSettings())
        case .seekBackward, .seekForward:
            return .seek(SeekSettings())
        case .timeDisplay:
            return .timeDisplay(TimeDisplaySettings())
        case .titleAuthor:
            return .titleAuthor(TitleAuthorSettings())
        case .seek:
            return .seek(SeekSettings())
        default:
            return nil
        }
    }

    // MARK: - Section Availability

    /// Button types available for top/bottom sections.
    static var availableForHorizontalSections: [ControlButtonType] {
        [
            .spacer,
            .timeDisplay,
            .titleAuthor,
            .playPrevious,
            .playPause,
            .playNext,
            .seek,
            .queue,
            .close,
            .brightness,
            .volume,
            .pictureInPicture,
            .fullscreen,
            .orientationLock,
            .controlsLock,
            .settings,
            .videoTrack,
            .audioTrack,
            .captions,
            .chapters,
            .playbackSpeed,
            .addToPlaylist,
            .contextMenu,
            .share,
            .panelToggle,
            .panscan,
            .autoPlayNext,
            .airplay,
            .mpvDebug
        ]
    }

    /// Button types for center section (play/pause, seek).
    static var availableForCenterSection: [ControlButtonType] {
        [.playPause, .seekBackward, .seekForward]
    }

    /// Button types available for the player pill (curated subset).
    static var availableForPill: [ControlButtonType] {
        [
            // Transport
            .playPause,
            .playPrevious,
            .playNext,
            .seek,
            // Queue & Playlist
            .queue,
            .addToPlaylist,
            // Player Actions
            .close,
            .share,
            .airplay,
            .pictureInPicture,
            // Utility
            .orientationLock,
            .playbackSpeed,
            .fullscreen
        ]
    }

    /// Button types available for the mini player (curated subset for compact UI).
    static var availableForMiniPlayer: [ControlButtonType] {
        [
            // Transport
            .playPause,
            .playPrevious,
            .playNext,
            .seek,
            // Queue & Actions
            .queue,
            .close,
            // Player Actions
            .share,
            .addToPlaylist,
            .airplay,
            .pictureInPicture,
            // Utility
            .playbackSpeed
        ]
    }
}
