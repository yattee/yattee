//
//  PlayerControlsView.swift
//  Yattee
//
//  Custom player controls overlay for iOS with play/pause, seek, and time display.
//

import SwiftUI

#if os(iOS)

// MARK: - Controls Theme Modifier

/// A view modifier that applies the controls theme color scheme.
private struct ControlsThemeModifier: ViewModifier {
    let theme: ControlsTheme
    @Environment(\.colorScheme) private var systemColorScheme

    func body(content: Content) -> some View {
        if let forcedScheme = theme.colorScheme {
            content.environment(\.colorScheme, forcedScheme)
        } else {
            content.environment(\.colorScheme, systemColorScheme)
        }
    }
}

struct PlayerControlsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Bindable var playerState: PlayerState
    let onPlayPause: () -> Void
    let onSeek: (TimeInterval) async -> Void
    let onSeekForward: (TimeInterval) async -> Void
    let onSeekBackward: (TimeInterval) async -> Void
    var onToggleFullscreen: (() -> Void)? = nil
    var isFullscreen: Bool = false
    var isWidescreenVideo: Bool = false
    var onClose: (() -> Void)? = nil
    var onTogglePiP: (() -> Void)? = nil
    var onToggleDebug: (() -> Void)? = nil
    var isWideScreenLayout: Bool = false
    var onTogglePanel: (() -> Void)? = nil
    var isPanelVisible: Bool = true
    var panelSide: FloatingPanelSide = .right
    var isPanelPinned: Bool = false
    /// Safe area padding from layout (when panel is pinned)
    var layoutLeadingSafeArea: CGFloat = 0
    var layoutTrailingSafeArea: CGFloat = 0
    var onToggleOrientationLock: (() -> Void)? = nil
    var isOrientationLocked: Bool = false
    var onToggleDetailsVisibility: (() -> Void)? = nil
    var onShowSettings: (() -> Void)? = nil
    /// Callback to play next video in queue
    var onPlayNext: (() async -> Void)? = nil
    /// Callback to play previous video in queue
    var onPlayPrevious: (() async -> Void)? = nil
    /// Callback to show queue management sheet
    var onShowQueue: (() -> Void)? = nil
    /// When true, forces controls to start hidden (user must tap to reveal)
    var forceInitialHidden: Bool = false

    /// Video area top offset from screen top (for positioning controls within video bounds)
    var videoAreaTop: CGFloat = 0
    /// Video area height (for positioning controls within video bounds, nil = use full geometry height)
    var videoAreaHeight: CGFloat? = nil
    /// Video fit height for slider sizing (stable during drag, unlike videoAreaHeight)
    var videoFitHeight: CGFloat? = nil

    /// Callback when volume changes (value 0.0-1.0)
    var onVolumeChanged: ((Float) -> Void)? = nil
    /// Callback when mute state toggles
    var onMuteToggled: (() -> Void)? = nil

    // MARK: - Video Context Properties (for share, playlist, captions, context menu)

    /// Currently playing video (for share, playlist, context menu)
    var currentVideo: Video? = nil
    /// Available captions for captions button
    var availableCaptions: [Caption] = []
    /// Currently selected caption
    var currentCaption: Caption? = nil
    /// Available streams for quality selector (when showing captions)
    var availableStreams: [Stream] = []
    /// Current video stream
    var currentStream: Stream? = nil
    /// Current audio stream
    var currentAudioStream: Stream? = nil
    /// Callback when playback rate changes
    var onRateChanged: ((PlaybackRate) -> Void)? = nil
    /// Callback when caption is selected
    var onCaptionSelected: ((Caption?) -> Void)? = nil
    /// Callback when stream is selected (for quality selector integration)
    var onStreamSelected: ((Stream, Stream?) -> Void)? = nil

    /// Current panscan value (0.0 = fit, 1.0 = fill)
    var panscanValue: Double = 0.0
    /// Whether panscan change is currently allowed
    var isPanscanAllowed: Bool = false
    /// Callback to toggle panscan between 0 and 1
    var onTogglePanscan: (() -> Void)? = nil

    // MARK: - Sheet State

    @State private var showingPlaylistSheet = false
    @State private var showingCaptionsSheet = false
    @State private var showingVideoTrackSheet = false
    @State private var showingAudioTrackSheet = false
    @State private var showingChaptersSheet = false

    private var showPlayerAreaDebug: Bool {
        appEnvironment?.settingsManager.showPlayerAreaDebug ?? false
    }

    private var isDismissGestureActive: Bool {
        appEnvironment?.navigationCoordinator.isPlayerDismissGestureActive ?? false
    }

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var isPendingSeek = false
    /// Target progress for pending seek - used to detect when playerState.progress converges
    @State private var targetSeekProgress: Double = 0
    @State private var hideTimer: Timer?
    @State private var showControls: Bool?
    @State private var isAdjustingVolume = false
    @State private var isAdjustingBrightness = false
    /// Tracks brightness value for side slider (needed because UIScreen.main.brightness isn't observable)
    @State private var currentBrightness: Double = UIScreen.main.brightness
    @State private var playNextTapCount = 0
    /// Track safe area to force re-render when it changes
    @State private var currentSafeArea: UIEdgeInsets = .zero
    /// Active player controls layout from preset (passed from parent to avoid flashing during view recreation)
    var activeLayout: PlayerControlsLayout = .default
    /// Animation trigger for seek backward button
    @State private var seekBackwardTrigger = false
    /// Animation trigger for seek forward button
    @State private var seekForwardTrigger = false

    // MARK: - Gesture State

    /// Gesture action handler for seek accumulation
    private let gestureActionHandler = PlayerGestureActionHandler()
    /// Current tap gesture feedback to display
    @State private var currentTapFeedback: (action: TapGestureAction, position: TapZonePosition, accumulated: Int?)?
    /// Pending seek to execute when feedback completes (direction, accumulated seconds)
    @State private var pendingSeek: (isForward: Bool, seconds: Int)?

    // MARK: - Seek Gesture State

    /// Whether the seek gesture is currently active (shared with NavigationCoordinator for mutual exclusion with pinch gesture)
    private var isSeekGestureActive: Bool {
        get { appEnvironment?.navigationCoordinator.isSeekGestureActive ?? false }
        nonmutating set { appEnvironment?.navigationCoordinator.isSeekGestureActive = newValue }
    }
    /// Preview time during seek gesture
    @State private var seekGesturePreviewTime: TimeInterval = 0
    /// Current time when seek gesture started (for relative seeking)
    @State private var seekGestureStartTime: TimeInterval = 0
    /// Screen width for seek calculation (captured from geometry)
    @State private var screenWidth: CGFloat = 0
    /// Whether boundary haptic was already triggered during current gesture
    @State private var seekGestureBoundaryHapticTriggered = false

    /// Controls visibility - only show when user interacts or explicitly pauses
    private var shouldShowControls: Bool {
        if let showControls {
            return showControls
        }
        // If forced hidden, require explicit tap to show
        if forceInitialHidden {
            return false
        }
        // Initial state: show if paused, hide otherwise (including during loading/buffering)
        return playerState.playbackState == .paused
    }

    var body: some View {
        GeometryReader { geometry in

            ZStack {
                // Gesture overlay (active when controls are hidden)
                gestureOverlayLayer(geometry: geometry)

                // Tap to show/hide controls (fallback when gestures disabled)
                if !gesturesEffectivelyEnabled {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleControlsVisibility()
                        }
                        .allowsHitTesting(playerState.playbackState != .ended && !playerState.isFailed)
                }

                // Controls overlay
                controlsOverlay
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(shouldShowControls ? 1 : 0)
                    .allowsHitTesting(shouldShowControls)
                    .modifier(ControlsThemeModifier(theme: activeLayout.globalSettings.theme))

                // Gesture feedback overlays
                gestureFeedbackLayer(geometry: geometry)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowControls)
        .onChange(of: playerState.playbackState) { oldState, newState in
            // When playback starts after being paused/loading, start hide timer if controls are showing
            if newState == .playing && shouldShowControls {
                startHideTimer()
            }
            // Hide controls when video ends (ended overlay takes over)
            if newState == .ended {
                showControls = false
                cancelHideTimer()
            }
            // Hide controls when video fails (failed overlay takes over)
            if case .failed = newState {
                showControls = false
                cancelHideTimer()
            }
        }
        .onChange(of: playerState.retryState.exhausted) { _, exhausted in
            // Hide controls when retries are exhausted (retry exhausted overlay takes over)
            if exhausted {
                showControls = false
                cancelHideTimer()
            }
        }
        .onChange(of: forceInitialHidden) { _, hidden in
            // Reset controls visibility when forced hidden (e.g., during fullscreen transition)
            if hidden {
                showControls = nil
                cancelHideTimer()
            }
        }
        .onChange(of: showControls) { _, newValue in
            // Sync local controls visibility to playerState for other views to observe
            playerState.controlsVisible = newValue ?? (playerState.playbackState == .paused)
        }
        .onAppear {
            // Update safe area on appear to ensure correct layout
            currentSafeArea = windowSafeArea
            // Sync initial controls visibility to playerState
            playerState.controlsVisible = shouldShowControls
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { _ in
            // Update safe area when geometry changes (rotation)
            currentSafeArea = windowSafeArea
        }
        .onChange(of: activeLayout.effectiveGesturesSettings.panscanGesture.snapToEnds, initial: true) { _, newValue in
            // Sync panscan snap setting to navigation coordinator (initial: true ensures sync on first render)
            appEnvironment?.navigationCoordinator.shouldSnapPanscan = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
            currentBrightness = UIScreen.main.brightness
        }
        .sheet(isPresented: $showingPlaylistSheet) {
            if let video = currentVideo {
                PlaylistSelectorSheet(video: video)
            }
        }
        .sheet(isPresented: $showingCaptionsSheet) {
            captionsSheet
        }
        .sheet(isPresented: $showingVideoTrackSheet) {
            videoTrackSheet
        }
        .sheet(isPresented: $showingAudioTrackSheet) {
            audioTrackSheet
        }
        .sheet(isPresented: $showingChaptersSheet) {
            chaptersSheet
        }
    }

    // MARK: - Track Selector Sheets

    @ViewBuilder
    private var captionsSheet: some View {
        QualitySelectorView(
            streams: [],
            captions: availableCaptions,
            currentStream: nil,
            currentCaption: currentCaption,
            initialTab: .subtitles,
            showTabPicker: false,
            onStreamSelected: { _, _ in },
            onCaptionSelected: { caption in
                onCaptionSelected?(caption)
            }
        )
    }

    @ViewBuilder
    private var videoTrackSheet: some View {
        QualitySelectorView(
            streams: availableStreams,
            captions: [],
            currentStream: currentStream,
            currentAudioStream: currentAudioStream,
            initialTab: .video,
            showTabPicker: false,
            onStreamSelected: { stream, audioStream in
                onStreamSelected?(stream, audioStream)
            },
            onCaptionSelected: { _ in }
        )
    }

    @ViewBuilder
    private var audioTrackSheet: some View {
        QualitySelectorView(
            streams: availableStreams,
            captions: [],
            currentStream: currentStream,
            currentAudioStream: currentAudioStream,
            initialTab: .audio,
            showTabPicker: false,
            onStreamSelected: { stream, audioStream in
                onStreamSelected?(stream, audioStream)
            },
            onCaptionSelected: { _ in }
        )
    }

    @ViewBuilder
    private var chaptersSheet: some View {
        ChaptersView(
            chapters: playerState.chapters,
            currentTime: playerState.currentTime,
            storyboard: playerState.preferredStoryboard,
            onChapterTap: { chapter in
                await onSeek(chapter.startTime)
            }
        )
    }

    // MARK: - Controls Overlay

    /// Whether running on iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Get safe area from window (works even when view ignores safe area)
    private var windowSafeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first?
            .safeAreaInsets ?? .zero
    }

    /// Whether to show in-app volume controls (only when volume mode is .mpv)
    private var showVolumeControls: Bool {
        GlobalLayoutSettings.cached.volumeMode == .mpv
    }

    /// Build the consolidated actions for the section renderer
    private var controlsActions: PlayerControlsActions {
        PlayerControlsActions(
            playerState: playerState,
            isWideScreenLayout: isWideScreenLayout,
            isFullscreen: isFullscreen,
            isWidescreenVideo: isWidescreenVideo,
            isOrientationLocked: isOrientationLocked,
            isPanelVisible: isPanelVisible,
            isPanelPinned: isPanelPinned,
            panelSide: panelSide,
            isIPad: isIPad,
            showVolumeControls: showVolumeControls,
            showDebugButton: onToggleDebug != nil,
            showCloseButton: onClose != nil,
            currentVideo: currentVideo,
            availableCaptions: availableCaptions,
            currentCaption: currentCaption,
            availableStreams: availableStreams,
            currentStream: currentStream,
            currentAudioStream: currentAudioStream,
            panscanValue: panscanValue,
            isPanscanAllowed: isPanscanAllowed,
            isAutoPlayNextEnabled: appEnvironment?.settingsManager.queueAutoPlayNext ?? true,
            yatteeServerURL: appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url,
            deArrowBrandingProvider: appEnvironment?.deArrowBrandingProvider,
            onClose: onClose,
            onToggleDebug: onToggleDebug,
            onTogglePiP: onTogglePiP,
            onToggleFullscreen: onToggleFullscreen,
            onToggleDetailsVisibility: onToggleDetailsVisibility,
            onToggleOrientationLock: onToggleOrientationLock,
            onTogglePanel: onTogglePanel,
            onTogglePanscan: onTogglePanscan,
            onToggleAutoPlayNext: {
                appEnvironment?.settingsManager.queueAutoPlayNext.toggle()
            },
            onShowSettings: onShowSettings,
            onPlayNext: onPlayNext,
            onPlayPrevious: onPlayPrevious,
            onPlayPause: onPlayPause,
            onSeekForward: { seconds in await onSeekForward(seconds) },
            onSeekBackward: { seconds in await onSeekBackward(seconds) },
            onVolumeChanged: onVolumeChanged,
            onMuteToggled: onMuteToggled,
            onCancelHideTimer: { [self] in cancelHideTimer() },
            onResetHideTimer: { [self] in resetHideTimer() },
            onSliderAdjustmentChanged: { isAdjusting in
                appEnvironment?.navigationCoordinator.isAdjustingPlayerSliders = isAdjusting
            },
            onRateChanged: onRateChanged,
            onCaptionSelected: onCaptionSelected,
            onShowPlaylistSelector: { [self] in showingPlaylistSheet = true },
            onShowQueue: onShowQueue,
            onShowCaptionsSelector: { [self] in showingCaptionsSheet = true },
            onShowChaptersSelector: { [self] in showingChaptersSheet = true },
            onShowVideoTrackSelector: { [self] in showingVideoTrackSheet = true },
            onShowAudioTrackSelector: { [self] in showingAudioTrackSheet = true },
            onControlsLockToggled: { locked in
                playerState.isControlsLocked = locked
            }
        )
    }

    private var controlsOverlay: some View {
        ZStack {
            // Background fill - extends into safe areas (except during dismiss gesture)
            if isDismissGestureActive {
                Color.black.opacity(0.5)
                    .allowsHitTesting(false)
            } else {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Controls layout - explicitly fill parent bounds
            controlsVStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controlsVStack: some View {
        // Use currentSafeArea state to ensure view updates when safe area changes
        let safeArea = currentSafeArea
        let basePadding: CGFloat = 12

        // Vertical padding - always apply in widescreen (layout ignores safe area)
        let topPadding: CGFloat = 2 + (isWideScreenLayout ? safeArea.top + 8 : 0)

        // Bottom padding - add safe area when controls are at screen bottom in fullscreen modes
        // When floating panel is visible (isPanelVisible && !isPanelPinned),
        // bottomExtraPadding handles positioning, so no safe area needed
        // In landscape (widescreen), cap the safe area since home indicator needs less clearance
        let floatingPanelActive = isPanelVisible && !isPanelPinned
        let needsBottomSafeArea = (isWideScreenLayout || isFullscreen) && !floatingPanelActive
        let bottomSafeArea = isWideScreenLayout ? min(safeArea.bottom, 12) : safeArea.bottom
        let bottomPadding: CGFloat = 2 + (needsBottomSafeArea ? bottomSafeArea : 0)

        // Horizontal padding - depends on panel state
        // When pinned, use layout-provided safe areas which account for panel and Dynamic Island
        let leftPadding: CGFloat
        let rightPadding: CGFloat

        // When panel is pinned AND visible, the controls frame is already constrained by layout
        // so we only need base padding (no additional safe area padding needed)
        // When panel is hidden or not pinned, controls must handle safe areas themselves
        let frameAlreadySafeAreaAdjusted = isWideScreenLayout && isPanelPinned && isPanelVisible

        if isWideScreenLayout {
            if frameAlreadySafeAreaAdjusted {
                // Frame is already positioned/sized to avoid panel and Dynamic Island
                // Just use base padding for aesthetics
                leftPadding = basePadding
                rightPadding = basePadding
            } else {
                // Panel not visible or not pinned - controls handle all safe areas (symmetric with max)
                let safeAreaPadding = max(safeArea.left, safeArea.right) + 4
                leftPadding = basePadding + safeAreaPadding
                rightPadding = basePadding + safeAreaPadding
            }
        } else {
            leftPadding = basePadding
            rightPadding = basePadding
        }

        let safeAreaOffset = isWideScreenLayout ? (safeArea.top - safeArea.bottom) / 2 : 0

        let centerSettings = activeLayout.centerSettings
        let buttonBackground = activeLayout.globalSettings.buttonBackground
        let theme = activeLayout.globalSettings.theme

        return GeometryReader { geometry in
            // Detect compact vertical mode for wide aspect ratio videos with limited height
            let isCompactVertical = geometry.size.height < 200

            // Video area bounds - use provided values or default to full geometry
            let effectiveVideoTop = videoAreaTop
            let effectiveVideoHeight = videoAreaHeight ?? geometry.size.height
            let effectiveVideoBottom = effectiveVideoTop + effectiveVideoHeight

            // Calculate center offset for video area (to position center controls within video bounds)
            let videoCenterY = effectiveVideoTop + effectiveVideoHeight / 2
            let screenCenterY = geometry.size.height / 2
            let centerYOffset = videoCenterY - screenCenterY

            // Only apply safeAreaOffset when no explicit video area bounds are provided
            // (i.e., when videoAreaHeight is nil and we're using full geometry)
            let hasExplicitVideoArea = videoAreaHeight != nil
            let effectiveSafeAreaOffset = hasExplicitVideoArea ? 0 : safeAreaOffset

            // Extra padding at bottom to account for space below video area
            let bottomExtraPadding = geometry.size.height - effectiveVideoBottom

            ZStack {
                // Top bar - aligned to screen top (stays fixed regardless of video area)
                VStack {
                    topBar
                        .padding(.top, topPadding)
                        .padding(.leading, leftPadding)
                        .padding(.trailing, rightPadding)
                        .applyCornerAdaptationOffset()
                        .overlay {
                            if showPlayerAreaDebug {
                                Rectangle().stroke(Color.green, lineWidth: 1)
                            }
                        }
                    Spacer()
                }

                // Calculate horizontal space for center controls scaling
                let sliderWidth: CGFloat = 36
                let leftSliderOccupies = centerSettings.leftSlider != .disabled ? sliderWidth + leftPadding : 0
                let rightSliderOccupies = centerSettings.rightSlider != .disabled ? sliderWidth + rightPadding : 0
                let availableForCenter = geometry.size.width - leftSliderOccupies - rightSliderOccupies - 24 // 24pt margin

                let requiredWidth = centerControlsRequiredWidth(
                    compact: isCompactVertical,
                    hasBackground: buttonBackground.glassStyle != nil,
                    settings: centerSettings
                )
                let horizontalScale = requiredWidth > 0 ? min(1.0, max(0.6, availableForCenter / requiredWidth)) : 1.0

                // Center controls - centered within video area
                centerControls(compact: isCompactVertical, scale: horizontalScale)
                    .offset(y: centerYOffset - effectiveSafeAreaOffset)

                // Vertical side sliders - constrained to video area
                // Position using same offset as center controls for proper vertical alignment
                // Rendered BEFORE bottom bar so seek preview appears above sliders
                if !isCompactVertical {
                    // Calculate available height for sliders
                    // Use full video area height for sliders (extends into letterbox areas)
                    let sliderBasisHeight = effectiveVideoHeight
                    let baseSliderAreaHeight = sliderBasisHeight - 48 - 100
                    // When videoFitHeight provided (panel/drag): use stable sizing within video
                    // When nil (fullscreen): target 250pt sliders when there's extra space
                    let isFullscreenWithSpace = videoFitHeight == nil && geometry.size.height > sliderBasisHeight * 1.5
                    let sliderAreaHeight: CGFloat = isFullscreenWithSpace
                        ? min(250, geometry.size.height - 200)
                        : max(80, baseSliderAreaHeight)

                    HStack {
                        // Left slider
                        if centerSettings.leftSlider != .disabled {
                            verticalSideSlider(
                                type: centerSettings.leftSlider,
                                isLeading: true,
                                buttonBackground: buttonBackground,
                                theme: theme
                            )
                            .padding(.leading, leftPadding)
                        }

                        Spacer()

                        // Right slider
                        if centerSettings.rightSlider != .disabled {
                            verticalSideSlider(
                                type: centerSettings.rightSlider,
                                isLeading: false,
                                buttonBackground: buttonBackground,
                                theme: theme
                            )
                            .padding(.trailing, rightPadding)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: sliderAreaHeight)
                    // Use same offset as center controls for proper vertical alignment
                    .offset(y: centerYOffset - effectiveSafeAreaOffset)
                }

                // Bottom bar - at screen bottom in fullscreen, at video area bottom when panel visible
                // Rendered after side sliders so seek preview appears above them
                VStack {
                    Spacer()
                    bottomBar
                        // Only apply bottomExtraPadding when floating panel is visible (to stay above panel)
                        // When panel is pinned (side panel), bottom bar stays at screen bottom
                        .padding(.bottom, bottomPadding + (isPanelVisible && !isPanelPinned ? bottomExtraPadding : 0))
                        .padding(.leading, leftPadding)
                        .padding(.trailing, rightPadding)
                        .overlay {
                            if showPlayerAreaDebug {
                                Rectangle().stroke(Color.blue, lineWidth: 1)
                            }
                        }
                }

                // DEBUG: Show internal padding values when setting enabled
                // Position at bottom-left to avoid overlap with yellow layout debug
                if showPlayerAreaDebug {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Controls (cyan):")
                            .fontWeight(.bold)
                        Text(verbatim: "winSA T:\(Int(safeArea.top)) B:\(Int(safeArea.bottom)) L:\(Int(safeArea.left)) R:\(Int(safeArea.right))")
                        Text(verbatim: "topPad: \(Int(topPadding)) btmPad: \(Int(bottomPadding)) wide: \(isWideScreenLayout ? "Y" : "N")")
                        Text(verbatim: "geom W:\(Int(geometry.size.width)) H:\(Int(geometry.size.height))")
                        Text(verbatim: "vidTop: \(Int(effectiveVideoTop)) vidH: \(Int(effectiveVideoHeight))")
                        Text(verbatim: "centerOff: \(Int(centerYOffset)) btmExtra: \(Int(bottomExtraPadding))")
                        Text(verbatim: "vis: \(isPanelVisible ? "Y" : "N") fitH: \(Int(videoFitHeight ?? -1)) effVH: \(Int(effectiveVideoHeight))")
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .padding(4)
                    .background(.black.opacity(0.8))
                    .position(x: 120, y: geometry.size.height - 120)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ControlsSectionRenderer(
            section: activeLayout.topSection,
            actions: controlsActions,
            globalSettings: activeLayout.globalSettings,
            controlsVisible: shouldShowControls
        )
    }

    // MARK: - Center Controls

    private func centerControls(compact: Bool, scale: CGFloat = 1.0) -> some View {
        let settings = activeLayout.centerSettings
        let buttonBackground = activeLayout.globalSettings.buttonBackground
        let theme = activeLayout.globalSettings.theme
        let hasBackground = buttonBackground.glassStyle != nil

        // Base sizes - scale down in compact mode to prevent overlapping with top/bottom bars
        let baseSpacing: CGFloat
        let baseSeekButtonSize: CGFloat
        let basePlayButtonSize: CGFloat
        let baseSeekFontSize: CGFloat
        let basePlayFontSize: CGFloat

        if compact {
            baseSpacing = 16
            baseSeekButtonSize = 36
            basePlayButtonSize = 48
            baseSeekFontSize = 20
            basePlayFontSize = 32
        } else {
            // Normal sizes - slightly larger when backgrounds are enabled
            baseSpacing = hasBackground ? 24 : 16
            baseSeekButtonSize = hasBackground ? 64 : 56
            basePlayButtonSize = hasBackground ? 82 : 72
            baseSeekFontSize = 36
            basePlayFontSize = 56
        }

        // Apply horizontal scale factor
        let spacing = baseSpacing * scale
        let seekButtonSize = baseSeekButtonSize * scale
        let playButtonSize = basePlayButtonSize * scale
        let seekFontSize = baseSeekFontSize * scale
        let playFontSize = basePlayFontSize * scale

        return HStack(spacing: spacing) {
            // Skip backward - conditionally shown based on layout settings
            if settings.showSeekBackward {
                Button {
                    seekBackwardTrigger.toggle()
                    Task { await onSeekBackward(TimeInterval(settings.seekBackwardSeconds)) }
                    resetHideTimer()
                } label: {
                    centerButtonContent(
                        systemImage: settings.seekBackwardSystemImage,
                        fontSize: seekFontSize,
                        frameSize: seekButtonSize,
                        buttonBackground: buttonBackground,
                        theme: theme
                    )
                }
                .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekBackwardTrigger)
                .disabled(isTransportDisabled || playerState.isControlsLocked)
                .opacity(playerState.isControlsLocked ? 0.5 : 1.0)
            }

            // Play/Pause - conditionally shown based on layout settings
            if settings.showPlayPause {
                if !isTransportDisabled && !playerState.isControlsLocked {
                    Button {
                        let wasPaused = playerState.playbackState == .paused
                        onPlayPause()
                        // Keep controls visible; start hide timer when resuming playback
                        showControls = true
                        if wasPaused {
                            resetHideTimer()
                        }
                    } label: {
                        centerButtonContent(
                            systemImage: playPauseIcon,
                            fontSize: playFontSize,
                            frameSize: playButtonSize,
                            buttonBackground: buttonBackground,
                            theme: theme
                        )
                    }
                    .accessibilityIdentifier("player.playPauseButton")
                    .accessibilityLabel("player.playPauseButton")
                } else if playerState.isControlsLocked {
                    // Show dimmed play/pause when locked
                    centerButtonContent(
                        systemImage: playPauseIcon,
                        fontSize: playFontSize,
                        frameSize: playButtonSize,
                        buttonBackground: buttonBackground,
                        theme: theme
                    )
                    .opacity(0.5)
                } else {
                    // Invisible spacer maintains layout stability when transport disabled
                    Color.clear
                        .frame(width: playButtonSize, height: playButtonSize)
                        .allowsHitTesting(false)
                }
            }

            // Skip forward - conditionally shown based on layout settings
            if settings.showSeekForward {
                Button {
                    seekForwardTrigger.toggle()
                    Task { await onSeekForward(TimeInterval(settings.seekForwardSeconds)) }
                    resetHideTimer()
                } label: {
                    centerButtonContent(
                        systemImage: settings.seekForwardSystemImage,
                        fontSize: seekFontSize,
                        frameSize: seekButtonSize,
                        buttonBackground: buttonBackground,
                        theme: theme
                    )
                }
                .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekForwardTrigger)
                .disabled(isTransportDisabled || playerState.isControlsLocked)
                .opacity(playerState.isControlsLocked ? 0.5 : 1.0)
            }
        }
    }

    /// Calculates the required width for center controls based on current settings.
    private func centerControlsRequiredWidth(compact: Bool, hasBackground: Bool, settings: CenterSectionSettings) -> CGFloat {
        let spacing: CGFloat = compact ? 16 : (hasBackground ? 24 : 16)
        let seekSize: CGFloat = compact ? 36 : (hasBackground ? 64 : 56)
        let playSize: CGFloat = compact ? 48 : (hasBackground ? 82 : 72)

        var width: CGFloat = 0
        var buttonCount = 0
        if settings.showSeekBackward { width += seekSize; buttonCount += 1 }
        if settings.showPlayPause { width += playSize; buttonCount += 1 }
        if settings.showSeekForward { width += seekSize; buttonCount += 1 }
        if buttonCount > 1 { width += CGFloat(buttonCount - 1) * spacing }
        return width
    }

    /// Creates content for center control buttons with optional glass background.
    @ViewBuilder
    private func centerButtonContent(
        systemImage: String,
        fontSize: CGFloat,
        frameSize: CGFloat,
        buttonBackground: ButtonBackgroundStyle,
        theme: ControlsTheme
    ) -> some View {
        if let glassStyle = buttonBackground.glassStyle {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                .font(.system(size: fontSize))
                .foregroundStyle(.white)
                .frame(width: frameSize, height: frameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial, colorScheme: theme.colorScheme)
                .contentShape(Circle())
        } else {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                .font(.system(size: fontSize))
                .foregroundStyle(.white)
                .frame(width: frameSize, height: frameSize)
                .contentShape(Rectangle())
        }
    }

    /// Whether transport controls should be disabled (during loading/buffering or buffer not ready)
    private var isTransportDisabled: Bool {
        playerState.playbackState == .loading ||
        playerState.playbackState == .buffering ||
        !playerState.isFirstFrameReady ||
        !playerState.isBufferReady
    }

    private var playPauseIcon: String {
        switch playerState.playbackState {
        case .playing:
            return "pause.fill"
        default:
            return "play.fill"
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 4) {
            // Progress bar (stays hardcoded - not customizable)
            progressBar

            // Dynamic button row from layout configuration
            ControlsSectionRenderer(
                section: activeLayout.bottomSection,
                actions: controlsActions,
                globalSettings: activeLayout.globalSettings,
                controlsVisible: shouldShowControls
            )
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if playerState.isLive {
                    // For live streams, show simple red indicator (no scrubbing)
                    Rectangle()
                        .fill(.red.opacity(0.6))
                        .frame(height: 4)
                } else {
                    // Regular VOD progress bar with chapter segments
                    SegmentedProgressBar(
                        chapters: activeLayout.progressBarSettings.showChapters ? playerState.chapters : [],
                        duration: playerState.duration,
                        currentTime: (isDragging || isPendingSeek) ? dragProgress * playerState.duration : playerState.currentTime,
                        bufferedTime: playerState.bufferedTime,
                        height: 4,
                        gapWidth: 2,
                        playedColor: activeLayout.progressBarSettings.playedColor.color,
                        bufferedColor: .white.opacity(0.5),
                        backgroundColor: .white.opacity(0.3),
                        sponsorSegments: playerState.sponsorSegments,
                        sponsorBlockSettings: activeLayout.progressBarSettings.sponsorBlockSettings
                    )

                    // Scrubber handle - fixed 20x20 frame to prevent layout shift
                    // Hidden when controls are locked to show only the progress bar
                    Circle()
                        .fill(activeLayout.progressBarSettings.playedColor.color)
                        .frame(width: 20, height: 20)
                        .scaleEffect(isDragging ? 1.0 : 0.75)
                        .offset(x: geometry.size.width * displayProgress - 10, y: 8)
                        .animation(.easeInOut(duration: 0.1), value: isDragging)
                        .opacity(playerState.isControlsLocked ? 0 : 1)
                }
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            // Only allow interaction for non-live streams and when controls are not locked
            .allowsHitTesting(!playerState.isLive && !playerState.isControlsLocked)
            .opacity(playerState.isControlsLocked ? 0.5 : 1.0)
            // Seek preview as overlay - doesn't affect layout
            .overlay {
                if !playerState.isLive, let storyboard = playerState.preferredStoryboard {
                    seekPreviewOverlay(storyboard: storyboard, geometry: geometry)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !playerState.isLive, !playerState.isControlsLocked else { return }
                        isDragging = true
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = progress
                        cancelHideTimer()
                    }
                    .onEnded { value in
                        guard !playerState.isLive, !playerState.isControlsLocked else { return }
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = progress
                        targetSeekProgress = progress
                        isDragging = false
                        isPendingSeek = true
                        let seekTime = progress * playerState.duration
                        Task { await onSeek(seekTime) }
                        resetHideTimer()
                    }
            )
            .accessibilityIdentifier("player.progressBar")
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            appEnvironment?.navigationCoordinator.progressBarFrame = geo.frame(in: .global)
                        }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            appEnvironment?.navigationCoordinator.progressBarFrame = newFrame
                        }
                }
            }
            .onChange(of: playerState.progress) { _, newProgress in
                // Clear isPendingSeek when playerState.progress converges to target (within 2%)
                if isPendingSeek && abs(newProgress - targetSeekProgress) < 0.02 {
                    isPendingSeek = false
                }
            }
        }
        .frame(height: 20)
    }

    @ViewBuilder
    private func seekPreviewOverlay(storyboard: Storyboard, geometry: GeometryProxy) -> some View {
        if isDragging {
            let seekTime = dragProgress * playerState.duration
            // Use fixed display dimensions (160x90) for positioning, not storyboard resolution
            let previewWidth: CGFloat = 160 + 16 // thumbnail width + padding
            let previewHeight: CGFloat = 90
            let halfWidth = previewWidth / 2
            let xPosition = max(halfWidth, min(geometry.size.width - halfWidth, geometry.size.width * dragProgress))
            let yPosition = -previewHeight / 2 - 12

            SeekPreviewView(
                storyboard: storyboard,
                seekTime: seekTime,
                storyboardService: StoryboardService.shared,
                buttonBackground: activeLayout.globalSettings.buttonBackground,
                theme: activeLayout.globalSettings.theme,
                chapters: playerState.chapters
            )
            .position(x: xPosition, y: yPosition)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.easeInOut(duration: 0.15), value: isDragging)
        }
    }

    private var displayProgress: Double {
        (isDragging || isPendingSeek) ? dragProgress : playerState.progress
    }

    private var bufferedProgress: Double {
        guard playerState.duration > 0 else { return 0 }
        return playerState.bufferedTime / playerState.duration
    }

    // MARK: - Timer Management

    private func toggleControlsVisibility() {
        showControls = !shouldShowControls
        if shouldShowControls {
            startHideTimer()
        }
    }

    private func startHideTimer() {
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                if playerState.playbackState == .playing {
                    showControls = false
                }
            }
        }
    }

    private func resetHideTimer() {
        startHideTimer()
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Gesture Handling

    /// Whether gestures are effectively enabled (master toggle + controls hidden).
    private var gesturesEffectivelyEnabled: Bool {
        let settings = activeLayout.effectiveGesturesSettings
        return settings.hasActiveGestures
    }

    /// Whether gestures should currently respond (controls hidden, not in failed/ended state).
    private var gesturesActive: Bool {
        // Disable gestures when controls are locked
        if playerState.isControlsLocked {
            return false
        }
        return gesturesEffectivelyEnabled &&
            !shouldShowControls &&
            playerState.playbackState != .ended &&
            !playerState.isFailed
    }

    @ViewBuilder
    private func gestureOverlayLayer(geometry: GeometryProxy) -> some View {
        let settings = activeLayout.effectiveGesturesSettings

        // Only render gesture overlay during normal playback
        // When video ends or fails, don't intercept taps - let ended/failed overlays handle them
        if gesturesEffectivelyEnabled && playerState.playbackState != .ended && !playerState.isFailed {
            PlayerGestureOverlay(
                settings: settings,
                isActive: gesturesActive,
                isSeekable: !playerState.isLive,
                onTapAction: { action, position in
                    handleTapGestureAction(action, position: position)
                },
                onSingleTap: {
                    toggleControlsVisibility()
                },
                onSeekGestureStarted: {
                    handleSeekGestureStarted(screenWidth: geometry.size.width)
                },
                onSeekGestureChanged: { horizontalDelta in
                    handleSeekGestureChanged(horizontalDelta: horizontalDelta)
                },
                onSeekGestureEnded: { horizontalDelta in
                    handleSeekGestureEnded(horizontalDelta: horizontalDelta)
                },
                isPinchGestureActive: { [weak appEnvironment] in
                    appEnvironment?.navigationCoordinator.isPinchGestureActive ?? false
                },
                isPanelDragging: { [weak appEnvironment] in
                    appEnvironment?.navigationCoordinator.isPanelDragging ?? false
                }
            )
        }
    }

    @ViewBuilder
    private func gestureFeedbackLayer(geometry: GeometryProxy) -> some View {
        ZStack {
            // Tap feedback
            if let feedback = currentTapFeedback {
                TapGestureFeedbackView(
                    action: feedback.action,
                    accumulatedSeconds: feedback.accumulated,
                    onComplete: {
                        currentTapFeedback = nil
                        executePendingSeek()
                    }
                )
                // Stable identity based on action type + position (not accumulated value)
                // This prevents view recreation when accumulated seconds changes
                .id("\(feedback.action.actionType.rawValue)-\(feedback.position.rawValue)")
            }

            // Seek gesture preview (top-aligned)
            VStack {
                GestureSeekPreviewView(
                    storyboard: playerState.preferredStoryboard,
                    currentTime: seekGestureStartTime,
                    seekTime: seekGesturePreviewTime,
                    duration: playerState.duration,
                    storyboardService: StoryboardService.shared,
                    buttonBackground: activeLayout.globalSettings.buttonBackground,
                    theme: activeLayout.globalSettings.theme,
                    chapters: playerState.chapters,
                    isActive: isSeekGestureActive
                )
                .padding(.top, 16)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.top)
        }
        // Allow taps to pass through feedback visuals to gesture recognizer below
        .allowsHitTesting(false)
    }

    private func handleTapGestureAction(_ action: TapGestureAction, position: TapZonePosition) {
        Task {
            // Update player state for clamping calculations
            await gestureActionHandler.updatePlayerState(
                currentTime: playerState.currentTime,
                duration: playerState.duration
            )

            // Check if switching seek direction or performing non-seek action - cancel pending seek
            switch action {
            case .seekForward:
                // Switching from backward to forward - cancel (option B)
                if pendingSeek?.isForward == false {
                    pendingSeek = nil
                    currentTapFeedback = nil
                    await gestureActionHandler.cancelAccumulation()
                }
            case .seekBackward:
                // Switching from forward to backward - cancel (option B)
                if pendingSeek?.isForward == true {
                    pendingSeek = nil
                    currentTapFeedback = nil
                    await gestureActionHandler.cancelAccumulation()
                }
            default:
                // Non-seek action cancels any pending seek
                if pendingSeek != nil {
                    pendingSeek = nil
                    currentTapFeedback = nil
                    await gestureActionHandler.cancelAccumulation()
                }
            }

            let result = await gestureActionHandler.handleTapAction(action, position: position)

            // Show feedback
            await MainActor.run {
                currentTapFeedback = (action, position, result.accumulatedSeconds)
            }

            // Handle the action
            switch action {
            case .togglePlayPause:
                // Execute immediately
                onPlayPause()

            case .seekForward(let seconds):
                // Defer execution - update pending seek
                let seekSeconds = result.accumulatedSeconds ?? seconds
                await MainActor.run {
                    pendingSeek = (isForward: true, seconds: seekSeconds)
                }

            case .seekBackward(let seconds):
                // Defer execution - update pending seek
                let seekSeconds = result.accumulatedSeconds ?? seconds
                await MainActor.run {
                    pendingSeek = (isForward: false, seconds: seekSeconds)
                }

            case .toggleFullscreen:
                // Execute immediately
                onToggleFullscreen?()

            case .togglePiP:
                // Execute immediately
                onTogglePiP?()

            case .playNext:
                // Execute immediately
                await onPlayNext?()

            case .playPrevious:
                // Not implemented yet - would need onPlayPrevious callback
                break

            case .cyclePlaybackSpeed:
                // Execute immediately
                let currentSpeed = playerState.rate.rawValue
                let nextSpeed = await gestureActionHandler.nextPlaybackSpeed(currentSpeed: currentSpeed)
                if let newRate = PlaybackRate(rawValue: nextSpeed) {
                    onRateChanged?(newRate)
                }

            case .toggleMute:
                // Execute immediately
                onMuteToggled?()
            }
        }
    }

    /// Executes the pending seek action when feedback completes.
    private func executePendingSeek() {
        guard let seek = pendingSeek else { return }
        pendingSeek = nil

        // Don't seek if accumulated time is 0 (already at boundary)
        guard seek.seconds > 0 else { return }

        Task {
            if seek.isForward {
                await onSeekForward(TimeInterval(seek.seconds))
            } else {
                await onSeekBackward(TimeInterval(seek.seconds))
            }

            // Reset accumulation in handler
            await gestureActionHandler.cancelAccumulation()
        }
    }

    // MARK: - Seek Gesture Handlers

    /// Called when horizontal seek gesture is recognized (after activation threshold).
    private func handleSeekGestureStarted(screenWidth: CGFloat) {
        // Capture initial state
        seekGestureStartTime = playerState.currentTime
        seekGesturePreviewTime = playerState.currentTime
        self.screenWidth = screenWidth
        seekGestureBoundaryHapticTriggered = false
        isSeekGestureActive = true

        // Trigger activation haptic
        appEnvironment?.settingsManager.triggerHapticFeedback(for: .seekGestureActivation)
    }

    /// Called during seek gesture with cumulative horizontal delta.
    private func handleSeekGestureChanged(horizontalDelta: CGFloat) {
        guard isSeekGestureActive, screenWidth > 0 else { return }

        let settings = activeLayout.effectiveGesturesSettings.seekGesture

        // Calculate raw delta for continuous preview (even if below minimum threshold)
        let rawDelta = Double(horizontalDelta / screenWidth) * settings.sensitivity.baseSecondsPerScreenWidth *
            SeekGestureCalculator.calculateDurationMultiplier(videoDuration: playerState.duration)

        // Clamp to boundaries
        let clampResult = SeekGestureCalculator.clampSeekTime(
            currentTime: seekGestureStartTime,
            seekDelta: rawDelta,
            duration: playerState.duration
        )

        // Update preview time
        seekGesturePreviewTime = clampResult.seekTime

        // Trigger boundary haptic if needed (only once per boundary hit)
        if clampResult.hitBoundary && !seekGestureBoundaryHapticTriggered {
            appEnvironment?.settingsManager.triggerHapticFeedback(for: .seekGestureBoundary)
            seekGestureBoundaryHapticTriggered = true
        } else if !clampResult.hitBoundary {
            // Reset if moved away from boundary
            seekGestureBoundaryHapticTriggered = false
        }
    }

    /// Called when seek gesture ends with final horizontal delta.
    private func handleSeekGestureEnded(horizontalDelta: CGFloat) {
        guard isSeekGestureActive else { return }

        let settings = activeLayout.effectiveGesturesSettings.seekGesture

        // Calculate final seek delta
        let seekDelta = SeekGestureCalculator.calculateSeekDelta(
            dragDistance: horizontalDelta,
            screenWidth: screenWidth,
            videoDuration: playerState.duration,
            sensitivity: settings.sensitivity
        )

        // Reset state
        isSeekGestureActive = false

        // Only seek if delta meets minimum threshold
        guard let delta = seekDelta else { return }

        // Clamp final seek time
        let clampResult = SeekGestureCalculator.clampSeekTime(
            currentTime: seekGestureStartTime,
            seekDelta: delta,
            duration: playerState.duration
        )

        // Execute the seek
        Task {
            await onSeek(clampResult.seekTime)
        }
    }

    // MARK: - Vertical Side Sliders

    /// Renders a vertical slider on the left or right edge of the player.
    @ViewBuilder
    private func verticalSideSlider(
        type: SideSliderType,
        isLeading: Bool,
        buttonBackground: ButtonBackgroundStyle,
        theme: ControlsTheme
    ) -> some View {
        if type != .disabled {
            VStack(spacing: 4) {
                // Tappable icon at top with expanded tap area
                Button {
                    handleSliderIconTap(type: type)
                } label: {
                    sliderIcon(type: type)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(type == .volume && playerState.isMuted ? .red : .white)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Vertical slider
                verticalSliderControl(type: type)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
            .padding(.horizontal, 4)
            .frame(width: 36)
            .modifier(SideSliderBackgroundModifier(buttonBackground: buttonBackground, theme: theme))
            .opacity(playerState.isControlsLocked ? 0.5 : 1.0)
            .allowsHitTesting(!playerState.isControlsLocked)
        }
    }

    /// Returns the appropriate icon for the slider using variable value SF Symbols.
    @ViewBuilder
    private func sliderIcon(type: SideSliderType) -> some View {
        switch type {
        case .volume:
            if playerState.isMuted {
                Image(systemName: "speaker.slash.fill")
            } else {
                Image(systemName: "speaker.wave.3.fill", variableValue: Double(playerState.volume))
            }
        case .brightness:
            Image(systemName: "sun.max.fill", variableValue: currentBrightness)
        case .disabled:
            EmptyView()
        }
    }

    /// Handles tap on the slider icon.
    private func handleSliderIconTap(type: SideSliderType) {
        switch type {
        case .volume:
            // Toggle mute
            onMuteToggled?()
            resetHideTimer()

        case .brightness:
            // Cycle to next brightness preset
            cycleBrightnessPreset()
            resetHideTimer()

        case .disabled:
            break
        }
    }

    /// Cycles brightness to the next preset value (0, 25, 50, 75, 100%).
    /// Always goes to the next higher preset from current position, wrapping from 100 to 0.
    private func cycleBrightnessPreset() {
        let presets: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let current = UIScreen.main.brightness

        // Find next higher preset (with small tolerance for floating point)
        let newValue: Double
        if let next = presets.first(where: { $0 > current + 0.01 }) {
            newValue = next
        } else {
            // At or above 100%, wrap to 0
            newValue = 0.0
        }

        UIScreen.main.brightness = newValue
        currentBrightness = newValue
    }

    /// Creates the appropriate vertical slider control based on type.
    @ViewBuilder
    private func verticalSliderControl(type: SideSliderType) -> some View {
        switch type {
        case .volume:
            VerticalSlider(
                value: Binding(
                    get: { Double(playerState.volume) },
                    set: { newValue in
                        // Auto-unmute when dragging volume slider
                        if playerState.isMuted {
                            onMuteToggled?()
                        }
                        playerState.volume = Float(newValue)
                        onVolumeChanged?(Float(newValue))
                    }
                ),
                onEditingChanged: { editing in
                    // Disable sheet dismiss gesture while adjusting slider
                    appEnvironment?.navigationCoordinator.isAdjustingPlayerSliders = editing
                    if editing {
                        cancelHideTimer()
                    } else {
                        resetHideTimer()
                    }
                }
            )
        case .brightness:
            VerticalSlider(
                value: Binding(
                    get: { currentBrightness },
                    set: { newValue in
                        UIScreen.main.brightness = newValue
                        currentBrightness = newValue
                    }
                ),
                onEditingChanged: { editing in
                    // Disable sheet dismiss gesture while adjusting slider
                    appEnvironment?.navigationCoordinator.isAdjustingPlayerSliders = editing
                    if editing {
                        cancelHideTimer()
                    } else {
                        resetHideTimer()
                    }
                }
            )
        case .disabled:
            EmptyView()
        }
    }
}

// MARK: - Vertical Slider Component

/// A vertical slider control for volume/brightness adjustment.
private struct VerticalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var onEditingChanged: ((Bool) -> Void)?

    @State private var isDragging = false
    /// Local value tracked during drag for immediate visual feedback
    @State private var dragValue: Double?

    /// The display value - uses local drag value during drag, otherwise the binding
    private var displayValue: Double {
        dragValue ?? value
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track background
                Capsule()
                    .fill(.white.opacity(0.3))

                // Fill
                Capsule()
                    .fill(.white)
                    .frame(height: geometry.size.height * normalizedValue)
            }
            .frame(width: 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            dragValue = value
                            onEditingChanged?(true)
                        }
                        // Invert Y since 0 is at top
                        let newValue = 1.0 - (gesture.location.y / geometry.size.height)
                        let clampedValue = min(max(newValue, range.lowerBound), range.upperBound)
                        dragValue = clampedValue
                        value = clampedValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragValue = nil
                        onEditingChanged?(false)
                    }
            )
        }
        .frame(width: 32)
        .frame(minHeight: 40, maxHeight: 180)
    }

    private var normalizedValue: CGFloat {
        let rangeSize = range.upperBound - range.lowerBound
        guard rangeSize > 0 else { return 0 }
        return (displayValue - range.lowerBound) / rangeSize
    }
}

// MARK: - Corner Adaptation Offset (iPadOS 26+ Stage Manager)

extension View {
    /// Applies corner adaptation offset for iPadOS 26+ Stage Manager window controls.
    /// This prevents the video info bar from colliding with traffic lights when the window is resized.
    @ViewBuilder
    func applyCornerAdaptationOffset() -> some View {
        if #available(iOS 26, *) {
            self.containerCornerOffset(.leading, sizeToFit: true)
        } else {
            self
        }
    }
}

// MARK: - Side Slider Background Modifier

/// Applies glass background to side sliders when enabled.
private struct SideSliderBackgroundModifier: ViewModifier {
    let buttonBackground: ButtonBackgroundStyle
    let theme: ControlsTheme

    func body(content: Content) -> some View {
        if let glassStyle = buttonBackground.glassStyle {
            content
                .glassBackground(
                    glassStyle,
                    in: .capsule,
                    fallback: .ultraThinMaterial,
                    colorScheme: theme.colorScheme
                )
        } else {
            // No background when "None" is selected
            content
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black

        PlayerControlsView(
            playerState: PlayerState(),
            onPlayPause: {},
            onSeek: { _ in },
            onSeekForward: { _ in },
            onSeekBackward: { _ in }
        )
    }
    .aspectRatio(16/9, contentMode: .fit)
}

#Preview("Slider") {
    @Previewable @State var value: Double = 50
    
    ZStack {
        Color.black
        VerticalSlider(value: $value, range: 0...100)
            .border(Color.red, width: 3)
    }
}

#endif
