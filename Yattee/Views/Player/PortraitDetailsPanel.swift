//
//  PortraitDetailsPanel.swift
//  Yattee
//
//  Details panel for portrait mode with no header bar.
//  Shows video info, description, comments pill, and queue pill.
//

import SwiftUI

#if os(iOS)

struct PortraitDetailsPanel: View {
    let onChannelTap: (() -> Void)?
    let playerControlsLayout: PlayerControlsLayout
    let onFullscreen: (() -> Void)?

    // Drag gesture callbacks
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: ((CGFloat, CGFloat) -> Void)?
    var onDragCancelled: (() -> Void)?

    @Environment(\.appEnvironment) private var appEnvironment
    @GestureState private var isDraggingHandle: Bool = false
    @State private var isCommentsExpanded: Bool = false
    @State private var showFormattedDate = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollToTopTrigger: Bool = false
    @State private var showQueueSheet: Bool = false
    @State private var showPlaylistSheet: Bool = false
    @State private var panelHeight: CGFloat = 0

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
    private var accentColor: Color { settingsManager?.accentColor.color ?? .accentColor }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }
    private var isPanelDragging: Bool { appEnvironment?.navigationCoordinator.isPanelDragging ?? false }

    // Read video and dislikeCount from playerState for reactive updates
    private var video: Video? { playerState?.currentVideo }
    private var dislikeCount: Int? { playerState?.dislikeCount }

    // Comments helpers
    private var comments: [Comment] { playerState?.comments ?? [] }
    private var commentsState: CommentsLoadState { playerState?.commentsState ?? .idle }

    // Video details helpers
    private var videoDetailsState: VideoDetailsLoadState { playerState?.videoDetailsState ?? .idle }

    // Queue helpers
    private var queue: [QueuedVideo] { playerState?.queue ?? [] }
    private var history: [QueuedVideo] { playerState?.history ?? [] }
    private var isQueueEnabled: Bool { settingsManager?.queueEnabled ?? true }

    // Player pill helpers
    private var playerPillSettings: PlayerPillSettings {
        playerControlsLayout.effectivePlayerPillSettings
    }
    private var shouldShowPlayerPill: Bool {
        playerPillSettings.visibility.isVisible(isWideLayout: false) &&
        !playerPillSettings.buttons.isEmpty
    }

    // Comments pill helpers
    private var commentsPillMode: CommentsPillMode {
        playerPillSettings.effectiveCommentsPillMode
    }
    private var shouldShowCommentsPill: Bool {
        playerPillSettings.shouldShowCommentsPill
    }
    private var isCommentsPillAlwaysCollapsed: Bool {
        playerPillSettings.isCommentsPillAlwaysCollapsed
    }

    private var hasVideoDescription: Bool {
        !(video?.description ?? "").isEmpty
    }

    /// Whether any pills are currently visible in the overlay
    private var hasPillsVisible: Bool {
        let hasCommentsPill = commentsState == .loaded && !comments.isEmpty && shouldShowCommentsPill
        return shouldShowPlayerPill || hasCommentsPill
    }

    /// Whether comments pill is shown expanded on its own row (above player pill)
    private var hasExpandedCommentsPill: Bool {
        let hasCommentsPill = commentsState == .loaded && !comments.isEmpty && shouldShowCommentsPill
        return hasCommentsPill && shouldShowPlayerPill && !isCommentsPillAlwaysCollapsed && hasVideoDescription
    }

    /// Returns the first enabled Yattee Server instance URL, if any.
    private var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    /// Returns the DeArrow title if available and enabled, otherwise the original title.
    private func displayTitle(for video: Video) -> String {
        appEnvironment?.deArrowBrandingProvider.title(for: video) ?? video.title
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, 5)
            .padding(.bottom, 2)
    }

    // MARK: - Bottom Fade Overlay

    @ViewBuilder
    private var bottomFadeOverlay: some View {
        // Fade height: tall when comments expanded on own row, medium for single-row pills, short when no pills
        // When expanded: 24pt padding + 52pt player pill + 12pt spacing + ~26pt (half comments pill) ≈ 115pt
        let fadeHeight: CGFloat = hasExpandedCommentsPill ? 115 : (hasPillsVisible ? 70 : 25)

        ZStack {
            // Touch-blocking layer (invisible but intercepts touches)
            Color.white.opacity(0.001)
                .frame(height: fadeHeight)
                .contentShape(Rectangle())

            // Visual gradient
            LinearGradient(
                colors: [.clear, Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            .allowsHitTesting(false)
        }
        .frame(height: fadeHeight)
        .animation(.easeInOut(duration: 0.2), value: hasExpandedCommentsPill)
        .animation(.easeInOut(duration: 0.2), value: hasPillsVisible)
    }

    var body: some View {
        if let video {
            ZStack(alignment: .top) {
                // Scrollable content (extends to top, scrolls under drag handle)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Anchor for scroll-to-top
                            Color.clear
                                .frame(height: 0)
                                .id("panelTop")

                            // Top padding so content isn't initially obscured by drag handle
                            Color.clear
                                .frame(height: 10)

                            videoInfo(video)

                            Divider()
                                .padding(.horizontal)

                            infoTabSection(video)
                        }
                    }
                    .background(Color(.systemBackground))
                    .background {
                        // UIKit gesture handler for smooth overscroll-to-collapse
                        OverscrollGestureView(
                            onDragChanged: { offset in
                                onDragChanged?(offset)
                            },
                            onDragEnded: { offset, predicted in
                                onDragEnded?(offset, predicted)
                            }
                        )
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y
                    } action: { _, newValue in
                        // Update scrollOffset for pills visibility
                        scrollOffset = max(0, newValue)
                    }
                    .onChange(of: scrollToTopTrigger) { _, _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("panelTop", anchor: .top)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    bottomFadeOverlay
                }

                // Extended drag hit area overlay - visual handle at top, hit area extends down
                VStack(spacing: 0) {
                    dragHandle
                    Spacer()
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemBackground).opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 25)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(coordinateSpace: .global)
                        .updating($isDraggingHandle) { _, state, _ in
                            state = true
                        }
                        .onChanged { value in
                            // Allow both upward (negative) and downward (positive) drag
                            let offset = value.translation.height
                            onDragChanged?(offset)
                        }
                        .onEnded { value in
                            onDragEnded?(value.translation.height, value.predictedEndTranslation.height)
                        }
                )
                .onChange(of: isDraggingHandle) { oldValue, newValue in
                    // When gesture state resets (true -> false) but onEnded wasn't called,
                    // the gesture was cancelled (app backgrounded, control center, etc.)
                    if oldValue && !newValue {
                        // Small delay to let onEnded fire first if it will
                        DispatchQueue.main.async {
                            // If still dragging according to parent, it was a cancellation
                            if appEnvironment?.navigationCoordinator.isPanelDragging == true {
                                onDragCancelled?()
                            }
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            // Pills overlay at bottom
            .overlay {
                if !isCommentsExpanded {
                    pillsOverlay
                }
            }
            // Expanded comments overlay
            .overlay {
                let expanded = isCommentsExpanded
                ExpandedCommentsView(
                    videoID: video.id.videoID,
                    onClose: collapseComments,
                    onDismissGestureEnded: handleCommentsDismissGestureEnded,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .visualEffect { content, proxy in
                    content.offset(y: expanded ? 0 : proxy.size.height)
                }
                .opacity(expanded ? 1 : 0)
                .allowsHitTesting(expanded)
            }
            .animation(.smooth(duration: 0.3), value: isCommentsExpanded)
            .onChange(of: video.id) { _, _ in
                isCommentsExpanded = false
            }
            .onChange(of: isCommentsExpanded) { _, newValue in
                appEnvironment?.navigationCoordinator.isCommentsExpanded = newValue
            }
            .sheet(isPresented: $showQueueSheet) {
                QueueManagementSheet()
            }
            .sheet(isPresented: $showPlaylistSheet) {
                if let currentVideo = playerState?.currentVideo {
                    PlaylistSelectorSheet(video: currentVideo)
                }
            }
        }
    }

    // MARK: - Pills Overlay

    @ViewBuilder
    private var pillsOverlay: some View {
        GeometryReader { geometry in
            let isScrolled = scrollOffset > 20
            let hasCommentsPill = commentsState == .loaded && !comments.isEmpty && shouldShowCommentsPill
            let isPlaying = playerState?.playbackState == .playing
            let hasNext = playerState?.hasNext ?? false
            // On narrow devices, use smaller side buttons so the player pill gets more horizontal space
            let isCompactPillRow = geometry.size.width <= 390
            let collapsedCommentWidth: CGFloat = isCompactPillRow ? 40 : 52
            let scrollButtonWidth: CGFloat = isCompactPillRow ? 40 : 52
            let pillRowSpacing: CGFloat = isCompactPillRow ? 8 : 12

            VStack {
                Spacer()

                VStack(spacing: 12) {
                    // Comments pill - on its own row (only when player pill exists AND not collapsed)
                    let isPillCollapsed = isScrolled || isCommentsPillAlwaysCollapsed || !hasVideoDescription
                    if hasCommentsPill, let firstComment = comments.first, shouldShowPlayerPill, !isPillCollapsed {
                        CommentsPillView(
                            comment: firstComment,
                            isCollapsed: false,
                            onTap: expandComments
                        )
                    }

                    // Bottom row
                    bottomPillsRow(
                        hasCommentsPill: hasCommentsPill,
                        collapsedCommentWidth: collapsedCommentWidth,
                        pillRowSpacing: pillRowSpacing,
                        isCompact: isCompactPillRow,
                        isPlaying: isPlaying,
                        hasNext: hasNext,
                        scrollButtonWidth: scrollButtonWidth,
                        availableWidth: geometry.size.width,
                        isScrolled: isScrolled
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            // Only animate when comments load or player pill changes, not on panel size changes
            // Suppress animations during panel drag to prevent independent animation on release
            .animation(isPanelDragging ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: hasCommentsPill)
            .animation(isPanelDragging ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: shouldShowPlayerPill)
            .animation(isPanelDragging ? nil : .easeInOut(duration: 0.2), value: isScrolled)
            .onAppear {
                panelHeight = geometry.size.height
            }
            .onChange(of: geometry.size.height) { _, newValue in
                panelHeight = newValue
            }
        }
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
        scrollButtonWidth: CGFloat,
        availableWidth: CGFloat,
        isScrolled: Bool
    ) -> some View {
        // Calculate max pill width: available width minus placeholders and spacing
        // Layout: [16 padding] [left] [spacing] [PILL] [spacing] [right] [16 padding]
        let edgeElementsWidth: CGFloat = 32 + collapsedCommentWidth + scrollButtonWidth + (pillRowSpacing * 2)
        let maxPillWidth = max(availableWidth - edgeElementsWidth, 150)

        HStack(spacing: pillRowSpacing) {
            // Left side: comments pill or placeholder
            let isPillCollapsed = isScrolled || isCommentsPillAlwaysCollapsed || !hasVideoDescription
            if hasCommentsPill, let firstComment = comments.first {
                if !shouldShowPlayerPill {
                    // No player pill: show comments in bottom row (respect collapse mode)
                    CommentsPillView(
                        comment: firstComment,
                        isCollapsed: isPillCollapsed,
                        fillWidth: !isPillCollapsed,
                        compact: isCompact && isPillCollapsed,
                        onTap: expandComments
                    )
                    .frame(maxWidth: isPillCollapsed ? nil : 400)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if isPillCollapsed {
                    // Player pill exists AND collapsed: show comments button on left
                    CommentsPillView(
                        comment: firstComment,
                        isCollapsed: true,
                        compact: isCompact,
                        onTap: expandComments
                    )
                } else {
                    // Placeholder (expanded comments on its own row)
                    Color.clear.frame(width: collapsedCommentWidth, height: collapsedCommentWidth)
                }
            } else if shouldShowPlayerPill {
                Color.clear.frame(width: collapsedCommentWidth, height: collapsedCommentWidth)
            }

            // Player pill
            if shouldShowPlayerPill {
                PlayerPillView(
                    settings: playerPillSettings,
                    maxWidth: maxPillWidth,
                    isWideLayout: false,
                    isPlaying: isPlaying,
                    hasNext: hasNext,
                    queueCount: queue.count,
                    queueModeIcon: playerState?.queueMode.icon ?? "list.bullet",
                    isPlayPauseDisabled: playerState?.playbackState == .loading,
                    isOrientationLocked: appEnvironment?.settingsManager.inAppOrientationLock ?? false,
                    video: video,
                    playbackRate: playerState?.rate ?? .x1,
                    showingPlaylistSheet: $showPlaylistSheet,
                    onQueueTap: { showQueueSheet = true },
                    onPrevious: { Task { await playerService?.playPrevious() } },
                    onPlayPause: { playerService?.togglePlayPause() },
                    onNext: { Task { await playerService?.playNext() } },
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
                        appEnvironment?.navigationCoordinator.isPlayerExpanded = false
                    },
                    onAirPlay: { /* AirPlay - handled by system */ },
                    onPiP: {
                        #if os(iOS)
                        if let mpvBackend = playerService?.currentBackend as? MPVBackend {
                            mpvBackend.togglePiP()
                        }
                        #endif
                    },
                    onOrientationLock: {
                        #if os(iOS)
                        appEnvironment?.settingsManager.inAppOrientationLock.toggle()
                        #endif
                    },
                    onFullscreen: { onFullscreen?() },
                    onRateChanged: { rate in
                        playerState?.rate = rate
                        playerService?.currentBackend?.rate = Float(rate.rawValue)
                    }
                )
            }

            // Spacer to push scroll button trailing when no player pill
            if !shouldShowPlayerPill {
                Spacer()
            }

            // Scroll button or placeholder
            if scrollOffset > 20 {
                Button {
                    scrollToTopTrigger.toggle()
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
                Color.clear.frame(width: scrollButtonWidth, height: scrollButtonWidth)
            }
        }
    }

    // MARK: - Video Info

    private func videoInfo(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title - full width (shows DeArrow title if available)
            Text(displayTitle(for: video))
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(3)

            // Stats row - only show for non-media-source videos
            if !video.isFromMediaSource {
                VideoStatsRow(
                    playerState: playerState,
                    showFormattedDate: $showFormattedDate,
                    returnYouTubeDislikeEnabled: settingsManager?.returnYouTubeDislikeEnabled ?? false
                )
            }

            // Channel row with context menu
            VideoChannelRow(
                author: video.author,
                source: video.id.source,
                yatteeServerURL: yatteeServerURL,
                onChannelTap: onChannelTap,
                video: video,
                accentColor: accentColor,
                showSubscriberCount: !video.isFromMediaSource,
                isLoadingDetails: playerState?.videoDetailsState == .loading
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Info Tab Section

    private func infoTabSection(_ video: Video) -> some View {
        let hasDescription = !(video.description ?? "").isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            descriptionContent(video.description ?? "")

            // Reduced bottom spacer when no description
            Spacer()
                .frame(height: hasDescription ? 80 : 50)
        }
        .padding(.vertical)
    }

    private func expandComments() {
        withAnimation(.smooth(duration: 0.3)) {
            isCommentsExpanded = true
        }
    }

    private func collapseComments() {
        withAnimation(.smooth(duration: 0.3)) {
            isCommentsExpanded = false
        }
    }

    private func handleCommentsDismissGestureEnded(_ finalOffset: CGFloat) {
        let dismissThreshold: CGFloat = 30
        if finalOffset >= dismissThreshold {
            collapseComments()
        }
    }

    private func descriptionContent(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !description.isEmpty {
                Text(DescriptionText.attributed(description, linkColor: accentColor))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .tint(accentColor)
                    .padding(.horizontal)
                    .handleTimestampLinks(using: playerService)
            } else if videoDetailsState == .loading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            }
            // No description text removed - let panel shrink instead
        }
    }
}

#endif
