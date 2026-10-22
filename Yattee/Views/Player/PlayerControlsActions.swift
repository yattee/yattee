//
//  PlayerControlsActions.swift
//  Yattee
//
//  Consolidated actions and state for player control buttons.
//

import SwiftUI

#if os(iOS) || os(macOS)

/// Consolidated actions and state for player control buttons.
/// Used by `ControlsSectionRenderer` (iOS) and `MacOSControlsSectionRenderer`
/// (macOS) to render buttons dynamically.
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

    #if os(iOS)
    /// Whether orientation is locked
    let isOrientationLocked: Bool
    #endif

    /// Whether the side panel is visible
    let isPanelVisible: Bool

    #if os(iOS)
    /// Whether the side panel is pinned (iPad landscape)
    let isPanelPinned: Bool

    /// Whether the corner layout is active: the fullscreen button then
    /// toggles the panels (hide = fullscreen video, unhide on next press)
    var isCornerLayout: Bool = false
    #endif

    /// Which side the panel is on
    let panelSide: FloatingPanelSide

    #if os(iOS)
    /// Whether running on iPad
    let isIPad: Bool

    /// Whether the system honors programmatic rotation requests. False on the
    /// iPhone Duo interior display, which then gets the iPad fullscreen
    /// behavior (details toggle, no rotate glyph, no orientation lock).
    var canRotate: Bool = true

    /// Screen of the window hosting the controls; brightness targets it
    /// (iPhone Duo interior and exterior are separate screens).
    var screen: UIScreen?

    /// iPad, or an iPhone windowing mode that can't rotate on request.
    var usesRotationFreeFullscreen: Bool { isIPad || !canRotate }

    /// Rotation-free fullscreen in a layout without a details toggle: the
    /// button shows/hides the panel instead, so the icon tracks the panel.
    var togglesPanelOnFullscreen: Bool {
        usesRotationFreeFullscreen && onToggleDetailsVisibility == nil && onTogglePanel != nil
    }
    #endif

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

    /// Embedded (in-container) tracks reported by mpv for the loaded file
    var embeddedSubtitleTracks: [MPVTrack] = []
    var currentEmbeddedSubtitleTrackID: Int? = nil

    #if os(iOS)
    /// Current panscan value (0.0 = fit, 1.0 = fill)
    let panscanValue: Double

    /// Whether panscan change is currently allowed
    let isPanscanAllowed: Bool
    #endif

    /// Whether auto-play next is enabled
    let isAutoPlayNextEnabled: Bool

    /// Whether audio-only (music) mode is enabled
    var isAudioModeEnabled: Bool = false

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

    /// Hide the controls overlay (corner layout hides them before the
    /// panel toggle so the controls-resize never plays visibly)
    var onHideControls: (() -> Void)?

    #if os(iOS)
    /// Toggle orientation lock
    var onToggleOrientationLock: (() -> Void)?
    #endif

    /// Toggle side panel
    var onTogglePanel: (() -> Void)?

    #if os(iOS)
    /// Toggle panscan between 0 and 1
    var onTogglePanscan: (() -> Void)?
    #endif

    /// Toggle auto-play next in queue
    var onToggleAutoPlayNext: (() -> Void)?

    /// Toggle audio-only (music) mode
    var onToggleAudioMode: (() -> Void)?

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

    /// Whether add to playlist is available
    var canAddToPlaylist: Bool {
        guard let video = currentVideo else { return false }
        return !video.isFromLocalFolder
    }

    /// Whether captions are available (external files or embedded tracks)
    var hasCaptions: Bool {
        !availableCaptions.isEmpty || !embeddedSubtitleTracks.isEmpty
    }

    /// Whether an external subtitle file can be loaded: media-source playback
    /// (local folder/SMB/WebDAV) on platforms with a file picker.
    var canLoadExternalSubtitles: Bool {
        #if os(tvOS)
        return false
        #else
        return currentVideo?.isFromMediaSource == true
        #endif
    }

    /// Whether chapters are available
    var hasChapters: Bool {
        !playerState.chapters.isEmpty
    }

    /// PiP icon based on current state
    var pipIcon: String {
        playerState.pipState == .active ? "pip.exit" : "pip.enter"
    }

    #if os(macOS)
    /// Fullscreen icon based on current state (no rotation semantics on macOS).
    var fullscreenIcon: String {
        isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
    }

    /// Whether the fullscreen button should be shown
    var shouldShowFullscreenButton: Bool {
        onToggleFullscreen != nil
    }
    #else
    /// Fullscreen icon based on current state.
    /// Uses rotation icons when tapping will cause device rotation,
    /// otherwise uses standard fullscreen arrows.
    var fullscreenIcon: String {
        if isCornerLayout || togglesPanelOnFullscreen {
            // Corner layout / rotation-free widescreen: reflects the panel
            // state, not orientation
            return isPanelVisible ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        }
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

    /// Shared fullscreen-tap decision used by the fullscreen button and tap gestures.
    /// Keep in sync with `willRotateOnFullscreenToggle` (icon mirror of this logic).
    func performFullscreenTap() {
        if isCornerLayout {
            // Corner layout: hide the controls and toggle the panels —
            // the controls fade out while the panel transition plays
            onHideControls?()
            onTogglePanel?()
            return
        }

        let isActualWidescreenLayout = isWideScreenLayout && onTogglePanel != nil

        if usesRotationFreeFullscreen {
            // iPad (or no programmatic rotation): toggle details visibility.
            // The widescreen layout has no details toggle — there fullscreen
            // means hiding the floating panel, like the corner layout.
            if let onToggleDetailsVisibility {
                onToggleDetailsVisibility()
            } else if togglesPanelOnFullscreen {
                onHideControls?()
                onTogglePanel?()
            }
        } else if isActualWidescreenLayout && isFullscreen && !isWidescreenVideo {
            // iPhone in landscape with portrait video fullscreen: rotate back to portrait
            onToggleFullscreen?()
        } else if !isWidescreenVideo {
            // iPhone portrait video in portrait layout: toggle details visibility
            onToggleDetailsVisibility?()
        } else {
            // iPhone with widescreen video: rotate orientation
            onToggleFullscreen?()
        }
    }

    /// Whether tapping fullscreen will cause device rotation.
    /// Mirrors the logic in `performFullscreenTap()`
    var willRotateOnFullscreenToggle: Bool {
        // iPad never rotates via fullscreen button; neither does a windowing
        // mode that refuses programmatic rotation
        guard !usesRotationFreeFullscreen else { return false }

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
        // Corner layout: always shown, toggles the panels both ways
        if isCornerLayout {
            return onTogglePanel != nil
        }

        // iPad widescreen (true landscape): hidden (can't force rotation).
        // Only real iPads: a rotation-free iPhone (Duo interior) with the
        // panel hidden still needs the button to bring the panel back.
        let isActualWidescreen = isWideScreenLayout && onTogglePanel != nil
        let showFullscreenButton = !(isIPad && isActualWidescreen)
        let hasFullscreenAction = onToggleFullscreen != nil || onToggleDetailsVisibility != nil

        // Hide on iPad when panel is pinned and visible (tapping does nothing)
        let isPinnedPanelActive = isIPad && isPanelPinned && isPanelVisible

        return showFullscreenButton && hasFullscreenAction && !isPinnedPanelActive
    }
    #endif

    /// Whether PiP button should be enabled.
    /// No video track in audio-only playback - `isPiPPossible` may lag behind
    /// a video-to-audio reload on a reused backend, so gate explicitly.
    var isPiPAvailable: Bool {
        playerState.isPiPPossible && playerState.currentStream?.isAudioOnly != true
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
