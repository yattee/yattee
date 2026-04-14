//
//  TVPlayerView.swift
//  Yattee
//
//  Main tvOS player container with custom controls and Apple TV remote support.
//

#if os(tvOS)
import SwiftUI

/// Focus targets for tvOS player controls navigation.
enum TVPlayerFocusTarget: Hashable {
    case background  // For capturing events when controls hidden
    case progressBar
    case settingsButton
    case infoButton
    case commentsButton
    case debugButton
    case playNext
    case closeButton
}

/// Main tvOS fullscreen player view.
struct TVPlayerView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Whether controls overlay is visible.
    @State private var controlsVisible = true

    /// Timer for auto-hiding controls.
    @State private var controlsHideTimer: Timer?

    /// Whether the details panel is shown.
    @State private var isDetailsPanelVisible = false

    /// Initial tab for the details panel when opened.
    @State private var detailsPanelInitialTab: TVDetailsTab = .info

    /// Whether user is scrubbing the progress bar.
    @State private var isScrubbing = false

    /// Whether the quality sheet is shown.
    @State private var showingQualitySheet = false

    /// Whether the debug overlay is shown.
    @State private var isDebugOverlayVisible = false

    /// Debug statistics from MPV.
    @State private var debugStats: MPVDebugStats = .init()

    /// Timer for updating debug stats.
    @State private var debugUpdateTimer: Timer?

    /// Current focus target for D-pad navigation.
    @FocusState private var focusedControl: TVPlayerFocusTarget?

    /// Whether the autoplay countdown is visible.
    @State private var showAutoplayCountdown = false

    /// Current countdown value (5, 4, 3, 2, 1).
    @State private var autoplayCountdown = 5

    /// Timer for the countdown.
    @State private var autoplayTimer: Timer?

    /// Handler for seek accumulation when using remote arrows with controls hidden.
    @State private var gestureActionHandler = PlayerGestureActionHandler()

    /// Current tap-seek feedback to display.
    @State private var currentTapFeedback: (action: TapGestureAction, position: TapZonePosition, accumulated: Int?)?

    /// Pending seek to execute when feedback completes.
    @State private var pendingSeek: (isForward: Bool, seconds: Int)?

    // MARK: - Computed Properties

    private var playerService: PlayerService? {
        appEnvironment?.playerService
    }

    private var playerState: PlayerState? {
        playerService?.state
    }

    // MARK: - Body

    var body: some View {
        mpvPlayerContent
            .ignoresSafeArea()
            .playerToastOverlay()
            // Quality / Settings selector (fullscreen cover gives tvOS enough room)
            .fullScreenCover(isPresented: $showingQualitySheet) {
                qualitySheetContent
            }
    }

    // MARK: - Quality Sheet Content

    @ViewBuilder
    private var qualitySheetContent: some View {
        if let playerService {
            let dashEnabled = appEnvironment?.settingsManager.dashEnabled ?? false
            let supportedFormats = playerService.currentBackendType.supportedFormats

            ZStack {
                // Dimmed backdrop over the video
                Color.black.opacity(0.7)
                    .ignoresSafeArea()

                QualitySelectorView(
                    streams: playerService.availableStreams.filter { stream in
                        let format = StreamFormat.detect(from: stream)
                        if format == .dash && !dashEnabled {
                            return false
                        }
                        return supportedFormats.contains(format)
                    },
                    captions: playerService.availableCaptions,
                    currentStream: playerState?.currentStream,
                    currentAudioStream: playerState?.currentAudioStream,
                    currentCaption: playerService.currentCaption,
                    isLoading: playerState?.playbackState == .loading,
                    currentDownload: playerService.currentDownload,
                    isLoadingOnlineStreams: playerService.isLoadingOnlineStreams,
                    localCaptionURL: playerService.currentDownload.flatMap { download in
                        guard let path = download.localCaptionPath else { return nil }
                        return appEnvironment?.downloadManager.downloadsDirectory().appendingPathComponent(path)
                    },
                    currentRate: playerState?.rate ?? .x1,
                    onStreamSelected: { stream, audioStream in
                        switchToStream(stream, audioStream: audioStream)
                    },
                    onCaptionSelected: { caption in
                        playerService.loadCaption(caption)
                    },
                    onLoadOnlineStreams: {
                        Task {
                            await playerService.loadOnlineStreams()
                        }
                    },
                    onSwitchToOnlineStream: { stream, audioStream in
                        Task {
                            await playerService.switchToOnlineStream(stream, audioStream: audioStream)
                        }
                    },
                    onRateChanged: { rate in
                        playerState?.rate = rate
                        playerService.currentBackend?.rate = Float(rate.rawValue)
                    }
                )
                .frame(maxWidth: 900, maxHeight: 700)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal, 200)
                .padding(.vertical, 80)
            }
        }
    }

    // MARK: - MPV Content

    /// Custom MPV player view with custom controls.
    @ViewBuilder
    private var mpvPlayerContent: some View {
        ZStack {
            // Background - always focusable to capture remote events
            backgroundLayer

            // Video layer
            videoLayer

            // Controls overlay
            if controlsVisible && !isDetailsPanelVisible && !isDebugOverlayVisible {
                TVPlayerControlsView(
                    playerState: playerState,
                    playerService: playerService,
                    focusedControl: $focusedControl,
                    onShowSettings: { showQualitySheet() },
                    onShowDetails: { showDetailsPanel(tab: .info) },
                    onShowComments: { showDetailsPanel(tab: .comments) },
                    onShowDebug: { showDebugOverlay() },
                    onClose: { closeVideo() },
                    onScrubbingChanged: { scrubbing in
                        isScrubbing = scrubbing
                        if scrubbing {
                            stopControlsTimer()
                        } else {
                            startControlsTimer()
                        }
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }

            // Swipe-up details panel
            if isDetailsPanelVisible {
                TVDetailsPanel(
                    video: playerState?.currentVideo,
                    initialTab: detailsPanelInitialTab,
                    onDismiss: { hideDetailsPanel() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Debug overlay
            if isDebugOverlayVisible {
                MPVDebugOverlay(
                    stats: debugStats,
                    isVisible: $isDebugOverlayVisible,
                    isLandscape: true,
                    onClose: { hideDebugOverlay() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Arrow-key seek feedback (when controls are hidden)
            if let feedback = currentTapFeedback {
                TapGestureFeedbackView(
                    action: feedback.action,
                    accumulatedSeconds: feedback.accumulated,
                    onComplete: {
                        currentTapFeedback = nil
                        executePendingSeek()
                    }
                )
                .id("\(feedback.action.actionType.rawValue)-\(feedback.position.rawValue)")
                .allowsHitTesting(false)
            }

            // Autoplay countdown overlay
            if showAutoplayCountdown, let nextVideo = playerState?.nextQueuedVideo {
                TVAutoplayCountdownView(
                    countdown: autoplayCountdown,
                    nextVideo: nextVideo,
                    onPlayNext: { playNextInQueue() },
                    onCancel: { cancelAutoplay() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onAppear {
            startControlsTimer()
            focusedControl = .progressBar
        }
        .onDisappear {
            stopControlsTimer()
            stopDebugUpdates()
            stopAutoplayCountdown()
        }
        // Remote event handling - these work globally
        .onPlayPauseCommand {
            handlePlayPause()
        }
        .onExitCommand {
            handleMenuButton()
        }
        // Track focus changes to show controls when navigating
        .onChange(of: focusedControl) { oldValue, newValue in
            handleFocusChange(from: oldValue, to: newValue)
        }
        // Start auto-hide timer when playback starts, handle video ended
        .onChange(of: playerState?.playbackState) { _, newState in
            if newState == .playing && controlsVisible && !isScrubbing {
                startControlsTimer()
            } else if newState == .ended {
                handleVideoEnded()
            }
        }
        // Dismiss countdown if video changes during countdown (e.g., from remote control)
        .onChange(of: playerState?.currentVideo?.id) { _, _ in
            if showAutoplayCountdown {
                stopAutoplayCountdown()
                showControls()
            }
        }
    }

    // MARK: - Background Layer

    @ViewBuilder
    private var backgroundLayer: some View {
        if !controlsVisible && !isDetailsPanelVisible && !isDebugOverlayVisible {
            // When controls hidden, use a Button to capture both click and swipe
            Button {
                showControls()
            } label: {
                Color.black
                    .ignoresSafeArea()
            }
            .buttonStyle(TVBackgroundButtonStyle())
            .focused($focusedControl, equals: .background)
            .onMoveCommand { direction in
                handleBackgroundMoveCommand(direction)
            }
        } else {
            // When controls visible, just a plain background
            Color.black
                .ignoresSafeArea()
        }
    }

    // MARK: - Video Layer

    @ViewBuilder
    private var videoLayer: some View {
        if let playerService,
           let backend = playerService.currentBackend as? MPVBackend,
           let playerState {
            MPVRenderViewRepresentable(
                backend: backend,
                playerState: playerState
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        } else {
            // Fallback/loading state - show thumbnail
            if let video = playerState?.currentVideo,
               let thumbnailURL = video.bestThumbnail?.url {
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.black
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Focus Handling

    private func handleFocusChange(from oldValue: TVPlayerFocusTarget?, to newValue: TVPlayerFocusTarget?) {
        // If focus moved to a control, ensure controls are visible
        if let newValue, newValue != .background {
            if !controlsVisible {
                showControls()
            }
            startControlsTimer()
        }
    }

    // MARK: - Controls Timer

    private func startControlsTimer() {
        stopControlsTimer()

        // Don't auto-hide if paused
        guard playerState?.playbackState == .playing else { return }

        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.3)) {
                    controlsVisible = false
                    focusedControl = .background
                }
            }
        }
    }

    private func stopControlsTimer() {
        controlsHideTimer?.invalidate()
        controlsHideTimer = nil
    }

    private func showControls() {
        withAnimation(.easeIn(duration: 0.2)) {
            controlsVisible = true
        }
        if focusedControl == .background || focusedControl == nil {
            focusedControl = .progressBar
        }
        startControlsTimer()
    }

    // MARK: - Details Panel

    private func showDetailsPanel(tab: TVDetailsTab = .info) {
        stopControlsTimer()
        detailsPanelInitialTab = tab
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isDetailsPanelVisible = true
            controlsVisible = false
        }
    }

    // MARK: - Quality Sheet

    private func showQualitySheet() {
        stopControlsTimer()
        showingQualitySheet = true
    }

    private func switchToStream(_ stream: Stream, audioStream: Stream? = nil) {
        guard let video = playerState?.currentVideo else { return }

        let currentTime = playerState?.currentTime

        Task {
            await playerService?.play(video: video, stream: stream, audioStream: audioStream, startTime: currentTime)
        }
    }

    private func hideDetailsPanel() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            isDetailsPanelVisible = false
        }
        showControls()
    }

    // MARK: - Debug Overlay

    private func showDebugOverlay() {
        stopControlsTimer()
        startDebugUpdates()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isDebugOverlayVisible = true
            controlsVisible = false
        }
    }

    private func hideDebugOverlay() {
        stopDebugUpdates()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            isDebugOverlayVisible = false
        }
        showControls()
    }

    private func startDebugUpdates() {
        stopDebugUpdates()
        guard let backend = playerService?.currentBackend as? MPVBackend else { return }

        // Update immediately
        debugStats = backend.getDebugStats()

        // Then update every second
        debugUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                guard let backend = self.playerService?.currentBackend as? MPVBackend else { return }
                self.debugStats = backend.getDebugStats()
            }
        }
    }

    private func stopDebugUpdates() {
        debugUpdateTimer?.invalidate()
        debugUpdateTimer = nil
    }

    // MARK: - Remote Event Handlers

    private func handlePlayPause() {
        // Cancel countdown if visible
        if showAutoplayCountdown {
            stopAutoplayCountdown()
            showControls()
            return
        }

        // Show controls if hidden (but not if debug overlay is visible), then toggle playback
        if !controlsVisible && !isDetailsPanelVisible && !isDebugOverlayVisible {
            showControls()
        }

        playerService?.togglePlayPause()

        // Reset timer when interacting (only if controls are visible)
        if !isDebugOverlayVisible {
            if playerState?.playbackState == .playing {
                startControlsTimer()
            } else {
                stopControlsTimer()
            }
        }
    }

    /// Handles D-pad / arrow presses while controls are hidden.
    /// Left/right trigger an accumulating seek with on-screen feedback; up/down reveal controls.
    private func handleBackgroundMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            triggerRemoteSeek(forward: false)
        case .right:
            triggerRemoteSeek(forward: true)
        case .up, .down:
            showControls()
        @unknown default:
            showControls()
        }
    }

    /// Triggers a seek action from the remote, accumulating across rapid presses.
    private func triggerRemoteSeek(forward: Bool) {
        let seekSeconds = 10
        let action: TapGestureAction = forward
            ? .seekForward(seconds: seekSeconds)
            : .seekBackward(seconds: seekSeconds)
        let position: TapZonePosition = forward ? .right : .left
        let currentTime = playerState?.currentTime ?? 0
        let duration = playerState?.duration ?? 0

        Task {
            await gestureActionHandler.updatePlayerState(
                currentTime: currentTime,
                duration: duration
            )

            // If switching seek direction, cancel any pending seek first.
            if let pending = pendingSeek, pending.isForward != forward {
                await MainActor.run {
                    pendingSeek = nil
                    currentTapFeedback = nil
                }
                await gestureActionHandler.cancelAccumulation()
            }

            let result = await gestureActionHandler.handleTapAction(action, position: position)
            let accumulated = result.accumulatedSeconds ?? seekSeconds

            await MainActor.run {
                currentTapFeedback = (action, position, result.accumulatedSeconds)
                pendingSeek = (isForward: forward, seconds: accumulated)
            }
        }
    }

    /// Commits the pending seek when the feedback overlay finishes its dismiss animation.
    private func executePendingSeek() {
        guard let seek = pendingSeek else { return }
        pendingSeek = nil
        guard seek.seconds > 0 else { return }

        if seek.isForward {
            playerService?.seekForward(by: TimeInterval(seek.seconds))
        } else {
            playerService?.seekBackward(by: TimeInterval(seek.seconds))
        }

        Task {
            await gestureActionHandler.cancelAccumulation()
        }
    }

    private func handleMenuButton() {
        if showAutoplayCountdown {
            // First priority: cancel countdown
            cancelAutoplay()
        } else if isDebugOverlayVisible {
            // Second: hide debug overlay
            hideDebugOverlay()
        } else if isDetailsPanelVisible {
            // Third: hide details panel
            hideDetailsPanel()
        } else if isScrubbing {
            // Fourth: exit scrub mode (handled by progress bar losing focus)
            // Just hide controls
            hideControls()
        } else if controlsVisible {
            // Fifth: hide controls
            hideControls()
        } else {
            // Sixth: dismiss player (controls already hidden)
            dismissPlayer()
        }
    }

    private func hideControls() {
        stopControlsTimer()
        withAnimation(.easeOut(duration: 0.25)) {
            controlsVisible = false
            focusedControl = .background
        }
    }

    private func closeVideo() {
        playerState?.isClosingVideo = true
        appEnvironment?.queueManager.clearQueue()
        playerService?.stop()
        appEnvironment?.navigationCoordinator.isPlayerExpanded = false
        dismiss()
    }

    private func dismissPlayer() {
        // Collapse the player but keep it alive so audio continues in the background
        // and the "Now Playing" sidebar entry can restore the session. Matches the
        // iOS/macOS ExpandedPlayerWindow dismissal path, which also does not stop()
        // on dismiss.
        appEnvironment?.navigationCoordinator.isPlayerExpanded = false
        dismiss()
    }

    // MARK: - Autoplay Countdown

    private func handleVideoEnded() {
        // Hide controls immediately
        stopControlsTimer()
        withAnimation(.easeOut(duration: 0.25)) {
            controlsVisible = false
        }

        // Check if autoplay is enabled and there's a next video
        let autoPlayEnabled = appEnvironment?.settingsManager.queueAutoPlayNext ?? true
        let hasNextVideo = playerState?.hasNext ?? false

        if autoPlayEnabled && hasNextVideo {
            startAutoplayCountdown()
        } else {
            // No next video or autoplay disabled - show controls with replay option
            showControls()
        }
    }

    private func startAutoplayCountdown() {
        stopAutoplayCountdown()

        // Get countdown duration from settings (default: 5 seconds, range: 1-15)
        let countdownDuration = appEnvironment?.settingsManager.queueAutoPlayCountdown ?? 5
        autoplayCountdown = countdownDuration

        withAnimation(.easeIn(duration: 0.3)) {
            showAutoplayCountdown = true
        }

        // Start countdown timer
        autoplayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if self.autoplayCountdown > 1 {
                    self.autoplayCountdown -= 1
                } else {
                    // Countdown finished - play next video
                    self.stopAutoplayCountdown()
                    self.playNextInQueue()
                }
            }
        }
    }

    private func stopAutoplayCountdown() {
        autoplayTimer?.invalidate()
        autoplayTimer = nil

        withAnimation(.easeOut(duration: 0.2)) {
            showAutoplayCountdown = false
        }
    }

    private func playNextInQueue() {
        stopAutoplayCountdown()

        Task {
            await playerService?.playNext()
        }
    }

    private func cancelAutoplay() {
        stopAutoplayCountdown()

        // Show controls so user can replay or manually navigate
        showControls()
    }
}

// MARK: - Background Button Style

/// Invisible button style for the background - no visual feedback, just captures input.
struct TVBackgroundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#endif
