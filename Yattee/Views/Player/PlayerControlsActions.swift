//
//  PlayerControlsActions.swift
//  Yattee
//
//  Consolidated actions and state for player control buttons.
//

import SwiftUI

#if os(iOS)

/// Consolidated actions and state for player control buttons.
/// Used by `ControlsSectionRenderer` to render buttons dynamically.
@MainActor
struct PlayerControlsActions {
    // MARK: - State

    /// The current player state
    let playerState: PlayerState

    /// Whether the layout is widescreen (landscape fullscreen)
    let isWideScreenLayout: Bool

    /// Whether fullscreen mode is active
    let isFullscreen: Bool

    /// Whether the video is widescreen aspect ratio
    let isWidescreenVideo: Bool

    /// Whether orientation is locked
    let isOrientationLocked: Bool

    /// Whether the side panel is visible
    let isPanelVisible: Bool

    /// Whether the side panel is pinned (iPad landscape)
    let isPanelPinned: Bool

    /// Which side the panel is on
    let panelSide: FloatingPanelSide

    /// Whether running on iPad
    let isIPad: Bool

    /// Whether volume controls should show (mpv mode)
    let showVolumeControls: Bool

    /// Whether debug button should show
    let showDebugButton: Bool

    /// Whether close button should show
    let showCloseButton: Bool

    /// The currently playing video (for share, playlist, context menu)
    let currentVideo: Video?

    /// Available captions for the current video
    let availableCaptions: [Caption]

    /// Currently selected caption
    let currentCaption: Caption?

    /// Available streams for the current video
    let availableStreams: [Stream]

    /// Current video stream
    let currentStream: Stream?

    /// Current audio stream
    let currentAudioStream: Stream?

    /// Current panscan value (0.0 = fit, 1.0 = fill)
    let panscanValue: Double

    /// Whether panscan change is currently allowed
    let isPanscanAllowed: Bool

    /// Whether auto-play next is enabled
    let isAutoPlayNextEnabled: Bool

    /// Yattee Server URL for channel avatar fallback
    let yatteeServerURL: URL?

    /// DeArrow branding provider for title replacement
    let deArrowBrandingProvider: DeArrowBrandingProvider?

    // MARK: - Actions

    /// Close the player
    var onClose: (() -> Void)?

    /// Toggle debug overlay
    var onToggleDebug: (() -> Void)?

    /// Toggle Picture-in-Picture
    var onTogglePiP: (() -> Void)?

    /// Toggle fullscreen mode
    var onToggleFullscreen: (() -> Void)?

    /// Toggle details visibility (portrait fullscreen)
    var onToggleDetailsVisibility: (() -> Void)?

    /// Toggle orientation lock
    var onToggleOrientationLock: (() -> Void)?

    /// Toggle side panel
    var onTogglePanel: (() -> Void)?

    /// Toggle panscan between 0 and 1
    var onTogglePanscan: (() -> Void)?

    /// Toggle auto-play next in queue
    var onToggleAutoPlayNext: (() -> Void)?

    /// Show settings sheet
    var onShowSettings: (() -> Void)?

    /// Play next video in queue
    var onPlayNext: (() async -> Void)?

    /// Play previous video in queue
    var onPlayPrevious: (() async -> Void)?

    /// Toggle play/pause
    var onPlayPause: (() -> Void)?

    /// Seek forward by specified seconds
    var onSeekForward: ((TimeInterval) async -> Void)?

    /// Seek backward by specified seconds
    var onSeekBackward: ((TimeInterval) async -> Void)?

    /// Volume changed (0.0-1.0)
    var onVolumeChanged: ((Float) -> Void)?

    /// Toggle mute
    var onMuteToggled: (() -> Void)?

    /// Timer control callbacks for slider interactions
    var onCancelHideTimer: (() -> Void)?
    var onResetHideTimer: (() -> Void)?

    /// Called when slider adjustment state changes (volume or brightness)
    var onSliderAdjustmentChanged: ((Bool) -> Void)?

    /// Change playback rate
    var onRateChanged: ((PlaybackRate) -> Void)?

    /// Select caption
    var onCaptionSelected: ((Caption?) -> Void)?

    /// Show playlist selector sheet
    var onShowPlaylistSelector: (() -> Void)?

    /// Show queue management sheet
    var onShowQueue: (() -> Void)?

    /// Show captions selector sheet
    var onShowCaptionsSelector: (() -> Void)?

    /// Show chapters selector sheet
    var onShowChaptersSelector: (() -> Void)?

    /// Show video track selector sheet
    var onShowVideoTrackSelector: (() -> Void)?

    /// Show audio track selector sheet
    var onShowAudioTrackSelector: (() -> Void)?

    /// Toggle controls lock state
    var onControlsLockToggled: ((Bool) -> Void)?

    // MARK: - Computed Properties

    /// Whether controls are locked (all buttons disabled except settings)
    var isControlsLocked: Bool {
        playerState.isControlsLocked
    }

    /// Current playback rate display text (shows rate when not 1x)
    var playbackRateDisplay: String? {
        let rate = playerState.rate
        if rate == .x1 {
            return nil
        }
        return String(format: "%.2gx", rate.rawValue)
    }

    /// Whether share is available (has video with share URL)
    var canShare: Bool {
        currentVideo != nil
    }

    /// Whether add to playlist is available
    var canAddToPlaylist: Bool {
        guard let video = currentVideo else { return false }
        return !video.isFromLocalFolder
    }

    /// Whether captions are available
    var hasCaptions: Bool {
        !availableCaptions.isEmpty
    }

    /// Whether chapters are available
    var hasChapters: Bool {
        !playerState.chapters.isEmpty
    }

    /// PiP icon based on current state
    var pipIcon: String {
        playerState.pipState == .active ? "pip.exit" : "pip.enter"
    }

    /// Fullscreen icon based on current state.
    /// Uses rotation icons when tapping will cause device rotation,
    /// otherwise uses standard fullscreen arrows.
    var fullscreenIcon: String {
        if willRotateOnFullscreenToggle {
            if isFullscreen {
                // Currently landscape fullscreen, will rotate to portrait
                return "rectangle.portrait.rotate"
            } else {
                // Currently portrait, will rotate to landscape
                return "rectangle.landscape.rotate"
            }
        } else {
            // Standard fullscreen icons (iPad or portrait video details toggle)
            return isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        }
    }

    /// Whether tapping fullscreen will cause device rotation.
    /// Mirrors the logic in ControlsSectionRenderer.handleFullscreenTap()
    var willRotateOnFullscreenToggle: Bool {
        // iPad never rotates via fullscreen button
        guard !isIPad else { return false }

        let isActualWidescreenLayout = isWideScreenLayout && onTogglePanel != nil

        if isActualWidescreenLayout && isFullscreen && !isWidescreenVideo {
            // iPhone in landscape with portrait video: rotates to portrait
            return true
        } else if !isWidescreenVideo {
            // iPhone portrait video in portrait: no rotation (toggles details)
            return false
        } else {
            // iPhone widescreen video: rotates
            return true
        }
    }

    /// Orientation lock icon based on current state
    var orientationLockIcon: String {
        isOrientationLocked ? "lock.rotation" : "lock.rotation.open"
    }

    /// Panel toggle icon (flipped based on panel side)
    var panelToggleIcon: String {
        "sidebar.trailing"
    }

    /// Panscan icon based on current state
    var panscanIcon: String {
        panscanValue > 0.5 ? "arrow.left.and.right.square.fill" : "arrow.left.and.right.square"
    }

    /// Whether the fullscreen button should be shown
    var shouldShowFullscreenButton: Bool {
        // iPad widescreen (true landscape): hidden (can't force rotation)
        let isActualWidescreen = isWideScreenLayout && onTogglePanel != nil
        let showFullscreenButton = !(isIPad && isActualWidescreen)
        let hasFullscreenAction = onToggleFullscreen != nil || onToggleDetailsVisibility != nil

        // Hide on iPad when panel is pinned and visible (tapping does nothing)
        let isPinnedPanelActive = isIPad && isPanelPinned && isPanelVisible

        return showFullscreenButton && hasFullscreenAction && !isPinnedPanelActive
    }

    /// Whether PiP button should be enabled
    var isPiPAvailable: Bool {
        playerState.isPiPPossible
    }

    /// Whether play next button should be enabled
    var hasNextInQueue: Bool {
        playerState.hasNext
    }

    /// Whether play previous button should be enabled
    var hasPreviousInQueue: Bool {
        playerState.hasPrevious
    }
}

#endif
