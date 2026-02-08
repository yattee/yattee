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
    case skipBackward
    case playPause
    case skipForward
    case progressBar
    case qualityButton
    case captionsButton
    case debugButton
    case infoButton
    case volumeDown
    case volumeUp
    case playNext
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
            // Quality selector sheet
            .sheet(isPresented: $showingQualitySheet) {
                if let playerService {
                    let dashEnabled = appEnvironment?.settingsManager.dashEnabled ?? false
                    let supportedFormats = playerService.currentBackendType.supportedFormats
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
                    onShowDetails: { showDetailsPanel() },
                    onShowQuality: { showQualitySheet() },
                    onShowDebug: { showDebugOverlay() },
                    onDismiss: { dismissPlayer() },
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
            focusedControl = .playPause
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
            .onMoveCommand { _ in
                // Any direction press shows controls
                showControls()
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
            focusedControl = .playPause
        }
        startControlsTimer()
    }

    // MARK: - Details Panel

    private func showDetailsPanel() {
        stopControlsTimer()
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

    private func dismissPlayer() {
        // Save progress and stop player before dismissing (matches iOS/macOS pattern)
        // This ensures watch history is updated when user exits player with Menu button
        playerService?.stop()
        
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
