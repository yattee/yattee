//
//  ExpandedPlayerSheet.swift
//  Yattee
//
//  Full-screen player sheet with video, info, and controls.
//

import SwiftUI

#if os(iOS) || os(macOS) || os(tvOS)

// MARK: - Expanded Player Sheet

struct ExpandedPlayerSheet: View {
    @Environment(\.appEnvironment) var appEnvironment
    @Environment(\.dismiss) private var dismiss

    // MARK: - Sheet State

    @State var showingQualitySheet = false
    @State var showingDeleteDownloadAlert = false
    @State var showingErrorSheet = false
    @State var isCommentsExpanded: Bool = false
    @State var commentsDismissOffset: CGFloat = 0
    /// Direct scroll position control - use scrollTo(y:) to scroll to top
    @State var scrollPosition: ScrollPosition = .init(y: 0)
    @State private var currentScrollOffset: CGFloat = 0
    @State var currentPlayerHeight: CGFloat = 0
    @State private var isBottomOverscroll: Bool = false
    @State var isPortraitPanelVisible: Bool = true
    /// Temporarily hide controls during fullscreen transition to avoid animation glitch
    @State var hideControlsDuringTransition: Bool = false

    /// Resolves the preset's default panel visibility for one orientation
    /// from the cached settings, so creators of this view can seed the initial
    /// state BEFORE the first frame — applying it in onAppear animates a
    /// visible top-to-center video jump during player expansion.
    @MainActor
    static func initialPanelVisibility(for orientation: PanelOrientation, settingsManager: SettingsManager?) -> Bool {
        PanelSettings.cached.effectiveDefaultVisibility(for: orientation)
            .resolve(lastVisible: settingsManager?.detailsPanelLastVisible(for: orientation) ?? false)
    }

    /// Portrait shorthand for `initialPanelVisibility(for:settingsManager:)`.
    @MainActor
    static func initialPortraitPanelVisibility(settingsManager: SettingsManager?) -> Bool {
        initialPanelVisibility(for: .portrait, settingsManager: settingsManager)
    }

    init(initialPortraitPanelVisible: Bool = true) {
        _isPortraitPanelVisible = State(initialValue: initialPortraitPanelVisible)
    }

    // MARK: - Panel Drag State

    /// Current drag offset when dismissing panel (positive = dragging down)
    @State var panelDragOffset: CGFloat = 0
    /// Whether panel is currently being dragged
    @State var isPanelDragging: Bool = false
    /// Current reveal offset when revealing hidden panel (negative = dragging up)
    @State var panelRevealOffset: CGFloat = 0
    /// Video Y offset for animating position (separate from computed position for smooth animation)
    @State var videoYOffset: CGFloat = 0
    /// Whether panel is expanded to cover the player (full-screen panel)
    @State var isPanelExpanded: Bool = false
    /// Current drag offset when expanding panel (negative = dragging up)
    @State var panelExpandOffset: CGFloat = 0
    /// Whether to use compact panel (no description) - animated state
    @State var useCompactPanel: Bool = false
    /// Track if we're in widescreen layout for status bar hiding
    @State private var isInWideScreenLayout = false
    /// Active player controls layout from preset (loaded once, updated on notification)
    // Seeded from the warm cache so the first frames resolve the correct
    // layout (corner mode) instead of flashing the default stacked layout;
    // loadPlayerControlsLayout replaces it with the authoritative value.
    @State var playerControlsLayout: PlayerControlsLayout = PlayerControlsLayout.cached

    // MARK: - Autoplay Countdown State

    /// Current countdown value (seconds remaining)
    @State var autoplayCountdown: Int = 0
    /// Timer for countdown
    @State var autoplayTimer: Timer?
    /// Whether user cancelled the autoplay
    @State var isAutoplayCancelled: Bool = false
    /// Thumbnail URL to display - controlled to prevent old thumbnail flash during transitions
    @State var displayedThumbnailURL: URL?
    /// Loaded thumbnail image stored in @State to survive view re-renders without flashing
    @State var displayedThumbnailImage: Image?
    /// Whether we're in transition and should freeze the thumbnail
    @State var isThumbnailFrozen: Bool = false
    /// Whether we need to scroll to top when player height changes (during video transition)
    @State private var pendingScrollToTopOnHeightChange: Bool = false
    /// Scroll position for recommended videos carousel on ended screen
    @State var recommendedScrollPosition: Int? = 0
    /// Task for preloading comments - cancelled when video changes
    @State var commentsPreloadTask: Task<Void, Never>?

    /// Namespace for matchedGeometryEffect transitions
    @Namespace var playerNamespace

    // MARK: - Layout State (iOS)

    #if os(iOS)
    /// Track previous orientation to detect changes
    @State private var previousIsLandscape: Bool?
    /// Foldable hinge partially open (iPhone Duo laptop position): the
    /// fullscreen portrait layout keeps the video on the upper half and
    /// moves every control to the lower half.
    @State var isTabletopHinge = false
    #endif

    #if os(iOS) || os(macOS)
    /// Debug stats for overlay
    @State var debugStats: MPVDebugStats = MPVDebugStats()
    /// Timer for updating debug stats
    @State var debugUpdateTimer: Timer?
    #endif

    // MARK: - Computed Properties

    var playerService: PlayerService? { appEnvironment?.playerService }
    var playerState: PlayerState? { playerService?.state }
    var downloadManager: DownloadManager? { appEnvironment?.downloadManager }
    var navigationCoordinator: NavigationCoordinator? { appEnvironment?.navigationCoordinator }
    var accentColor: Color { appEnvironment?.settingsManager.resolvedAccentColor ?? .accentColor }

    #if os(iOS)
    var inAppOrientationLock: Bool { appEnvironment?.settingsManager.inAppOrientationLock ?? false }
    #endif

    // MARK: - Comments Helpers

    var comments: [Comment] { playerState?.comments ?? [] }
    var commentsState: CommentsLoadState { playerState?.commentsState ?? .idle }

    // MARK: - Queue Helpers

    var queue: [QueuedVideo] { playerState?.queue ?? [] }
    var history: [QueuedVideo] { playerState?.history ?? [] }
    var isQueueEnabled: Bool { appEnvironment?.settingsManager.queueEnabled ?? true }
    var hasQueueItems: Bool { !queue.isEmpty && isQueueEnabled }

    // MARK: - Autoplay Helpers

    var isAutoPlayEnabled: Bool {
        (appEnvironment?.settingsManager.queueEnabled ?? true) &&
        (appEnvironment?.settingsManager.queueAutoPlayNext ?? true) &&
        playerState?.queueMode != .repeatOne
    }

    var autoPlayCountdownDuration: Int {
        appEnvironment?.settingsManager.queueAutoPlayCountdown ?? 5
    }

    var nextQueuedVideo: QueuedVideo? { queue.first }

    // MARK: - Playback State Helpers

    /// Returns current playback state info for rendering decisions
    var playbackInfo: PlaybackInfo {
        let state = playerState?.playbackState ?? .idle
        let isLoading = state == .loading
        let isIdle = state == .idle
        let isEnded = state == .ended
        let isFailed = if case .failed = state { true } else { false }
        let hasBackend = playerService?.currentBackend != nil && !isLoading && !isIdle && !isEnded && !isFailed
        return PlaybackInfo(
            state: state,
            isLoading: isLoading,
            isIdle: isIdle,
            isEnded: isEnded,
            isFailed: isFailed,
            hasBackend: hasBackend
        )
    }

    // MARK: - Shared Sheets

    /// Presents through the player's sheet host. The host sits inside this
    /// view's body, so this view's own environment can't reach it; the global
    /// request does, because the player host takes requests while it is up.
    func presentSheet(_ sheet: AppSheet) {
        appEnvironment?.navigationCoordinator.presenter.present(sheet)
    }

    func presentAddToPlaylist() {
        guard let video = playerState?.currentVideo else { return }
        presentSheet(.addToPlaylist(video))
    }

    #if !os(tvOS)
    func presentDownloadOptions() {
        guard let video = playerState?.currentVideo, let playerService = appEnvironment?.playerService else { return }
        presentSheet(.downloadOptions(
            video,
            streams: playerService.availableStreams,
            captions: playerService.availableCaptions,
            dislikeCount: playerState?.dislikeCount
        ))
    }
    #endif

    // MARK: - Body

    var body: some View {
        playerContentWithOverlays
            .applyPlayerSheets(
                showingQualitySheet: $showingQualitySheet,
                showingDeleteDownloadAlert: $showingDeleteDownloadAlert,
                onStreamSelected: { stream, audioStream in
                    switchToStream(stream, audioStream: audioStream)
                }
            )
    }

    // MARK: - Player Content with Overlays

    /// Main player content with overlays and event handlers - extracted to help compiler type-checking
    @ViewBuilder
    private var playerContentWithOverlays: some View {
        playerContentWithCommentsOverlay
            .modifier(PlayerEventHandlersModifier(
                isCommentsExpanded: $isCommentsExpanded,
                scrollPosition: $scrollPosition,
                isPanelExpanded: $isPanelExpanded,
                panelExpandOffset: $panelExpandOffset,
                isThumbnailFrozen: $isThumbnailFrozen,
                displayedThumbnailURL: $displayedThumbnailURL,
                displayedThumbnailImage: $displayedThumbnailImage,
                isAutoplayCancelled: $isAutoplayCancelled,
                pendingScrollToTopOnHeightChange: $pendingScrollToTopOnHeightChange,
                playerControlsLayout: $playerControlsLayout,
                isPortraitPanelVisible: $isPortraitPanelVisible,
                isInWideScreenLayout: isInWideScreenLayout,
                stopAutoplayCountdown: stopAutoplayCountdown,
                startAutoplayCountdown: startAutoplayCountdown,
                startPreloadingComments: startPreloadingComments,
                cancelCommentsPreload: cancelCommentsPreload,
                isAutoPlayEnabled: isAutoPlayEnabled,
                nextQueuedVideo: nextQueuedVideo
            ))
            #if os(iOS)
            .modifier(PlayerIOSEventHandlersModifier(
                inAppOrientationLock: inAppOrientationLock,
                toggleFullscreen: toggleFullscreen,
                startDebugUpdates: startDebugUpdates,
                stopDebugUpdates: stopDebugUpdates,
                setupRotationMonitoring: setupRotationMonitoring,
                setupOrientationLockCallback: setupOrientationLockCallback
            ))
            #endif
            #if os(macOS)
            .modifier(PlayerMacOSEventHandlersModifier(
                startDebugUpdates: startDebugUpdates,
                stopDebugUpdates: stopDebugUpdates
            ))
            #endif
    }

    /// Player content with comments overlay - extracted to help compiler type-checking
    @ViewBuilder
    private var playerContentWithCommentsOverlay: some View {
        playerContent
            .accessibilityIdentifier("player.expandedSheet")
            .accessibilityLabel("player.expandedSheet")
            .playerToastOverlay()
            .overlay(alignment: .bottom) {
                expandedCommentsOverlay
            }
            .animation(.smooth(duration: 0.3), value: isCommentsExpanded)
    }

    // MARK: - Comments Overlay

    /// Expanded comments overlay - extracted to help compiler type-checking
    @ViewBuilder
    private var expandedCommentsOverlay: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height - currentPlayerHeight + geometry.safeAreaInsets.bottom
            let commentsMinHeight: CGFloat = 500
            let shouldCoverFullSheet = availableHeight < commentsMinHeight
            let commentsHeight = shouldCoverFullSheet
                ? geometry.size.height + geometry.safeAreaInsets.bottom
                : availableHeight
            let spacerHeight = shouldCoverFullSheet ? 0 : currentPlayerHeight
            let isVisible = !isInWideScreenLayout && isCommentsExpanded

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: spacerHeight)

                ExpandedCommentsView(
                    videoID: playerState?.currentVideo?.id.videoID ?? "",
                    onClose: collapseComments,
                    onDismissOffsetChanged: handleCommentsDismissOffset,
                    onDismissGestureEnded: handleCommentsDismissGestureEnded,
                    dismissThreshold: 30,
                    showAvatars: playerControlsLayout.effectivePanelSettings.commentsShowAvatars
                )
                .frame(height: max(0, commentsHeight))
                .clipped()
            }
            .offset(y: commentsDismissOffset)
            .visualEffect { content, proxy in
                content.offset(y: isVisible ? 0 : proxy.size.height)
            }
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .background(
                GeometryReader { commentsGeometry in
                    Color.clear
                        .onChange(of: commentsGeometry.frame(in: .global)) { _, newFrame in
                            if isCommentsExpanded {
                                navigationCoordinator?.commentsFrame = newFrame
                            }
                        }
                        .onChange(of: isCommentsExpanded) { _, expanded in
                            if expanded {
                                navigationCoordinator?.commentsFrame = commentsGeometry.frame(in: .global)
                            } else {
                                navigationCoordinator?.commentsFrame = .zero
                            }
                        }
                }
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    #if os(iOS)
    /// Whether the status bar and home indicator are hidden for the current
    /// layout state (see the modifier site for the rationale).
    private var hidesSystemOverlays: Bool {
        if navigationCoordinator?.isCornerLayoutActive == true {
            return UIDevice.current.userInterfaceIdiom == .phone
                || !(appEnvironment?.settingsManager.landscapeDetailsPanelVisible ?? true)
        }
        return isInWideScreenLayout || !isPortraitPanelVisible
    }
    #endif

    // MARK: - Player Content

    @ViewBuilder
    private var playerContent: some View {
        GeometryReader { geometry in
            let wideScreen = isWideScreenLayout(size: geometry.size)
            #if os(iOS) || os(macOS)
            // Gate on the full size including safe areas: the corner layout
            // shows the status bar, which would otherwise shrink the measured
            // height and flip the decision back (layout oscillation).
            let cornerActive = isCornerLayout(size: CGSize(
                width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            ))
            #endif

            ZStack(alignment: .top) {
                // Full-screen background - prevents content leaking during aspect ratio animation
                // Use black for all modes since panel-based layout uses black backgrounds
                Color.black.ignoresSafeArea(edges: .bottom)

                #if os(iOS) || os(macOS)
                if geometry.size.width <= 0 || geometry.size.height <= 0 {
                    // Transient zero-size layout pass (e.g. the deferred macOS
                    // player window before its first real layout). Don't mount
                    // either layout branch — a branch mounted here would grab
                    // the shared render view for one frame and immediately hand
                    // it off when the real size picks the other branch.
                    Color.black.ignoresSafeArea(.all)
                } else if wideScreen {
                    if let video = playerState?.currentVideo {
                        if cornerActive {
                            // Corner layout: video top-left with panel regions.
                            // Laid out within the safe area (black background
                            // extends beneath it).
                            cornerContent(video: video)
                        } else {
                            // Widescreen layout with floating panel
                            // Must ignore safe area to get full screen geometry
                            wideScreenContent(video: video)
                                .ignoresSafeArea(.all)
                        }
                    } else {
                        // Widescreen loading state - just show black with spinner
                        Color.black
                            .ignoresSafeArea(.all)
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.large)
                            }
                    }
                } else {
                    // Portrait/standard scrolling layout
                    standardPlayerContent(geometry: geometry)
                }
                #else
                // tvOS uses standard layout only
                standardPlayerContent(geometry: geometry)
                #endif
            }
            #if os(iOS)
            // Applied inside the animation-stripping transaction below so the
            // hinge-driven tabletop switch still animates the video between
            // the screen center and the upper half.
            .animation(.easeInOut(duration: 0.3), value: isTabletopHinge)
            #endif
            .transaction { transaction in
                // Disable animations during layout switch to prevent position interpolation
                transaction.animation = nil
            }
            #if os(iOS)
            .observeHingeLayout(isTabletop: $isTabletopHinge)
            #endif
            #if os(iOS) || os(macOS)
            .onChange(of: cornerActive) { _, newValue in
                navigationCoordinator?.isCornerLayoutActive = newValue
            }
            #endif
            .onChange(of: wideScreen, initial: true) { _, newValue in
                navigationCoordinator?.isWideScreenLayoutActive = newValue
            }
            .onChange(of: wideScreen) { _, newValue in
                isInWideScreenLayout = newValue
                #if os(iOS)
                // Detect orientation changes for panscan reset
                if let previous = previousIsLandscape, previous != newValue {
                    // Landscape→portrait: panscan reset
                    if previous && !newValue {
                        navigationCoordinator?.pinchPanscan = 0
                        // Restore portrait panel visibility state
                        navigationCoordinator?.isPortraitPanelVisible = isPortraitPanelVisible
                    }

                    // Reset panel expansion state on orientation change
                    isPanelExpanded = false
                    panelExpandOffset = 0

                    // Reset panel state to the preset's default visibility
                    if newValue {
                        // Entering landscape: apply the preset's default
                        applyPanelDefaultVisibility(
                            playerControlsLayout.effectivePanelSettings,
                            settingsManager: appEnvironment?.settingsManager
                        )
                        // Portrait panel doesn't exist in wide layout - clear flag so gesture handler allows pinch
                        navigationCoordinator?.isPortraitPanelVisible = false
                    }
                    // Note: Entering portrait preserves panel visibility state
                    // (if hidden before landscape, stays hidden after returning to portrait)
                }
                previousIsLandscape = newValue
                #endif
            }
            .onAppear {
                isInWideScreenLayout = wideScreen
                #if os(iOS) || os(macOS)
                navigationCoordinator?.isCornerLayoutActive = cornerActive
                #endif
                #if os(iOS)
                previousIsLandscape = wideScreen
                if wideScreen {
                    navigationCoordinator?.isPortraitPanelVisible = false
                }
                #endif
                // Provisional pass on fresh player open (prevents stale panel
                // state from a previous session). Uses the cached settings;
                // loadPlayerControlsLayout re-applies the authoritative value.
                if navigationCoordinator?.hasAppliedPanelDefaultVisibility != true {
                    let visible = applyPanelDefaultVisibility(
                        PanelSettings.cached,
                        settingsManager: appEnvironment?.settingsManager
                    )
                    #if os(iOS) || os(macOS)
                    LoggingService.shared.logPlayer("[ExpandedPlayerSheet] onAppear provisional apply: visible=\(visible), state=\(isPortraitPanelVisible), wideScreen=\(wideScreen)")
                    // No animation: this is the opening state, not a user
                    // toggle — animating it here slides the video mid-expand.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isPortraitPanelVisible = visible
                    }
                    if !wideScreen {
                        navigationCoordinator?.isPortraitPanelVisible = visible
                    }
                    #endif
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: commentsState == .loaded && !comments.isEmpty)
        .sheet(isPresented: $showingErrorSheet) {
            ErrorDetailsSheet(errorMessage: playerState?.errorMessage ?? "Unknown error")
        }
        // Host the resolved/ambiguous link confirmation dialogs while the
        // expanded player is up so they appear above this sheet rather than
        // being buried underneath it on the root app view.
        .resolvedLinkPrompts(
            shouldHost: (appEnvironment?.navigationCoordinator.isPlayerExpanded == true),
            appEnvironment: appEnvironment
        )
        // Shared sheets opened from the player, and global requests while it
        // is up, so they appear above the player window.
        .appSheetHost(isTopLevel: appEnvironment?.navigationCoordinator.isPlayerExpanded == true)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        // Corner layout with panels visible keeps the system status bar and
        // home indicator on iPad (a thin strip); hiding the panels (fullscreen
        // state) hides them so the video and controls reach the screen edges.
        // On the iPhone Duo interior the landscape status bar is a ~57pt
        // column plus top row that would inset the whole layout, so the
        // corner layout always hides it there.
        .playerStatusBarHidden(hidesSystemOverlays)
        .persistentSystemOverlays(hidesSystemOverlays ? .hidden : .automatic)
        #endif
    }
}

// MARK: - Player Sheet Modifiers

/// View extension for applying player sheets - extracted to help compiler type-checking
private extension View {
    @ViewBuilder
    func applyPlayerSheets(
        showingQualitySheet: Binding<Bool>,
        showingDeleteDownloadAlert: Binding<Bool>,
        onStreamSelected: @escaping (Stream, Stream?) -> Void
    ) -> some View {
        modifier(PlayerSheetsModifier(
            showingQualitySheet: showingQualitySheet,
            showingDeleteDownloadAlert: showingDeleteDownloadAlert,
            onStreamSelected: onStreamSelected
        ))
    }
}

/// ViewModifier for player sheets - extracted to help compiler type-checking
private struct PlayerSheetsModifier: ViewModifier {
    @Environment(\.appEnvironment) var appEnvironment
    @Binding var showingQualitySheet: Bool
    @Binding var showingDeleteDownloadAlert: Bool
    let onStreamSelected: (Stream, Stream?) -> Void

    var playerService: PlayerService? { appEnvironment?.playerService }
    var playerState: PlayerState? { playerService?.state }
    var downloadManager: DownloadManager? { appEnvironment?.downloadManager }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingQualitySheet) {
                qualitySelectorSheet
            }
            #if !os(tvOS)
            .alert(
                String(localized: "player.deleteDownload.title"),
                isPresented: $showingDeleteDownloadAlert
            ) {
                Button(String(localized: "player.deleteDownload.cancel"), role: .cancel) {}
                Button(String(localized: "player.deleteDownload.delete"), role: .destructive) {
                    if let video = playerState?.currentVideo,
                       let download = downloadManager?.download(for: video.id)
                    {
                        Task {
                            await downloadManager?.delete(download)
                        }
                    }
                }
            } message: {
                Text(String(localized: "player.deleteDownload.message"))
            }
            #endif
    }

    @ViewBuilder
    private var qualitySelectorSheet: some View {
        if let playerService {
            let supportedFormats = playerService.currentBackendType.supportedFormats
            QualitySelectorView(
                streams: playerService.availableStreams.filter { stream in
                    let format = StreamFormat.detect(from: stream)
                    // DASH is never offered for manual selection
                    if format == .dash {
                        return false
                    }
                    return supportedFormats.contains(format)
                },
                captions: playerService.availableCaptions,
                currentStream: playerState?.currentStream,
                currentAudioStream: playerState?.currentAudioStream,
                currentCaption: playerService.currentCaption,
                isLoading: playerService.availableStreams.isEmpty && playerState?.playbackState == .loading,
                currentDownload: playerService.currentDownload,
                isLoadingOnlineStreams: playerService.isLoadingOnlineStreams,
                localCaptionURL: playerService.currentDownload.flatMap { download in
                    guard let path = download.localCaptionPath else { return nil }
                    return appEnvironment?.downloadManager.downloadsDirectory().appendingPathComponent(path)
                },
                currentRate: playerState?.rate ?? .x1,
                isControlsLocked: playerState?.isControlsLocked ?? false,
                isAudioMode: appEnvironment?.settingsManager.audioOnlyModeEnabled ?? false,
                embeddedAudioTracks: playerService.embeddedAudioTracks,
                embeddedSubtitleTracks: playerService.embeddedSubtitleTracks,
                currentEmbeddedAudioTrackID: playerService.selectedEmbeddedAudioTrackID,
                currentEmbeddedSubtitleTrackID: playerService.selectedEmbeddedSubtitleTrackID,
                embeddedVideoTrack: playerService.primaryEmbeddedVideoTrack,
                onStreamSelected: { stream, audioStream in
                    onStreamSelected(stream, audioStream)
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
                onEmbeddedAudioTrackSelected: { trackID in
                    playerService.selectEmbeddedAudioTrack(trackID)
                },
                onEmbeddedSubtitleTrackSelected: { trackID in
                    playerService.selectEmbeddedSubtitleTrack(trackID)
                },
                onRateChanged: { rate in
                    playerState?.rate = rate
                    playerService.currentBackend?.rate = Float(rate.rawValue)
                },
                onLockToggled: { locked in
                    playerState?.isControlsLocked = locked
                },
                onAudioModeToggled: { enabled in
                    Task {
                        await playerService.setAudioMode(enabled)
                    }
                }
            )
        }
    }

}

// MARK: - Player Event Handlers Modifier

/// ViewModifier for common player event handlers - extracted to help compiler type-checking
private struct PlayerEventHandlersModifier: ViewModifier {
    @Environment(\.appEnvironment) var appEnvironment
    @Binding var isCommentsExpanded: Bool
    @Binding var scrollPosition: ScrollPosition
    @Binding var isPanelExpanded: Bool
    @Binding var panelExpandOffset: CGFloat
    @Binding var isThumbnailFrozen: Bool
    @Binding var displayedThumbnailURL: URL?
    @Binding var displayedThumbnailImage: Image?
    @Binding var isAutoplayCancelled: Bool
    @Binding var pendingScrollToTopOnHeightChange: Bool
    @Binding var playerControlsLayout: PlayerControlsLayout
    @Binding var isPortraitPanelVisible: Bool
    let isInWideScreenLayout: Bool

    let stopAutoplayCountdown: () -> Void
    let startAutoplayCountdown: () -> Void
    let startPreloadingComments: () -> Void
    let cancelCommentsPreload: () -> Void
    let isAutoPlayEnabled: Bool
    let nextQueuedVideo: QueuedVideo?

    var playerState: PlayerState? { appEnvironment?.playerService.state }
    var navigationCoordinator: NavigationCoordinator? { appEnvironment?.navigationCoordinator }

    func body(content: Content) -> some View {
        content
            .onChange(of: isCommentsExpanded) { _, newValue in
                navigationCoordinator?.isCommentsExpanded = newValue
            }
            .onChange(of: playerState?.currentVideo?.id) { _, _ in
                handleVideoChange()
            }
            .onChange(of: playerState?.playbackState) { oldState, newState in
                handlePlaybackStateChange(oldState: oldState, newState: newState)
            }
            .onChange(of: playerState?.isBufferReady) { oldValue, newValue in
                if newValue == true && oldValue != true {
                    startPreloadingComments()
                    // Unfreeze thumbnail now that player is ready
                    isThumbnailFrozen = false
                }
            }
            .onChange(of: navigationCoordinator?.scrollPlayerIntoViewTrigger) { _, _ in
                handleScrollIntoView()
            }
            .onAppear {
                handleOnAppear()
            }
            .task {
                await loadPlayerControlsLayout()
            }
            .onReceive(NotificationCenter.default.publisher(for: .playerControlsActivePresetDidChange)) { _ in
                Task { await loadPlayerControlsLayout() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .playerControlsPresetsDidChange)) { _ in
                Task { await loadPlayerControlsLayout() }
            }
    }

    private func handleVideoChange() {
        cancelCommentsPreload()

        pendingScrollToTopOnHeightChange = true
        scrollPosition.scrollTo(y: 0)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            playerState?.comments = []
            playerState?.commentsState = .idle
            playerState?.commentsContinuation = nil
            isCommentsExpanded = false
            navigationCoordinator?.commentsFrame = .zero
            isPanelExpanded = false
            panelExpandOffset = 0
        }
        stopAutoplayCountdown()
        isAutoplayCancelled = false

        // Clear loaded image so new video gets fresh thumbnail
        displayedThumbnailImage = nil
        // Capture thumbnail URL immediately and freeze to prevent flash during details load.
        // Use the reliable (hqdefault) variant: the frozen URL is loaded without fallback,
        // and the best advertised variant often 404s for older videos.
        displayedThumbnailURL = playerState?.currentVideo?.reliableThumbnailURL
        isThumbnailFrozen = true
    }

    private func handlePlaybackStateChange(oldState: PlaybackState?, newState: PlaybackState?) {
        if newState == .ended {
            if isAutoPlayEnabled && nextQueuedVideo != nil {
                startAutoplayCountdown()
            }
        } else if oldState == .ended {
            stopAutoplayCountdown()
            isAutoplayCancelled = false
        }
    }

    private func handleScrollIntoView() {
        let animationDuration = 0.25
        withAnimation(.easeOut(duration: animationDuration)) {
            scrollPosition.scrollTo(y: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak navigationCoordinator] in
            navigationCoordinator?.isPlayerScrollAnimating = false
        }
    }

    private func handleOnAppear() {
        if playerState?.isBufferReady == true && playerState?.commentsState == .idle {
            startPreloadingComments()
        }

        if playerState?.playbackState == .ended,
           isAutoPlayEnabled,
           nextQueuedVideo != nil,
           !isAutoplayCancelled {
            startAutoplayCountdown()
        }
    }

    private func loadPlayerControlsLayout() async {
        if let service = appEnvironment?.playerControlsLayoutService {
            let layout = await service.activeLayout()
            playerControlsLayout = layout
            PlayerControlsLayout.cached = layout
            GlobalLayoutSettings.cached = layout.globalSettings
            MiniPlayerSettings.cached = layout.effectiveMiniPlayerSettings
            PanelSettings.cached = layout.effectivePanelSettings

            // Apply the preset's default panel visibility once per expanded
            // player session, now that the authoritative settings are loaded.
            if navigationCoordinator?.hasAppliedPanelDefaultVisibility != true {
                let visible = applyPanelDefaultVisibility(
                    layout.effectivePanelSettings,
                    settingsManager: appEnvironment?.settingsManager
                )
                #if os(iOS) || os(macOS)
                LoggingService.shared.logPlayer("[ExpandedPlayerSheet] authoritative apply: visible=\(visible), state=\(isPortraitPanelVisible), wideScreen=\(isInWideScreenLayout)")
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isPortraitPanelVisible = visible
                }
                if !isInWideScreenLayout {
                    navigationCoordinator?.isPortraitPanelVisible = visible
                }
                #endif
                navigationCoordinator?.hasAppliedPanelDefaultVisibility = true
            }
        }
    }
}

/// Applies the preset's default details panel visibility for a fresh
/// panel mount. The landscape default is written straight to the
/// persisted landscape state (the wide layouts read it); the portrait
/// default is returned so callers can mirror it into the portrait panel
/// state, which lives in view @State rather than settings.
@MainActor
@discardableResult
private func applyPanelDefaultVisibility(_ settings: PanelSettings, settingsManager: SettingsManager?) -> Bool {
    guard let settingsManager else { return true }
    settingsManager.landscapeDetailsPanelVisible = settings
        .effectiveDefaultVisibility(for: .landscape)
        .resolve(lastVisible: settingsManager.landscapeDetailsPanelLastVisible)
    return settings
        .effectiveDefaultVisibility(for: .portrait)
        .resolve(lastVisible: settingsManager.portraitDetailsPanelLastVisible)
}

// MARK: - iOS Event Handlers Modifier

#if os(iOS)
/// ViewModifier for iOS-specific player event handlers - extracted to help compiler type-checking
private struct PlayerIOSEventHandlersModifier: ViewModifier {
    @Environment(\.appEnvironment) var appEnvironment

    let inAppOrientationLock: Bool
    let toggleFullscreen: () -> Void
    let startDebugUpdates: () -> Void
    let stopDebugUpdates: () -> Void
    let setupRotationMonitoring: () -> Void
    let setupOrientationLockCallback: () -> Void

    var playerState: PlayerState? { appEnvironment?.playerService.state }
    var navigationCoordinator: NavigationCoordinator? { appEnvironment?.navigationCoordinator }

    func body(content: Content) -> some View {
        content
            .onAppear {
                setupRotationMonitoring()
                setupOrientationLockCallback()
                if inAppOrientationLock {
                    OrientationManager.shared.lock()
                }
            }
            .onDisappear {
                DeviceRotationManager.shared.stopMonitoring()
                DeviceRotationManager.shared.isOrientationLocked = nil
                OrientationManager.shared.unlock()
                stopDebugUpdates()
            }
            .onChange(of: inAppOrientationLock) { _, isLocked in
                if isLocked {
                    OrientationManager.shared.lock()
                } else {
                    OrientationManager.shared.unlock()
                }
            }
            .onChange(of: navigationCoordinator?.pendingFullscreenToggle) { _, _ in
                toggleFullscreen()
            }
            .onChange(of: playerState?.showDebugOverlay) { _, isVisible in
                if isVisible == true {
                    startDebugUpdates()
                } else {
                    stopDebugUpdates()
                }
            }
    }
}
#endif

// MARK: - macOS Event Handlers Modifier

#if os(macOS)
/// ViewModifier for macOS-specific player event handlers - extracted to help compiler type-checking
private struct PlayerMacOSEventHandlersModifier: ViewModifier {
    @Environment(\.appEnvironment) var appEnvironment

    let startDebugUpdates: () -> Void
    let stopDebugUpdates: () -> Void

    var playerState: PlayerState? { appEnvironment?.playerService.state }

    /// Corner layout with its panels visible resizes the window freely: no
    /// aspect lock, no auto-fit. With the panels hidden only the video is
    /// left, so the window follows the ratio lock like the stacked layout.
    private var isCornerLayoutActive: Bool {
        appEnvironment?.isCornerPanelLayoutActive == true
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: playerState?.showDebugOverlay) { _, isVisible in
                if isVisible == true {
                    startDebugUpdates()
                } else {
                    stopDebugUpdates()
                }
            }
            .onChange(of: playerState?.videoAspectRatio) { oldValue, newValue in
                handleAspectRatioChange(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: playerState?.currentVideo?.id) { oldValue, newValue in
                handleVideoChangeForResize(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: appEnvironment?.isCornerPanelLayoutActive) { _, isCorner in
                handleCornerLayoutChange(isCorner: isCorner == true)
            }
            .onAppear {
                handleMacOSAppear()
            }
    }

    /// Entering corner mode with panels shown drops the window's aspect-ratio
    /// constraint so it resizes freely; leaving it (stacked layout, or corner
    /// panels hidden) restores the lock (and auto-fit, when on) exactly as the
    /// aspect-change handler would have applied it.
    private func handleCornerLayoutChange(isCorner: Bool) {
        if isCorner {
            ExpandedPlayerWindowManager.shared.unlockAspectRatio()
        } else if let aspectRatio = playerState?.videoAspectRatio, aspectRatio > 0 {
            ExpandedPlayerWindowManager.shared.lockAspectRatio(aspectRatio)
            // Auto-fit only when the layout change was not caused by the
            // user dragging the window. The corner layout resolves from the
            // window width, so a drag across its threshold flips this handler;
            // fitting back to the video size mid-drag pushes the width over
            // the threshold again and the window oscillates between layouts
            // for the rest of the drag. The user's drag owns the size.
            if appEnvironment?.settingsManager.playerSheetAutoResize == true,
               !ExpandedPlayerWindowManager.shared.isLiveResizing {
                ExpandedPlayerWindowManager.shared.resizeToFitAspectRatio(aspectRatio, animated: true)
            }
        }
    }

    private func handleAspectRatioChange(oldValue: Double?, newValue: Double?) {
        guard !isCornerLayoutActive else { return }
        // nil while a video is loaded means audio-only playback (no video
        // track reports a size) — fall back to the standard 16:9 instead of
        // keeping the previous video's ratio.
        let ratio: Double
        if let newValue, newValue > 0 {
            ratio = newValue
        } else if playerState?.currentVideo != nil {
            ratio = 16.0 / 9.0
        } else {
            return
        }

        // Always keep the manual-resize aspect lock in sync, regardless of the
        // auto-resize setting — the user always wants resize to be ratio-locked.
        ExpandedPlayerWindowManager.shared.lockAspectRatio(ratio)

        guard appEnvironment?.settingsManager.playerSheetAutoResize == true else { return }

        let shouldAnimate = oldValue != nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            ExpandedPlayerWindowManager.shared.resizeToFitAspectRatio(
                ratio,
                animated: shouldAnimate
            )
        }
    }

    private func handleVideoChangeForResize(oldValue: Video.ID?, newValue: Video.ID?) {
        guard !isCornerLayoutActive else { return }
        guard oldValue != nil, newValue != nil else { return }
        guard appEnvironment?.settingsManager.playerSheetAutoResize == true else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if let aspectRatio = playerState?.videoAspectRatio, aspectRatio > 0 {
                ExpandedPlayerWindowManager.shared.resizeToFitAspectRatio(
                    aspectRatio,
                    animated: true
                )
            }
        }
    }

    private func handleMacOSAppear() {
        guard !isCornerLayoutActive else { return }
        guard let aspectRatio = playerState?.videoAspectRatio, aspectRatio > 0 else { return }

        // Lock aspect ratio for manual resize unconditionally.
        ExpandedPlayerWindowManager.shared.lockAspectRatio(aspectRatio)

        if appEnvironment?.settingsManager.playerSheetAutoResize == true {
            ExpandedPlayerWindowManager.shared.resizeToFitAspectRatio(aspectRatio, animated: false)
        }
    }
}
#endif

// MARK: - Preview

#Preview("Player Sheet") {
    Text("Tap to open")
        .sheet(isPresented: .constant(true)) {
            ExpandedPlayerSheet()
        }
        .appEnvironment(.preview)
}

#endif
