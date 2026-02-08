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
    @State private var showingPlaylistSheet = false
    @State var showingDownloadSheet = false
    @State var showingDeleteDownloadAlert = false
    @State var showingQueueSheet = false
    @State var showingErrorSheet = false
    @State var isCommentsExpanded: Bool = false
    @State var commentsDismissOffset: CGFloat = 0
    /// Direct scroll position control - use scrollTo(y:) to scroll to top
    @State var scrollPosition: ScrollPosition = .init(y: 0)
    @State private var showScrollButton = false
    @State private var currentScrollOffset: CGFloat = 0
    @State var currentPlayerHeight: CGFloat = 0
    @State private var isBottomOverscroll: Bool = false
    @State var isPortraitPanelVisible: Bool = true
    /// Temporarily hide controls during fullscreen transition to avoid animation glitch
    @State var hideControlsDuringTransition: Bool = false

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
    @State var showFormattedDate = false
    @State var showOriginalTitle = false
    /// Track if we're in widescreen layout for status bar hiding
    @State private var isInWideScreenLayout = false
    /// Active player controls layout from preset (loaded once, updated on notification)
    @State var playerControlsLayout: PlayerControlsLayout = .default

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
    var accentColor: Color { appEnvironment?.settingsManager.accentColor.color ?? .accentColor }

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

    // MARK: - Player Pill Helpers

    var playerPillSettings: PlayerPillSettings {
        playerControlsLayout.effectivePlayerPillSettings
    }
    var shouldShowPlayerPill: Bool {
        playerPillSettings.visibility.isVisible(isWideLayout: true) &&
        !playerPillSettings.buttons.isEmpty
    }

    // MARK: - Autoplay Helpers

    var isAutoPlayEnabled: Bool {
        (appEnvironment?.settingsManager.queueEnabled ?? true) &&
        (appEnvironment?.settingsManager.queueAutoPlayNext ?? true)
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

    // MARK: - Body

    var body: some View {
        playerContentWithOverlays
            .applyPlayerSheets(
                showingQualitySheet: $showingQualitySheet,
                showingPlaylistSheet: $showingPlaylistSheet,
                showingDownloadSheet: $showingDownloadSheet,
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
                showOriginalTitle: $showOriginalTitle,
                isThumbnailFrozen: $isThumbnailFrozen,
                displayedThumbnailURL: $displayedThumbnailURL,
                displayedThumbnailImage: $displayedThumbnailImage,
                isAutoplayCancelled: $isAutoplayCancelled,
                pendingScrollToTopOnHeightChange: $pendingScrollToTopOnHeightChange,
                playerControlsLayout: $playerControlsLayout,
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
                    dismissThreshold: 30
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
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Player Content

    @ViewBuilder
    private var playerContent: some View {
        GeometryReader { geometry in
            let wideScreen = isWideScreenLayout(size: geometry.size)

            ZStack(alignment: .top) {
                // Full-screen background - prevents content leaking during aspect ratio animation
                // Use black for all modes since panel-based layout uses black backgrounds
                Color.black.ignoresSafeArea(edges: .bottom)

                #if os(iOS) || os(macOS)
                if wideScreen {
                    if let video = playerState?.currentVideo {
                        // Widescreen layout with floating panel
                        // Must ignore safe area to get full screen geometry
                        wideScreenContent(video: video)
                            .ignoresSafeArea(.all)
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
            .transaction { transaction in
                // Disable animations during layout switch to prevent position interpolation
                transaction.animation = nil
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

                    // Reset panel state to orientation defaults
                    if newValue {
                        // Entering landscape: reset to hidden/unpinned
                        appEnvironment?.settingsManager.landscapeDetailsPanelVisible = false
                        appEnvironment?.settingsManager.landscapeDetailsPanelPinned = false
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
                #if os(iOS)
                previousIsLandscape = wideScreen
                // Reset panel state on fresh player open (prevents stale state from previous session)
                appEnvironment?.settingsManager.landscapeDetailsPanelVisible = false
                appEnvironment?.settingsManager.landscapeDetailsPanelPinned = false
                if wideScreen {
                    navigationCoordinator?.isPortraitPanelVisible = false
                }
                #endif
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: commentsState == .loaded && !comments.isEmpty)
        .sheet(isPresented: $showingQueueSheet) {
            QueueManagementSheet()
        }
        .sheet(isPresented: $showingErrorSheet) {
            ErrorDetailsSheet(errorMessage: playerState?.errorMessage ?? "Unknown error")
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .playerStatusBarHidden(isInWideScreenLayout || !isPortraitPanelVisible)
        .persistentSystemOverlays((isInWideScreenLayout || !isPortraitPanelVisible) ? .hidden : .automatic)
        #endif
    }

    // MARK: - Bottom Pills Overlay (iOS)

    #if os(iOS)
    /// Extracted overlay for player pill, comments pill and scroll button to help compiler type-checking
    @ViewBuilder
    private var bottomPillsOverlay: some View {
        GeometryReader { geometry in
            let hasCommentsPill = commentsState == .loaded && !comments.isEmpty
            let isPlaying = playerState?.playbackState == .playing
            // Disable play/pause when loading OR when thumbnail is still visible (buffer/frame not ready)
            let isPlayPauseDisabled = playerState?.playbackState == .loading ||
                                      playerState?.playbackState == .buffering ||
                                      !(playerState?.isFirstFrameReady ?? false) ||
                                      !(playerState?.isBufferReady ?? false)
            let hasNext = playerState?.hasNext ?? false
            // On narrow devices, use smaller side buttons so the player pill gets more horizontal space
            let isCompactPillRow = geometry.size.width <= 390
            let collapsedCommentWidth: CGFloat = isCompactPillRow ? 40 : 52
            let scrollButtonWidth: CGFloat = isCompactPillRow ? 40 : 52
            let pillRowSpacing: CGFloat = isCompactPillRow ? 8 : 12

            VStack {
                Spacer()

                VStack(spacing: 12) {
                    // Comments pill - on its own row (only when player pill exists)
                    if hasCommentsPill, let firstComment = comments.first, shouldShowPlayerPill {
                        CommentsPillView(
                            comment: firstComment,
                            isCollapsed: false,
                            onTap: expandComments
                        )
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Bottom row - centered group
                    bottomPillsRow(
                        hasCommentsPill: hasCommentsPill,
                        collapsedCommentWidth: collapsedCommentWidth,
                        pillRowSpacing: pillRowSpacing,
                        isCompact: isCompactPillRow,
                        isPlaying: isPlaying,
                        hasNext: hasNext,
                        isPlayPauseDisabled: isPlayPauseDisabled,
                        scrollButtonWidth: scrollButtonWidth,
                        availableWidth: geometry.size.width
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .background {
                    // Block touches on description links behind pills area
                    // Prevents accidental link taps when trying to tap pills
                    Color.clear
                        .contentShape(Rectangle())
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasCommentsPill)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: shouldShowPlayerPill)
            .animation(.easeInOut(duration: 0.2), value: showScrollButton)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Bottom row of pills (comments, player pill, scroll button) - extracted to help compiler
    @ViewBuilder
    private func bottomPillsRow(
        hasCommentsPill: Bool,
        collapsedCommentWidth: CGFloat,
        pillRowSpacing: CGFloat,
        isCompact: Bool,
        isPlaying: Bool,
        hasNext: Bool,
        isPlayPauseDisabled: Bool,
        scrollButtonWidth: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        // Calculate max pill width: available width minus placeholders and spacing
        // Layout: [16 padding] [left] [spacing] [PILL] [spacing] [right] [16 padding]
        let edgeElementsWidth: CGFloat = 32 + collapsedCommentWidth + scrollButtonWidth + (pillRowSpacing * 2)
        let maxPillWidth = max(availableWidth - edgeElementsWidth, 150)

        HStack(spacing: pillRowSpacing) {
            // Left side: comments pill or placeholder
            if hasCommentsPill, let firstComment = comments.first {
                if !shouldShowPlayerPill {
                    // No player pill: expanded comments in bottom row
                    CommentsPillView(
                        comment: firstComment,
                        isCollapsed: false,
                        fillWidth: true,
                        onTap: expandComments
                    )
                    .frame(maxWidth: 400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Placeholder (expanded comments on its own row)
                    Color.clear
                        .frame(width: collapsedCommentWidth, height: collapsedCommentWidth)
                }
            } else if shouldShowPlayerPill {
                Color.clear
                    .frame(width: collapsedCommentWidth, height: collapsedCommentWidth)
            }

            // Player pill
            if shouldShowPlayerPill {
                PlayerPillView(
                    settings: playerPillSettings,
                    maxWidth: maxPillWidth,
                    isPlaying: isPlaying,
                    hasNext: hasNext,
                    queueCount: queue.count,
                    queueModeIcon: playerState?.queueMode.icon ?? "list.bullet",
                    isPlayPauseDisabled: isPlayPauseDisabled,
                    isOrientationLocked: inAppOrientationLock,
                    video: playerState?.currentVideo,
                    playbackRate: playerState?.rate ?? .x1,
                    showingPlaylistSheet: $showingPlaylistSheet,
                    onQueueTap: { showingQueueSheet = true },
                    onPrevious: {
                        Task { await playerService?.playPrevious() }
                    },
                    onPlayPause: {
                        playerService?.togglePlayPause()
                    },
                    onNext: {
                        playNextInQueue()
                    },
                    onSeek: { signedSeconds in
                        if signedSeconds >= 0 {
                            playerService?.seekForward(by: signedSeconds)
                        } else {
                            playerService?.seekBackward(by: -signedSeconds)
                        }
                    },
                    onClose: {
                        appEnvironment?.queueManager.clearQueue()
                        playerService?.stop()
                        navigationCoordinator?.isPlayerExpanded = false
                    },
                    onAirPlay: { /* AirPlay - handled by system */ },
                    onPiP: {
                        if let mpvBackend = playerService?.currentBackend as? MPVBackend {
                            mpvBackend.togglePiP()
                        }
                    },
                    onOrientationLock: {
                        appEnvironment?.settingsManager.inAppOrientationLock.toggle()
                    },
                    onRateChanged: { rate in
                        playerState?.rate = rate
                        playerService?.currentBackend?.rate = Float(rate.rawValue)
                    }
                )
            }

            // Scroll button or placeholder
            if showScrollButton {
                Button {
                    scrollToTop()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: isCompact ? 28 : 32, height: isCompact ? 28 : 32)
                        .padding(isCompact ? 6 : 10)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassBackground(.regular, in: .circle, fallback: .thinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                .contentShape(Circle())
                .transition(.scale.combined(with: .opacity))
            } else if shouldShowPlayerPill {
                Color.clear
                    .frame(width: scrollButtonWidth, height: scrollButtonWidth)
            }
        }
    }
    #endif
}

// MARK: - Player Sheet Modifiers

/// View extension for applying player sheets - extracted to help compiler type-checking
private extension View {
    @ViewBuilder
    func applyPlayerSheets(
        showingQualitySheet: Binding<Bool>,
        showingPlaylistSheet: Binding<Bool>,
        showingDownloadSheet: Binding<Bool>,
        showingDeleteDownloadAlert: Binding<Bool>,
        onStreamSelected: @escaping (Stream, Stream?) -> Void
    ) -> some View {
        modifier(PlayerSheetsModifier(
            showingQualitySheet: showingQualitySheet,
            showingPlaylistSheet: showingPlaylistSheet,
            showingDownloadSheet: showingDownloadSheet,
            showingDeleteDownloadAlert: showingDeleteDownloadAlert,
            onStreamSelected: onStreamSelected
        ))
    }
}

/// ViewModifier for player sheets - extracted to help compiler type-checking
private struct PlayerSheetsModifier: ViewModifier {
    @Environment(\.appEnvironment) var appEnvironment
    @Binding var showingQualitySheet: Bool
    @Binding var showingPlaylistSheet: Bool
    @Binding var showingDownloadSheet: Bool
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
            .sheet(isPresented: $showingPlaylistSheet) {
                if let video = playerState?.currentVideo {
                    PlaylistSelectorSheet(video: video)
                }
            }
            #if !os(tvOS)
            .sheet(isPresented: $showingDownloadSheet) {
                downloadSheet
            }
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
            let dashEnabled = appEnvironment?.settingsManager.dashEnabled ?? false
            QualitySelectorView(
                streams: playerService.availableStreams.filter { stream in
                    let format = StreamFormat.detect(from: stream)
                    // Filter out DASH streams if disabled in settings
                    if format == .dash && !dashEnabled {
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
                onRateChanged: { rate in
                    playerState?.rate = rate
                    playerService.currentBackend?.rate = Float(rate.rawValue)
                },
                onLockToggled: { locked in
                    playerState?.isControlsLocked = locked
                }
            )
        }
    }

    #if !os(tvOS)
    @ViewBuilder
    private var downloadSheet: some View {
        if let video = playerState?.currentVideo, let playerService {
            DownloadQualitySheet(
                video: video,
                streams: playerService.availableStreams,
                captions: playerService.availableCaptions,
                dislikeCount: playerState?.dislikeCount
            )
        }
    }
    #endif
}

// MARK: - Player Event Handlers Modifier

/// ViewModifier for common player event handlers - extracted to help compiler type-checking
private struct PlayerEventHandlersModifier: ViewModifier {
    @Environment(\.appEnvironment) var appEnvironment
    @Binding var isCommentsExpanded: Bool
    @Binding var scrollPosition: ScrollPosition
    @Binding var isPanelExpanded: Bool
    @Binding var panelExpandOffset: CGFloat
    @Binding var showOriginalTitle: Bool
    @Binding var isThumbnailFrozen: Bool
    @Binding var displayedThumbnailURL: URL?
    @Binding var displayedThumbnailImage: Image?
    @Binding var isAutoplayCancelled: Bool
    @Binding var pendingScrollToTopOnHeightChange: Bool
    @Binding var playerControlsLayout: PlayerControlsLayout

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
            isPanelExpanded = false
            panelExpandOffset = 0
        }
        showOriginalTitle = false
        stopAutoplayCountdown()
        isAutoplayCancelled = false

        // Clear loaded image so new video gets fresh thumbnail
        displayedThumbnailImage = nil
        // Capture thumbnail URL immediately and freeze to prevent flash during details load
        displayedThumbnailURL = playerState?.currentVideo?.bestThumbnail?.url
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
            GlobalLayoutSettings.cached = layout.globalSettings
            MiniPlayerSettings.cached = layout.effectiveMiniPlayerSettings
        }
    }
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
            .onAppear {
                handleMacOSAppear()
            }
    }

    private func handleAspectRatioChange(oldValue: Double?, newValue: Double?) {
        guard let newValue, newValue > 0 else { return }
        guard appEnvironment?.settingsManager.playerSheetAutoResize == true else { return }

        let shouldAnimate = oldValue != nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            ExpandedPlayerWindowManager.shared.resizeToFitAspectRatio(
                newValue,
                animated: shouldAnimate
            )
        }
    }

    private func handleVideoChangeForResize(oldValue: Video.ID?, newValue: Video.ID?) {
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
        if appEnvironment?.settingsManager.playerSheetAutoResize == true,
           let aspectRatio = playerState?.videoAspectRatio,
           aspectRatio > 0 {
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
