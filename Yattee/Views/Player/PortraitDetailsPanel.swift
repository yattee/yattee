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
    @Environment(\.appEnvironment) private var appEnvironment

    let onChannelTap: (() -> Void)?
    let playerControlsLayout: PlayerControlsLayout
    let onFullscreen: (() -> Void)?
    let pillsOverlayOpacity: CGFloat

    /// Corner layout host: comments live in the side column, so the pill is
    /// suppressed entirely.
    var hidesCommentsPill: Bool = false

    /// Portrait inlines chapters/related into the info page; the corner
    /// layout's below-video host turns this off because those live in the
    /// side column tabs (the description stays collapsible either way).
    var inlineInfoSections: Bool = true

    /// Panel clip rounding — the corner layout's below-video host uses 0
    /// for a plain rectangle.
    var panelCornerRadius: CGFloat = 16
    /// Moves the pills off the leading part of the panel (foldable book
    /// posture with the side column hidden: pills centered on the half right
    /// of the hinge).
    var pillsLeadingInset: CGFloat = 0

    // Drag gesture callbacks
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: ((CGFloat, CGFloat) -> Void)?
    var onDragCancelled: (() -> Void)?
    /// Asks the host to expand the panel (comments pill → comments page).
    var onRequestExpand: (() -> Void)?
    @GestureState private var isDraggingHandle: Bool = false
    @State private var isCommentsExpanded: Bool = false
    @State private var selectedPage: PanelPageType = .info
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollToTopTrigger: Bool = false
    @Environment(\.presentAppSheet) private var presentAppSheet

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
    private var accentColor: Color { settingsManager?.resolvedAccentColor ?? .accentColor }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }
    private var isPanelDragging: Bool { appEnvironment?.navigationCoordinator.isPanelDragging ?? false }

    // Read video from playerState for reactive updates
    private var video: Video? { playerState?.currentVideo }

    // Comments helpers
    private var comments: [Comment] { playerState?.comments ?? [] }
    private var commentsState: CommentsLoadState { playerState?.commentsState ?? .idle }

    // Queue helpers
    private var queue: [QueuedVideo] { playerState?.queue ?? [] }

    // Player pill helpers
    private var playerPillSettings: PlayerPillSettings {
        playerControlsLayout.effectivePlayerPillSettings
    }
    private var shouldShowPlayerPill: Bool {
        playerPillSettings.visibility.isVisible(isWideLayout: false) &&
        !playerPillSettings.buttons.isEmpty
    }

    // Comments pill helpers (mode lives on the comments page settings)
    private var commentsPillMode: CommentsPillMode {
        panelSettings.commentsPillMode
    }
    private var shouldShowCommentsPill: Bool {
        !hidesCommentsPill && commentsPillMode != .disabled
    }
    private var isCommentsPillAlwaysCollapsed: Bool {
        commentsPillMode.alwaysCollapsed
    }

    private var hasVideoDescription: Bool {
        !(video?.description ?? "").isEmpty
    }

    // Panel pages configuration
    private var panelSettings: PanelSettings {
        playerControlsLayout.effectivePanelSettings
    }

    /// Prototype: portrait has a single info page with inline sections, so the
    /// comments pill always opens the comments overlay, never a page.
    private var isCommentsPageAvailable: Bool {
        false
    }

    /// Whether any pills are currently visible in the overlay
    private var hasPillsVisible: Bool {
        let hasCommentsPill = commentsState == .loaded && !comments.isEmpty && shouldShowCommentsPill
        return shouldShowPlayerPill || hasCommentsPill
    }

    /// Whether comments pill is shown expanded on its own row (above player pill)
    /// Whether the comments pill currently occupies its own row above the
    /// player pill. Must track the pill's actual collapse state (including
    /// collapse on scroll): the bottom fade sizes its touch blocker from
    /// this, and a stale "expanded" answer swallows taps on the last rows
    /// of content, e.g. a collapsed section header.
    private var hasExpandedCommentsPill: Bool {
        let hasCommentsPill = commentsState == .loaded && !comments.isEmpty && shouldShowCommentsPill
        let isPillCollapsed = scrollOffset > 20 || isCommentsPillAlwaysCollapsed || !hasVideoDescription
        return hasCommentsPill && shouldShowPlayerPill && !isPillCollapsed
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
                // Unified page content (page bar + selected page)
                PlayerPanelContentView(
                    panelSettings: panelSettings,
                    selectedPage: $selectedPage,
                    context: PanelPageContext(
                        appEnvironment: appEnvironment,
                        video: video,
                        accentColor: accentColor,
                        onChannelTap: onChannelTap
                    ),
                    scrollConfig: PanelScrollConfig(
                        topInset: 10,
                        bottomInset: hasVideoDescription ? 80 : 50,
                        scrollOffsetChanged: { offset in
                            scrollOffset = offset
                        },
                        scrollToTopTrigger: scrollToTopTrigger,
                        isScrollDisabled: isDraggingHandle,
                        onOverscrollDragChanged: { offset in
                            onDragChanged?(offset)
                        },
                        onOverscrollDragEnded: { offset, predicted in
                            onDragEnded?(offset, predicted)
                        }
                    ),
                    pageBarTopPadding: 14,
                    showPageBar: false,
                    inlineInfoSections: inlineInfoSections
                )
                .background(Color(.systemBackground))
                .overlay(alignment: .bottom) {
                    bottomFadeOverlay
                }

                // Extended drag hit area overlay - visual handle at top, hit area
                // extends down over the title (the portrait panel has no page bar)
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
                    .allowsHitTesting(false)
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
            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
            // Pills overlay at bottom
            .overlay {
                if !isCommentsExpanded {
                    pillsOverlay
                        .padding(.leading, pillsLeadingInset)
                        .opacity(pillsOverlayOpacity)
                        .allowsHitTesting(pillsOverlayOpacity > 0.01)
                }
            }
            // Expanded comments overlay (only when the comments page is not
            // available; the pill then falls back to the overlay path)
            .overlay {
                if !isCommentsPageAvailable {
                    expandedCommentsOverlay(video: video)
                }
            }
            .animation(.smooth(duration: 0.3), value: isCommentsExpanded)
            .onChange(of: video.id) { _, _ in
                isCommentsExpanded = false
            }
            .onChange(of: isCommentsExpanded) { _, newValue in
                appEnvironment?.navigationCoordinator.isCommentsExpanded = newValue
            }
        }
    }

    @ViewBuilder
    private func expandedCommentsOverlay(video: Video) -> some View {
        let expanded = isCommentsExpanded
        ExpandedCommentsView(
                    videoID: video.id.videoID,
                    onClose: collapseComments,
                    onDismissGestureEnded: handleCommentsDismissGestureEnded,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded,
                    showAvatars: panelSettings.commentsShowAvatars
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .visualEffect { content, proxy in
                    content.offset(y: expanded ? 0 : proxy.size.height)
                }
                .opacity(expanded ? 1 : 0)
                .allowsHitTesting(expanded)
                .background(
                    GeometryReader { commentsGeometry in
                        Color.clear
                            .onChange(of: commentsGeometry.frame(in: .global)) { _, newFrame in
                                if isCommentsExpanded {
                                    appEnvironment?.navigationCoordinator.commentsFrame = newFrame
                                }
                            }
                            .onChange(of: isCommentsExpanded) { _, expanded in
                                if expanded {
                                    appEnvironment?.navigationCoordinator.commentsFrame = commentsGeometry.frame(in: .global)
                                } else {
                                    appEnvironment?.navigationCoordinator.commentsFrame = .zero
                                }
                            }
                    }
                )
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
                            showAvatar: panelSettings.commentsShowAvatars,
                            onTap: expandComments
                        )
                        // Wide hosts (iPad corner/stacked panels) would
                        // stretch the excerpt across the whole panel.
                        .frame(maxWidth: 600)
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
                        showAvatar: panelSettings.commentsShowAvatars,
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
                        showAvatar: panelSettings.commentsShowAvatars,
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
                    onQueueTap: { presentAppSheet(.queue()) },
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

    private func expandComments() {
        if isCommentsPageAvailable {
            // Route to the comments page and ask the host to expand the panel
            withAnimation(.smooth(duration: 0.3)) {
                selectedPage = .comments
            }
            onRequestExpand?()
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            isCommentsExpanded = true
        }
    }

    private func collapseComments() {
        appEnvironment?.navigationCoordinator.commentsFrame = .zero
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
}

#endif
