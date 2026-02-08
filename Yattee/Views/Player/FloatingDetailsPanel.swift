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
    let onPinToggle: () -> Void
    let onAlignmentToggle: () -> Void
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

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var isCommentsExpanded: Bool = false
    @State private var showFormattedDate = false
    @State private var showOriginalTitle = false
    @State private var scrollOffset: CGFloat = 0
    @State private var panelHeight: CGFloat = 0
    @State private var scrollToTopTrigger: Bool = false
    @State private var showQueueSheet: Bool = false
    @State private var showPlaylistSheet: Bool = false
    @State private var isDragHandleActive: Bool = false

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
    private var accentColor: Color { settingsManager?.accentColor.color ?? .accentColor }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }

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

    // Player pill helpers
    private var playerPillSettings: PlayerPillSettings {
        playerControlsLayout.effectivePlayerPillSettings
    }
    private var shouldShowPlayerPill: Bool {
        playerPillSettings.visibility.isVisible(isWideLayout: true) &&
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

    /// Returns the first enabled Yattee Server instance URL, if any.
    private var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    /// Returns the DeArrow title if available and enabled.
    private func deArrowTitle(for video: Video) -> String? {
        appEnvironment?.deArrowBrandingProvider.title(for: video)
    }

    /// Returns the display title based on toggle state.
    private func displayTitle(for video: Video) -> String {
        if let deArrow = deArrowTitle(for: video) {
            return showOriginalTitle ? video.title : deArrow
        }
        return video.title
    }

    /// Whether the title can be toggled (DeArrow title is available).
    private func canToggleTitle(for video: Video) -> Bool {
        deArrowTitle(for: video) != nil
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
        .animation(.easeInOut(duration: 0.25), value: isPinned)
        .onChange(of: video.id) { _, _ in
            // Comments state is managed by parent - just reset local state
            showOriginalTitle = false
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
            PanelPinButton(
                isPinned: isPinned,
                panelSide: panelSide,
                onPinToggle: onPinToggle,
                isDragHandleActive: $isDragHandleActive
            )
            .offset(y: -65)
            .zIndex(10) // Ensure pin button appears above panel content
        }
        .overlay(alignment: .center) {
            PanelAlignmentButton(
                panelSide: panelSide,
                onAlignmentToggle: onAlignmentToggle,
                isDragHandleActive: $isDragHandleActive
            )
            .offset(y: 65)
            .zIndex(10)
        }
        .zIndex(10) // Ensure grabber overlay appears above panel
    }

    @ViewBuilder
    private func panelContent(video: Video) -> some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Scroll offset tracker at top
                        Color.clear
                            .frame(height: 0)
                            .id("panelTop")
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .named("panelScroll")).origin.y) { _, newValue in
                                            scrollOffset = -newValue
                                        }
                                }
                            )

                        videoInfo(video)

                        Divider()
                            .padding(.horizontal)

                        infoTabSection(video)
                    }
                }
                .coordinateSpace(name: "panelScroll")
                .onChange(of: scrollToTopTrigger) { _, _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("panelTop", anchor: .top)
                    }
                }
            }
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
        .overlay { expandedCommentsOverlay(video: video) }
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
    }

    // MARK: - Video Info

    private func videoInfo(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title - full width
            Text(displayTitle(for: video))
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(3)
                .onTapGesture {
                    if canToggleTitle(for: video) {
                        showOriginalTitle.toggle()
                    }
                }

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
        .padding()
    }

    // MARK: - Info Tab Section

    private func infoTabSection(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description only (no picker)
            descriptionContent(video.description ?? "")

            // Extra space at bottom so content can scroll above the comments pill
            Spacer()
                .frame(height: 80)
        }
        .padding(.vertical)
    }

    private func expandComments() {
        // Use same animation as player sheet expand (0.3s, no bounce)
        withAnimation(.smooth(duration: 0.3)) {
            isCommentsExpanded = true
        }
    }

    private func collapseComments() {
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
            } else {
                Text(String(localized: "player.noDescription"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - Panel Resize Grabber

/// A draggable handle for resizing the panel width.
private struct PanelResizeGrabber: View {
    @Binding var panelWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let panelSide: FloatingPanelSide
    let isPinned: Bool
    @Binding var isDragActive: Bool

    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat? = nil
    @State private var dragStartLocation: CGFloat? = nil
    #if os(macOS)
    @State private var isHovering = false
    #endif

    /// Width of the grabber hit area
    private static let grabberHitWidth: CGFloat = 20

    /// Grabber fill color - needs to be visible against both light (pinned) and dark (floating) backgrounds
    private var grabberColor: Color {
        // When pinned (light background), use a darker gray for visibility
        // When floating (dark background), use lighter color
        let baseColor = isPinned ? Color.gray : Color.secondary
        let isActive = isDragging
        return baseColor.opacity(isActive ? 1.0 : (isPinned ? 0.5 : 0.6))
    }

    var body: some View {
        // Full-height container for expanded hit area
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.grabberHitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                // Visual pill indicator (centered)
                RoundedRectangle(cornerRadius: 3)
                    .fill(grabberColor)
                    .frame(width: 6, height: 40)
            }
            .gesture(dragGesture)
            #if os(macOS)
            .onHover { hovering in
                isHovering = hovering
                isDragActive = hovering || isDragging
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            #endif
            .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                // Capture initial state on first drag event
                if dragStartWidth == nil {
                    dragStartWidth = panelWidth
                    dragStartLocation = value.location.x
                }

                isDragging = true
                isDragActive = true

                guard let startWidth = dragStartWidth,
                      let startLocation = dragStartLocation else { return }

                // Calculate delta from absolute finger position (not translation)
                let locationDelta = value.location.x - startLocation

                // Apply delta based on panel side
                let delta: CGFloat
                if panelSide == .right {
                    delta = -locationDelta
                } else {
                    delta = locationDelta
                }

                let newWidth = startWidth + delta
                panelWidth = min(max(newWidth, minWidth), maxWidth)
            }
            .onEnded { _ in
                dragStartWidth = nil
                dragStartLocation = nil
                isDragging = false
                #if os(macOS)
                isDragActive = isHovering
                #else
                isDragActive = false
                #endif
            }
    }
}

#endif
