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
    case playPrevious
    case playPauseButton
    case playNext
    case closeButton
    case queueButton
    case errorDetails
    case errorRetry
    case errorPlayNext
    case errorClose
}

/// Main tvOS fullscreen player view.
struct TVPlayerView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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

    /// Whether playback was active when the current scrub session began;
    /// used to decide whether to resume on scrub end.
    @State private var wasPlayingBeforeScrub = false

    /// Whether the quality sheet is shown.
    @State private var showingQualitySheet = false

    /// Whether the queue sheet is shown.
    @State private var showingQueueSheet = false

    /// Whether the error details sheet is shown.
    @State private var showingErrorSheet = false

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

    /// Current tap-seek feedback to display.
    @State private var currentTapFeedback: (action: TapGestureAction, position: TapZonePosition, accumulated: Int?)?

    /// Pending seek to execute when feedback completes.
    @State private var pendingSeek: (isForward: Bool, seconds: Int)?

    /// Pending target time for arrow-key seeks while the progress bar is
    /// focused (controls visible). Mirrored onto the scrubber so the handle
    /// moves without any extra overlay.
    @State private var scrubberRemoteSeekTime: TimeInterval?

    /// Most recent accumulated seek amount for the focused-bar flow; applied
    /// on debounced commit.
    @State private var scrubberRemoteSeek: (isForward: Bool, seconds: Int)?

    /// Debounce task that commits the focused-bar arrow-key seek 1s after the
    /// last press.
    @State private var scrubberRemoteSeekTask: Task<Void, Never>?

    /// Bumped to signal `TVPlayerProgressBar` to cancel an in-progress scrub
    /// without performing the seek (used when Menu is pressed during scrub).
    @State private var cancelScrubTrigger: UUID?

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
            .fullScreenCover(isPresented: $showingQueueSheet) {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    QueueManagementSheet()
                }
            }
            .fullScreenCover(isPresented: $showingErrorSheet) {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    ErrorDetailsSheet(errorMessage: playerState?.errorMessage ?? "Unknown error")
                        .frame(maxWidth: 1200, maxHeight: 700)
                        .padding(.horizontal, 200)
                        .padding(.vertical, 80)
                }
            }
    }

    // MARK: - Quality Sheet Content

    @ViewBuilder
    private var qualitySheetContent: some View {
        if let playerService {
            let dashEnabled = appEnvironment?.settingsManager.dashEnabled ?? false
            let supportedFormats = playerService.currentBackendType.supportedFormats

            ZStack {
                // Glass backdrop — matches info/comments panel for visual uniformity
                Rectangle()
                    .fill(.ultraThinMaterial)
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

            // Controls overlay — always in tree, toggled via opacity so the fade-out
            // isn't skipped by tvOS's focus engine forcibly tearing down a focused
            // subview when the conditional flips to false. Focus is redirected to
            // the background Button after each hide so the remote touch area still
            // triggers showControls() instead of hitting a disabled hidden control.
            TVPlayerControlsView(
                playerState: playerState,
                playerService: playerService,
                focusedControl: $focusedControl,
                onShowSettings: { showQualitySheet() },
                onShowQueue: { showQueueSheet() },
                onShowDetails: { showDetailsPanel(tab: .info) },
                onShowComments: { showDetailsPanel(tab: .comments) },
                onShowDebug: { showDebugOverlay() },
                onClose: { closeVideo() },
                onTogglePlayPause: { handlePlayPause() },
                onScrubbingChanged: { scrubbing in
                    isScrubbing = scrubbing
                    if scrubbing {
                        stopControlsTimer()
                        wasPlayingBeforeScrub = playerService?.state.playbackState == .playing
                        if wasPlayingBeforeScrub {
                            playerService?.pause()
                        }
                    } else {
                        startControlsTimer()
                        if wasPlayingBeforeScrub {
                            playerService?.resume()
                        }
                        wasPlayingBeforeScrub = false
                    }
                },
                remoteSeekTime: scrubberRemoteSeekTime,
                onRemoteSeek: { forward in
                    triggerScrubberRemoteSeek(forward: forward)
                },
                cancelScrubTrigger: cancelScrubTrigger
            )
            .opacity(shouldShowControls ? 1 : 0)
            .allowsHitTesting(shouldShowControls)
            .disabled(!shouldShowControls)
            .animation(.easeInOut(duration: 0.25), value: shouldShowControls)

            // Right-side details panel (covers ~50% of screen)
            if isDetailsPanelVisible {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        TVDetailsPanel(
                            video: playerState?.currentVideo,
                            initialTab: detailsPanelInitialTab,
                            onDismiss: { hideDetailsPanel() }
                        )
                        .frame(width: geo.size.width / 2)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Debug overlay
            if isDebugOverlayVisible {
                MPVDebugOverlay(
                    stats: debugStats,
                    isVisible: $isDebugOverlayVisible,
                    isLandscape: true
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

            // Press-and-hold continuous seek (UIPress-based; routes to the
            // same accumulating seek functions as the discrete .onMoveCommand
            // path).
            TVRemoteHoldSeekOverlay(
                isActive: !isDetailsPanelVisible
                    && !isDebugOverlayVisible
                    && !showingQualitySheet
                    && !showingQueueSheet
                    && !isScrubbing
            ) { forward, step in
                if controlsVisible, !isScrubbing {
                    // Controls visible — mirror the discrete focused-bar
                    // path. We do NOT gate on focusedControl == .progressBar
                    // because tvOS focus may briefly drop while the window
                    // recognizer captures the press; the user's intent is
                    // clearly to scrub the visible bar.
                    triggerScrubberRemoteSeek(forward: forward, stepSeconds: step)
                } else {
                    // Controls hidden — accumulating overlay seek.
                    triggerRemoteSeek(forward: forward, stepSeconds: step)
                }
            }
            .allowsHitTesting(false)

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

            // Playback failure overlay
            if playerState?.isFailed == true {
                failedOverlay
                    .transition(.opacity)
            } else if playerState?.retryState.exhausted == true {
                retryExhaustedOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: playerState?.isFailed)
        .animation(.easeInOut(duration: 0.25), value: playerState?.retryState.exhausted)
        .onAppear {
            startControlsTimer()
            focusedControl = .progressBar
        }
        .onDisappear {
            stopControlsTimer()
            stopDebugUpdates()
            stopAutoplayCountdown()
            scrubberRemoteSeekTask?.cancel()
            scrubberRemoteSeekTask = nil
            scrubberRemoteSeek = nil
            scrubberRemoteSeekTime = nil
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
            } else if case .failed = newState {
                handleVideoFailed()
            }
        }
        .onChange(of: playerState?.retryState.exhausted) { _, exhausted in
            if exhausted == true {
                handleVideoFailed()
            }
        }
        // Dismiss countdown if video changes during countdown (e.g., from remote control)
        .onChange(of: playerState?.currentVideo?.id) { _, _ in
            if showAutoplayCountdown {
                stopAutoplayCountdown()
                showControls()
            }
        }
        // When app returns to foreground (e.g. after auto-pause from background),
        // surface the controls so the user can immediately resume or navigate.
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && oldPhase != .active {
                showControls()
            }
        }
    }

    // MARK: - Failure Overlays

    /// Whether either failure overlay is currently visible.
    private var isFailureOverlayVisible: Bool {
        playerState?.isFailed == true || playerState?.retryState.exhausted == true
    }

    @ViewBuilder
    private var failedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.yellow)
                    if let message = playerState?.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: 1000)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 36)
                .glassBackground(.regular, in: .rect(cornerRadius: 28), fallback: .ultraThinMaterial)

                HStack(spacing: 32) {
                    failureButton(
                        title: String(localized: "player.error.button"),
                        systemImage: "info.circle",
                        focus: .errorDetails,
                        action: { showingErrorSheet = true }
                    )

                    failureButton(
                        title: String(localized: "player.error.retry"),
                        systemImage: "arrow.clockwise",
                        focus: .errorRetry,
                        action: { retryPlayback() }
                    )

                    if playerState?.nextQueuedVideo != nil {
                        failureButton(
                            title: String(localized: "player.autoplay.playNext"),
                            systemImage: "forward.fill",
                            focus: .errorPlayNext,
                            action: { playNextInQueue() }
                        )
                    } else {
                        failureButton(
                            title: String(localized: "player.close"),
                            systemImage: "xmark",
                            focus: .errorClose,
                            action: { closeVideo() }
                        )
                    }
                }
                .focusSection()
            }
        }
    }

    @ViewBuilder
    private var retryExhaustedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(String(localized: "player.retry.button"))
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 32) {
                    failureButton(
                        title: String(localized: "player.error.retry"),
                        systemImage: "arrow.clockwise",
                        focus: .errorRetry,
                        action: { retryPlayback() }
                    )

                    failureButton(
                        title: String(localized: "player.close"),
                        systemImage: "xmark",
                        focus: .errorClose,
                        action: { closeVideo() }
                    )
                }
                .focusSection()
            }
        }
    }

    @ViewBuilder
    private func failureButton(
        title: String,
        systemImage: String,
        focus: TVPlayerFocusTarget,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 320, height: 80)
        }
        .buttonStyle(TVFailureButtonStyle())
        .focused($focusedControl, equals: focus)
    }

    // MARK: - Failure Actions

    /// Restart playback of the current video from scratch.
    private func retryPlayback() {
        guard let playerService, let video = playerState?.currentVideo else { return }
        Task {
            await playerService.play(video: video)
        }
    }

    /// Called when playback enters the failed state or retries are exhausted.
    private func handleVideoFailed() {
        stopControlsTimer()
        stopAutoplayCountdown()
        withAnimation(.easeOut(duration: 0.25)) {
            controlsVisible = false
        }
        // Defer focus assignment so the overlay is in the tree before the focus
        // engine evaluates it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            focusedControl = .errorRetry
        }
    }

    // MARK: - Background Layer

    @ViewBuilder
    private var backgroundLayer: some View {
        if !controlsVisible && !isDetailsPanelVisible && !isDebugOverlayVisible && !isFailureOverlayVisible {
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

    // MARK: - Derived State

    /// Whether the primary controls overlay should be visible right now.
    private var shouldShowControls: Bool {
        controlsVisible && !isDetailsPanelVisible && !isDebugOverlayVisible && !isFailureOverlayVisible
    }

    // MARK: - Controls Timer

    private func startControlsTimer() {
        stopControlsTimer()

        // Don't auto-hide if paused
        guard playerState?.playbackState == .playing else { return }

        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.25)) {
                    controlsVisible = false
                }
                // After controlsVisible flips, the backgroundLayer Button is in the
                // tree and focusable — move focus to it so the remote touch area
                // calls showControls() instead of a hidden/disabled control.
                focusedControl = .background
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

    private func showQueueSheet() {
        stopControlsTimer()
        showingQueueSheet = true
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

    /// Triggers a seek action from the remote, accumulating a signed net
    /// offset across rapid presses. A reverse press within the active window
    /// subtracts from the pending offset instead of restarting from the
    /// current playback time (e.g. right, right, left from 30s → +10s → 40s,
    /// not −10s → 20s).
    private func triggerRemoteSeek(forward: Bool, stepSeconds: Int = 10) {
        let currentTime = playerState?.currentTime ?? 0
        let duration = playerState?.duration ?? 0

        // Current signed offset from any in-flight accumulation.
        let currentNet: Int = pendingSeek.map { $0.isForward ? $0.seconds : -$0.seconds } ?? 0
        let step = forward ? stepSeconds : -stepSeconds
        let rawNet = currentNet + step

        // Clamp to the available seekable range in either direction.
        let maxForward = Int(max(0, duration - currentTime))
        let maxBackward = Int(max(0, currentTime))
        let clampedNet = min(max(rawNet, -maxBackward), maxForward)

        let netMagnitude = abs(clampedNet)
        let netIsForward = clampedNet >= 0

        let action: TapGestureAction = netIsForward
            ? .seekForward(seconds: stepSeconds)
            : .seekBackward(seconds: stepSeconds)
        let position: TapZonePosition = netIsForward ? .right : .left

        currentTapFeedback = (action, position, netMagnitude)
        pendingSeek = (isForward: netIsForward, seconds: netMagnitude)
    }

    /// Accumulating arrow-key seek for when the progress bar is focused and
    /// controls are visible. Suppresses the circular feedback overlay — the
    /// visible scrubber shows the pending target instead — and uses the same
    /// signed net-offset accumulation as the hidden-controls flow.
    private func triggerScrubberRemoteSeek(forward: Bool, stepSeconds: Int = 10) {
        let currentTime = playerState?.currentTime ?? 0
        let duration = playerState?.duration ?? 0

        // Keep controls on-screen while the user is arrow-seeking.
        stopControlsTimer()

        // Current signed offset from any in-flight accumulation.
        let currentNet: Int = scrubberRemoteSeek.map { $0.isForward ? $0.seconds : -$0.seconds } ?? 0
        let step = forward ? stepSeconds : -stepSeconds
        let rawNet = currentNet + step

        let maxForward = Int(max(0, duration - currentTime))
        let maxBackward = Int(max(0, currentTime))
        let clampedNet = min(max(rawNet, -maxBackward), maxForward)

        let netMagnitude = abs(clampedNet)
        let netIsForward = clampedNet >= 0

        // When the seek is clamped at the edge of the seekable range,
        // successive ticks would write the same values; skip the @State
        // assignments to avoid spurious SwiftUI invalidations.
        if scrubberRemoteSeek?.isForward != netIsForward
            || scrubberRemoteSeek?.seconds != netMagnitude
        {
            scrubberRemoteSeek = (isForward: netIsForward, seconds: netMagnitude)
        }
        let newSeekTime = currentTime + TimeInterval(clampedNet)
        if scrubberRemoteSeekTime != newSeekTime {
            scrubberRemoteSeekTime = newSeekTime
        }

        scrubberRemoteSeekTask?.cancel()
        scrubberRemoteSeekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            commitScrubberRemoteSeek()
        }
    }

    /// Commits the debounced accumulating arrow-key seek for the focused bar.
    private func commitScrubberRemoteSeek() {
        guard let seek = scrubberRemoteSeek else { return }
        scrubberRemoteSeek = nil
        scrubberRemoteSeekTime = nil
        scrubberRemoteSeekTask = nil

        if seek.seconds > 0 {
            if seek.isForward {
                playerService?.seekForward(by: TimeInterval(seek.seconds))
            } else {
                playerService?.seekBackward(by: TimeInterval(seek.seconds))
            }
        }

        // Resume the auto-hide timer now that the user is done seeking.
        startControlsTimer()
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
    }

    private func handleMenuButton() {
        if showingErrorSheet {
            // Top priority: close the error details sheet
            showingErrorSheet = false
        } else if isFailureOverlayVisible {
            // While the failure overlay is up, Menu closes the video so the
            // user isn't stranded with no working remote affordance.
            closeVideo()
        } else if showAutoplayCountdown {
            // First priority: cancel countdown
            cancelAutoplay()
        } else if isDebugOverlayVisible {
            // Second: hide debug overlay
            hideDebugOverlay()
        } else if isDetailsPanelVisible {
            // Third: hide details panel
            hideDetailsPanel()
        } else if isScrubbing {
            // Fourth: cancel scrub without seeking, then hide controls. The
            // subsequent focus-loss path sees cleared scrub state and no-ops.
            cancelScrubTrigger = UUID()
            hideControls()
        } else if controlsVisible {
            // Fifth: hide controls
            hideControls()
        } else if appEnvironment?.settingsManager.tvOSMenuButtonClosesVideo == true {
            // Sixth (Menu-closes mode): fully close the video like the xmark button
            closeVideo()
        } else {
            // Sixth: dismiss player (controls already hidden)
            dismissPlayer()
        }
    }

    private func hideControls() {
        stopControlsTimer()
        withAnimation(.easeOut(duration: 0.25)) {
            controlsVisible = false
        }
        // Focus is redirected outside withAnimation to keep the fade-out animation
        // from being skipped, and to keep the remote touch area pointing at the
        // background Button's showControls() action rather than a hidden control.
        focusedControl = .background
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

/// Glass-backed button style used by the playback failure overlay.
/// Scales on focus and brightens the glass material to indicate selection.
struct TVFailureButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassBackground(
                isFocused ? .tinted(.white.opacity(0.25)) : .regular,
                in: .capsule,
                fallback: isFocused ? .ultraThickMaterial : .ultraThinMaterial
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.08 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif
