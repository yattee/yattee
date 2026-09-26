//
//  FloatingDetailsPanel.swift
//  Yattee
//
//  Floating panel showing video details in widescreen layout.
//

import SwiftUI

#if os(iOS) || os(macOS)

// MARK: - Panel Height Preference Key

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FloatingDetailsPanel: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.colorScheme) private var systemColorScheme

    let onPinToggle: () -> Void
    let isPinned: Bool
    let panelSide: FloatingPanelSide
    let onChannelTap: (() -> Void)?
    let onFullscreen: (() -> Void)?

    // Resizable width parameters
    @Binding var panelWidth: CGFloat
    let availableWidth: CGFloat
    let maxPanelWidth: CGFloat

    // Player controls layout for pill settings
    let playerControlsLayout: PlayerControlsLayout
    @State private var isCommentsExpanded: Bool = false
    @State private var selectedPage: PanelPageType = .info
    @State private var scrollOffset: CGFloat = 0
    @State private var panelHeight: CGFloat = 0
    @State private var scrollToTopTrigger: Bool = false
    @State private var showQueueSheet: Bool = false
    @State private var showPlaylistSheet: Bool = false
    @State private var isDragHandleActive: Bool = false

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
    private var accentColor: Color { settingsManager?.resolvedAccentColor ?? .accentColor }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }

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
        playerPillSettings.visibility.isVisible(isWideLayout: true) &&
        !playerPillSettings.buttons.isEmpty
    }

    // Comments pill helpers (mode lives on the comments page settings)
    private var commentsPillMode: CommentsPillMode {
        panelSettings.commentsPillMode
    }
    private var shouldShowCommentsPill: Bool {
        commentsPillMode != .disabled
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

    /// iPhone renders the same single info page with inline sections as the
    /// portrait panel: no page bar, comments stay on the pill/overlay.
    private var usesInlineSections: Bool {
        PanelSettings.isSectionsOnlyDevice
    }

    /// iPhone is floating-only: no pin button on the grabber.
    private var showsPinButton: Bool {
        !PanelSettings.isSectionsOnlyDevice
    }

    /// Whether the comments pill should route to the comments page instead of
    /// the overlay.
    private var isCommentsPageAvailable: Bool {
        !usesInlineSections
            && panelSettings.isPageEnabled(.comments)
            && !(video?.isFromMediaSource ?? true)
    }

    /// Whether any pills are currently visible
    private var hasPillsVisible: Bool {
        let hasCommentsPill = commentsState == .loaded && !comments.isEmpty && shouldShowCommentsPill
        return shouldShowPlayerPill || hasCommentsPill
    }

    /// Whether the expanded comments pill is shown on its own row above the player pill
    private var hasExpandedCommentsPill: Bool {
        let hasCommentsPill = commentsState == .loaded && !comments.isEmpty && shouldShowCommentsPill
        return hasCommentsPill && shouldShowPlayerPill && !isCommentsPillAlwaysCollapsed && hasVideoDescription
    }

    /// Minimum panel width
    static let minPanelWidth: CGFloat = 400
    /// Default panel width
    static let defaultPanelWidth: CGFloat = 400

    /// Clamp width within valid bounds
    private func clampWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, Self.minPanelWidth), maxPanelWidth)
    }

    var body: some View {
        if let video {
            mainPanelLayout(video: video)
        }
    }

    // MARK: - Panel Layout Components

    @ViewBuilder
    private func mainPanelLayout(video: Video) -> some View {
        HStack(spacing: 0) {
            // Resize grabber on left when panel is on right side
            if panelSide == .right {
                grabberWithPinButton
            }

            // Main panel content
            panelContent(video: video)

            // Resize grabber on right when panel is on left side
            if panelSide == .left {
                grabberWithPinButton
            }
        }
        .environment(\.colorScheme, isPinned ? systemColorScheme : .dark)
        .environment(\.presentationColorScheme, systemColorScheme)
        .animation(.easeInOut(duration: 0.25), value: isPinned)
        .onChange(of: video.id) { _, _ in
            // Comments state is managed by parent - just reset local state
            isCommentsExpanded = false
        }
        .onChange(of: isCommentsExpanded) { _, newValue in
            // Sync with NavigationCoordinator to block sheet dismiss gesture when comments expanded
            appEnvironment?.navigationCoordinator.isCommentsExpanded = newValue
        }
        .onChange(of: maxPanelWidth) { _, _ in
            // Re-clamp width when max width changes (e.g., pinned vs floating)
            panelWidth = clampWidth(panelWidth)
        }
        .onChange(of: availableWidth) { _, _ in
            // Re-clamp width when available width changes (e.g., rotation)
            panelWidth = clampWidth(panelWidth)
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

    @ViewBuilder
    private var grabberWithPinButton: some View {
        PanelResizeGrabber(
            panelWidth: $panelWidth,
            minWidth: Self.minPanelWidth,
            maxWidth: maxPanelWidth,
            panelSide: panelSide,
            isPinned: isPinned,
            isDragActive: $isDragHandleActive
        )
        .overlay(alignment: .center) {
            if showsPinButton {
                PanelPinButton(
                    isPinned: isPinned,
                    panelSide: panelSide,
                    onPinToggle: onPinToggle,
                    isDragHandleActive: $isDragHandleActive
                )
                .offset(y: -65)
                .zIndex(10) // Ensure pin button appears above panel content
            }
        }
        .zIndex(10) // Ensure grabber overlay appears above panel
    }

    @ViewBuilder
    private func panelContent(video: Video) -> some View {
        VStack(spacing: 0) {
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
                    topInset: 8,
                    bottomInset: 80,
                    scrollOffsetChanged: { offset in
                        scrollOffset = offset
                    },
                    scrollToTopTrigger: scrollToTopTrigger
                ),
                pageBarTopPadding: 12,
                showPageBar: !usesInlineSections,
                inlineInfoSections: usesInlineSections
            )
        }
        .frame(width: clampWidth(panelWidth))
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .top) {
            topFadeOverlay
        }
        .overlay(alignment: .bottom) {
            bottomFadeOverlay
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: PanelHeightKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(PanelHeightKey.self) { height in
            panelHeight = height
        }
        .overlay(alignment: .bottom) {
            bottomOverlay(video: video)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: commentsState)
        .overlay {
            if !isCommentsPageAvailable {
                expandedCommentsOverlay(video: video)
            }
        }
        .animation(.smooth(duration: 0.3), value: isCommentsExpanded)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if isPinned {
            #if os(iOS)
            Color(uiColor: .systemBackground)
            #else
            Color(nsColor: .windowBackgroundColor)
            #endif
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        }
    }

    /// Background color for fades - adapts to pinned/floating state
    private var fadeBackgroundColor: Color {
        if isPinned {
            #if os(iOS)
            return Color(.systemBackground)
            #else
            return Color(nsColor: .windowBackgroundColor)
            #endif
        } else {
            // Use subtle dark color that blends with material background
            return Color.black.opacity(0.4)
        }
    }

    /// Top fade for wide layout (like portrait drag handle style)
    @ViewBuilder
    private var topFadeOverlay: some View {
        LinearGradient(
            colors: [fadeBackgroundColor, fadeBackgroundColor.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 25)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 16))
        .allowsHitTesting(false)
    }

    /// Bottom fade with touch blocking
    @ViewBuilder
    private var bottomFadeOverlay: some View {
        // Wide layout: comments pill is always in the same row (collapsed when player pill exists)
        // 12pt padding + 52pt pill + ~26pt (half pill) ≈ 90pt when pills visible
        let fadeHeight: CGFloat = hasExpandedCommentsPill ? 115 : (hasPillsVisible ? 90 : 25)

        ZStack {
            // Touch-blocking layer
            Color.white.opacity(0.001)
                .frame(height: fadeHeight)
                .contentShape(Rectangle())

            // Visual gradient
            LinearGradient(
                colors: [.clear, fadeBackgroundColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            .allowsHitTesting(false)
        }
        .frame(height: fadeHeight)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 0))
        .animation(.easeInOut(duration: 0.2), value: hasPillsVisible)
        .animation(.easeInOut(duration: 0.2), value: hasExpandedCommentsPill)
    }

    @ViewBuilder
    private func bottomOverlay(video: Video) -> some View {
        if !isCommentsExpanded {
            let availablePanelHeight = panelHeight
            let hasEnoughSpace = availablePanelHeight == 0 || availablePanelHeight >= 400
            let isPillCollapsed = scrollOffset > 20 || !hasEnoughSpace || isCommentsPillAlwaysCollapsed || !hasVideoDescription
            let showScrollButton = scrollOffset > 20
            let hasCommentsPill = commentsState == .loaded && !comments.isEmpty && shouldShowCommentsPill
            let isPlaying = playerState?.playbackState == .playing
            let hasNext = playerState?.hasNext ?? false

            VStack(spacing: 12) {
                // Expanded comments pill on its own row (when player pill exists and pill not collapsed)
                if hasCommentsPill, let firstComment = comments.first, shouldShowPlayerPill, !isPillCollapsed {
                    CommentsPillView(comment: firstComment, isCollapsed: false, onTap: expandComments)
                }

                ZStack {
                    if shouldShowPlayerPill {
                        playerPillContent(video: video, isPlaying: isPlaying, hasNext: hasNext)
                    }
                    edgeButtonsContent(hasCommentsPill: hasCommentsPill, isPillCollapsed: isPillCollapsed, showScrollButton: showScrollButton)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPillCollapsed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: shouldShowPlayerPill)
            .animation(.easeInOut(duration: 0.2), value: showScrollButton)
        }
    }

    @ViewBuilder
    private func playerPillContent(video: Video, isPlaying: Bool, hasNext: Bool) -> some View {
        let edgeButtonsWidth: CGFloat = 130
        let maxPillWidth = max(clampWidth(panelWidth) - edgeButtonsWidth, 200)

        HStack {
            Spacer()
            PlayerPillView(
                settings: playerPillSettings,
                maxWidth: maxPillWidth,
                isWideLayout: true,
                isPlaying: isPlaying,
                hasNext: hasNext,
                queueCount: queue.count,
                queueModeIcon: playerState?.queueMode.icon ?? "list.bullet",
                isPlayPauseDisabled: playerState?.playbackState == .loading,
                isOrientationLocked: {
                    #if os(iOS)
                    return appEnvironment?.settingsManager.inAppOrientationLock ?? false
                    #else
                    return false
                    #endif
                }(),
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
            Spacer()
        }
    }

    @ViewBuilder
    private func edgeButtonsContent(hasCommentsPill: Bool, isPillCollapsed: Bool, showScrollButton: Bool) -> some View {
        HStack {
            if hasCommentsPill, let firstComment = comments.first {
                if !shouldShowPlayerPill {
                    CommentsPillView(comment: firstComment, isCollapsed: isPillCollapsed, onTap: expandComments)
                } else if isPillCollapsed {
                    CommentsPillView(comment: firstComment, isCollapsed: true, onTap: expandComments)
                }
                // else: expanded pill is on its own row above — nothing here
            }

            Spacer()

            if showScrollButton {
                Button {
                    scrollToTopTrigger.toggle()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .padding(10)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassBackground(.regular, in: .circle, fallback: .thinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                .contentShape(Circle())
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func expandedCommentsOverlay(video: Video) -> some View {
        let expanded = isCommentsExpanded
        ExpandedCommentsView(
            videoID: video.id.videoID,
            onClose: collapseComments,
            onDismissGestureEnded: handleCommentsDismissGestureEnded
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

    private func expandComments() {
        if isCommentsPageAvailable {
            // Route to the comments page instead of the overlay
            withAnimation(.smooth(duration: 0.3)) {
                selectedPage = .comments
            }
            return
        }
        // Use same animation as player sheet expand (0.3s, no bounce)
        withAnimation(.smooth(duration: 0.3)) {
            isCommentsExpanded = true
        }
    }

    private func collapseComments() {
        appEnvironment?.navigationCoordinator.commentsFrame = .zero
        // Use same animation as player sheet dismiss (0.3s, no bounce)
        withAnimation(.smooth(duration: 0.3)) {
            isCommentsExpanded = false
        }
    }

    private func handleCommentsDismissGestureEnded(_ finalOffset: CGFloat) {
        let dismissThreshold: CGFloat = 30
        if finalOffset >= dismissThreshold {
            collapseComments()
        }
        // Below threshold - scroll view will rubber-band back naturally
    }
}

#endif
