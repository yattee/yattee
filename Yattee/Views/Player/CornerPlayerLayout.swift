//
//  CornerPlayerLayout.swift
//  Yattee
//
//  Corner player layout for iPad/macOS: video in the top-left, the portrait-
//  style info panel below it, and a resizable side column on the right with
//  tabs for the remaining pages (related/chapters/queue/comments) —
//  YouTube-style. The layout resolver in ExpandedPlayerSheet falls back to
//  the stacked layout when the window is too narrow.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct CornerPlayerLayout<PlayerContent: View>: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let playerControlsLayout: PlayerControlsLayout

    /// Video + controls area builder, sized by the layout.
    @ViewBuilder let playerContent: (
        _ onTogglePanel: @escaping () -> Void,
        _ isPanelVisible: Bool,
        _ width: CGFloat,
        _ height: CGFloat
    ) -> PlayerContent

    let onChannelTap: (() -> Void)?
    var onFullscreen: (() -> Void)? = nil

    /// Seed the panel visibility BEFORE the first frame — applying the
    /// preset's default visibility via onAppear/onChange animates the panels
    /// popping in over an initially full-screen video on player expand
    /// (same trap the portrait panel hit, fixed by init-time seeding).
    init(
        playerControlsLayout: PlayerControlsLayout,
        initialPanelVisible: Bool = true,
        initialColumnWidth: CGFloat? = nil,
        @ViewBuilder playerContent: @escaping (
            _ onTogglePanel: @escaping () -> Void,
            _ isPanelVisible: Bool,
            _ width: CGFloat,
            _ height: CGFloat
        ) -> PlayerContent,
        onChannelTap: (() -> Void)?,
        onFullscreen: (() -> Void)? = nil
    ) {
        self.playerControlsLayout = playerControlsLayout
        self.playerContent = playerContent
        self.onChannelTap = onChannelTap
        self.onFullscreen = onFullscreen
        _isPanelVisible = State(initialValue: initialPanelVisible)
        if let initialColumnWidth, initialColumnWidth > 0 {
            _columnWidth = State(initialValue: initialColumnWidth)
        }
    }

    // MARK: - Layout Constants

    /// Side column width bounds.
    static var minColumnWidth: CGFloat { 280 }
    static var maxColumnWidthCap: CGFloat { 560 }
    /// Minimum width kept for the video column.
    static var minVideoColumnWidth: CGFloat { 480 }
    /// Maximum fraction of the window height the video area may take when a
    /// below-video region needs space.
    static var maxVideoHeightFraction: CGFloat { 0.72 }

    // MARK: - State

    @State private var isPanelVisible = true
    @State private var columnWidth: CGFloat = SettingsManager.defaultCornerPanelColumnWidth
    @State private var primaryPage: PanelPageType = .related
    @State private var isGrabberActive = false
    @State private var isBelowPanelVisible = true
    @State private var belowPanelDragOffset: CGFloat = 0
    @State private var isBelowPanelExpanded = false
    @State private var belowPanelExpandOffset: CGFloat = 0
    /// Swipe-up-on-video reveal in progress: the panel renders in the shown
    /// layout, positioned by `belowPanelDragOffset` counting down from full
    /// hide travel so it follows the finger.
    @State private var isRevealDragActive = false

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
    /// Suppresses the leaf-level .animation modifiers while a panel drag
    /// tracks the finger (the host sheet strips withAnimation transactions,
    /// so these modifiers are what actually animate releases — like portrait).
    private var isPanelDragActive: Bool { appEnvironment?.navigationCoordinator.isPanelDragging ?? false }
    private var playerState: PlayerState? { appEnvironment?.playerService.state }
    private var video: Video? { playerState?.currentVideo }
    private var accentColor: Color { settingsManager?.resolvedAccentColor ?? .accentColor }

    private var panelSettings: PanelSettings {
        playerControlsLayout.effectivePanelSettings
    }

    /// Whether the info page is assigned to (and enabled in) the below-video
    /// region — the below panel only exists to host it.
    private var hasBelowVideoInfo: Bool {
        guard let info = panelSettings.configuration(for: .info) else { return false }
        return info.isEnabled && info.region == .belowVideo
    }

    /// Comments assigned below the video render as the portrait panel's
    /// comments pill (iOS only, and only while the info panel is below —
    /// the pill lives inside it). Everything else falls back to the column.
    private var hasBelowVideoComments: Bool {
        #if os(iOS)
        guard hasBelowVideoInfo,
              let comments = panelSettings.configuration(for: .comments) else { return false }
        return comments.isEnabled && comments.region == .belowVideo
        #else
        return false
        #endif
    }

    /// Pages the below-video host actually renders. Enabled pages assigned
    /// `.belowVideo` that it can't host (chapters/related/queue/tracks, or
    /// comments without the info panel) fall back to the side column instead
    /// of disappearing.
    private var belowVideoPageTypes: Set<PanelPageType> {
        var types: Set<PanelPageType> = []
        if hasBelowVideoInfo { types.insert(.info) }
        if hasBelowVideoComments { types.insert(.comments) }
        return types
    }

    /// Column emptiness is decided at the config level: runtime-empty pages
    /// (no chapters, no related yet) are hidden inside the panel content, not
    /// by collapsing the column — layout jumps during loading would be jarring.
    private var hasSideColumn: Bool {
        panelSettings.enabledPages().contains { !belowVideoPageTypes.contains($0.pageType) }
    }

    /// The info page config drives the below-video panel's element settings.
    private var infoPageSettings: InfoPageSettings {
        panelSettings.pages.first { $0.pageType == .info }?.infoSettings ?? InfoPageSettings()
    }

    private var panelBackgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private func clampColumnWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let maxWidth = max(
            Self.minColumnWidth,
            min(Self.maxColumnWidthCap, availableWidth * 0.45, availableWidth - Self.minVideoColumnWidth)
        )
        return min(max(width, Self.minColumnWidth), maxWidth)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let height = max(1, geometry.size.height)

            let showsSideColumn = isPanelVisible && hasSideColumn
            let showsBelowVideo = isPanelVisible && isBelowPanelVisible && hasBelowVideoInfo

            let effectiveColumnWidth = clampColumnWidth(columnWidth, availableWidth: width)
            // Grabber sits on the column's leading edge, inside the column
            // background — narrow strip matching the panel drag handle look.
            let grabberWidth: CGFloat = 12
            let totalColumnWidth = effectiveColumnWidth + grabberWidth

            let videoWidth = showsSideColumn ? max(1, width - totalColumnWidth) : width
            let shownVideoHeight: CGFloat = {
                let rawAspectRatio = playerState?.displayAspectRatio ?? (16.0 / 9.0)
                let aspectRatio = rawAspectRatio > 0 ? rawAspectRatio : (16.0 / 9.0)
                return max(1, min(videoWidth / aspectRatio, height * Self.maxVideoHeightFraction))
            }()
            // Reveal drag renders the shown layout so the panel can follow
            // the finger while `isBelowPanelVisible` is still false.
            let showsPanelLayout = showsBelowVideo || (isPanelVisible && isRevealDragActive)

            // Panel travel needed to fully clear the screen (incl. bottom
            // safe area + the player window's extra PiP inset), and the video
            // recenter offset that follows the drag — like the portrait
            // layout's videoYOffset. At full travel the offset video matches
            // the centered full-height layout exactly, so the state flips
            // after the hide/reveal animations cause no visible jump.
            let bottomInset = geometry.safeAreaInsets.bottom
            let fullColumnHeight = height + bottomInset
            // With the below panel hidden the video (and its bottom controls)
            // extends to the physical bottom edge, not the safe-area line.
            let videoHeight = showsPanelLayout ? shownVideoHeight : fullColumnHeight
            let normalPanelHeight = max(1, fullColumnHeight - shownVideoHeight)
            let panelHideTravel = normalPanelHeight

            // One shared duration for the whole panel toggle — both panels
            // and both video dimensions animate in lockstep so the video
            // corner grows diagonally and everything finishes together.
            // Scaled to the larger travel so the speed stays reasonable.
            let panelExitSpeed: CGFloat = 1400
            let panelToggleDuration = Double(min(max(max(totalColumnWidth, normalPanelHeight) / panelExitSpeed, 0.25), 0.45))
            let videoDragProgress = showsPanelLayout
                ? min(1.0, max(0, belowPanelDragOffset) / panelHideTravel)
                : 0
            let videoDragYOffset = (fullColumnHeight - shownVideoHeight) / 2 * videoDragProgress

            // Portrait-style expand: dragging up grows the panel over the
            // video (expandOffset is negative while dragging up; when
            // expanded, positive while dragging down to collapse).
            let panelHeight: CGFloat = {
                if isBelowPanelExpanded {
                    return max(normalPanelHeight, fullColumnHeight - belowPanelExpandOffset)
                }
                return min(fullColumnHeight, normalPanelHeight - belowPanelExpandOffset)
            }()
            let panelSpacerHeight: CGFloat = {
                if isBelowPanelExpanded {
                    return min(videoHeight, belowPanelExpandOffset)
                }
                return max(0, videoHeight + belowPanelExpandOffset)
            }()

            ZStack {
                Color.black.ignoresSafeArea(.all)

                HStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        // Sized from the live (animated) geometry, not the
                        // target values — during panel toggles the video then
                        // resizes smoothly through every animation frame
                        // instead of snapping to the final size.
                        GeometryReader { videoProxy in
                            playerContent(
                                togglePanel,
                                isPanelVisible,
                                max(1, videoProxy.size.width),
                                max(1, videoProxy.size.height)
                            )
                        }
                        // Height animates with the below-panel timing, width
                        // with the side-column timing — the inner .animation
                        // scopes only the height frame. Keyed to gesture/
                        // visibility state, NOT to derived geometry — appear
                        // settling must not animate.
                        .frame(height: videoHeight)
                        .animation(isPanelDragActive ? nil : .easeInOut(duration: panelToggleDuration), value: isPanelVisible)
                        .animation(isPanelDragActive ? nil : .easeInOut(duration: panelToggleDuration), value: isBelowPanelVisible)
                        .frame(width: videoWidth)
                        .animation(isPanelDragActive ? nil : .easeInOut(duration: panelToggleDuration), value: isPanelVisible)
                        .clipped()
                        .offset(y: videoDragYOffset)
                        .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: videoDragYOffset)
                        // Aspect ratio changes (new video, stream switch)
                        // resize the video/panel split — animate them
                        .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: playerState?.displayAspectRatio)
                        // Swipe up on the video to bring the panel back —
                        // the panel follows the finger (like the portrait
                        // reveal) via belowPanelDragOffset counting down
                        // from full hide travel.
                        .simultaneousGesture(
                            (isPanelVisible && !isBelowPanelVisible && hasBelowVideoInfo)
                                ? DragGesture()
                                    .onChanged { value in
                                        guard appEnvironment?.navigationCoordinator.isAdjustingPlayerSliders != true else { return }
                                        guard value.translation.height < 0 || isRevealDragActive else { return }
                                        if appEnvironment?.navigationCoordinator.isPanelDragging != true {
                                            appEnvironment?.navigationCoordinator.isPanelDragging = true
                                        }
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            isRevealDragActive = true
                                            belowPanelDragOffset = min(panelHideTravel, max(0, panelHideTravel + value.translation.height))
                                        }
                                    }
                                    .onEnded { value in
                                        guard isRevealDragActive else { return }
                                        appEnvironment?.navigationCoordinator.isPanelDragging = false
                                        if value.translation.height < -80 || value.predictedEndTranslation.height < -160 {
                                            // Revealing: flip to visible at the
                                            // current position, then animate home
                                            var transaction = Transaction()
                                            transaction.disablesAnimations = true
                                            withTransaction(transaction) {
                                                isBelowPanelVisible = true
                                                isRevealDragActive = false
                                            }
                                            withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                                belowPanelDragOffset = 0
                                            }
                                        } else {
                                            // Snap back off-screen, then drop the
                                            // reveal layout without animation
                                            withAnimation(.spring(response: 0.3, dampingFraction: 1.0), completionCriteria: .logicallyComplete) {
                                                belowPanelDragOffset = panelHideTravel
                                            } completion: {
                                                var transaction = Transaction()
                                                transaction.disablesAnimations = true
                                                withTransaction(transaction) {
                                                    isRevealDragActive = false
                                                    belowPanelDragOffset = 0
                                                }
                                            }
                                        }
                                    }
                                : nil
                        )
                        .frame(maxHeight: .infinity, alignment: .top)

                        if showsPanelLayout, let video {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                    .frame(height: panelSpacerHeight)

                                belowVideoInfoPanel(video: video, hideTravel: panelHideTravel)
                                    .frame(width: videoWidth)
                                    .frame(height: panelHeight)
                                    .offset(y: belowPanelDragOffset)
                            }
                            .frame(maxHeight: .infinity, alignment: .top)
                            .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: belowPanelDragOffset)
                            .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isBelowPanelExpanded)
                            .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: belowPanelExpandOffset)
                            .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: playerState?.displayAspectRatio)
                            // Pure slide, no fade — with a fade the panel
                            // seems to vanish before the side column and the
                            // video resize, breaking the one-transition feel
                            .transition(.move(edge: .bottom).animation(.easeInOut(duration: panelToggleDuration)))
                        }
                    }
                    .frame(width: videoWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    // Extend into the bottom safe area (incl. the player
                    // window's extra PiP inset) so the panel and its pills
                    // reach the true bottom edge
                    .ignoresSafeArea(edges: .bottom)

                    if showsSideColumn, let video {
                        HStack(spacing: 0) {
                            PanelResizeGrabber(
                                panelWidth: $columnWidth,
                                minWidth: Self.minColumnWidth,
                                maxWidth: clampColumnWidth(.infinity, availableWidth: width),
                                panelSide: .right,
                                isPinned: true,
                                isDragActive: $isGrabberActive,
                                hitWidth: grabberWidth
                            )

                            sideColumnPanel(video: video)
                                .frame(width: effectiveColumnWidth)
                        }
                        // Bottom only — the background must not run under
                        // the system status bar at the top
                        .background(panelBackgroundColor.ignoresSafeArea(edges: .bottom))
                        .transition(.move(edge: .trailing).animation(.easeInOut(duration: panelToggleDuration)))
                    }
                }
                // Container-level animation so panel insert/remove and the
                // video-area resize play as one transition (the host sheet
                // strips withAnimation transactions, so key it here)
                .animation(isPanelDragActive ? nil : .easeInOut(duration: panelToggleDuration), value: isPanelVisible)
                .animation(isPanelDragActive ? nil : .easeInOut(duration: panelToggleDuration), value: isBelowPanelVisible)
            }
            .onChange(of: width) { _, newWidth in
                // Re-clamp when the window shrinks (still above the corner
                // threshold — below it the resolver switches layouts).
                columnWidth = clampColumnWidth(columnWidth, availableWidth: newWidth)
            }
        }
        .onAppear {
            // Only sync from the setting once the session's default
            // visibility was applied — before that the setting is stale
            // (the init seed already resolved the correct initial value).
            if appEnvironment?.navigationCoordinator.hasAppliedPanelDefaultVisibility == true,
               let visible = settingsManager?.landscapeDetailsPanelVisible {
                isPanelVisible = visible
            }
            // Default the side column to the first configured page (skipping
            // pages hosted below the video).
            if let first = panelSettings.enabledPages().first(where: { !belowVideoPageTypes.contains($0.pageType) })?.pageType {
                primaryPage = first
            }
        }
        .onChange(of: columnWidth) { _, newWidth in
            settingsManager?.cornerPanelColumnWidth = newWidth
        }
        .onChange(of: settingsManager?.landscapeDetailsPanelVisible) { _, newValue in
            // External writes (preset default visibility, other layout hosts)
            // must reach the local state too.
            guard let newValue, newValue != isPanelVisible else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isPanelVisible = newValue
            }
        }
    }

    // MARK: - Panels

    /// Portrait-style panel below the video: the actual PortraitDetailsPanel
    /// (drag handle, player pill, collapsible description) with the comments
    /// pill hidden and no inline chapters/related — those live in the side
    /// column tabs.
    @ViewBuilder
    private func belowVideoInfoPanel(video: Video, hideTravel: CGFloat) -> some View {
        Group {
            #if os(iOS)
            PortraitDetailsPanel(
                onChannelTap: onChannelTap,
                playerControlsLayout: playerControlsLayout,
                onFullscreen: onFullscreen,
                pillsOverlayOpacity: 1,
                hidesCommentsPill: !hasBelowVideoComments,
                inlineInfoSections: false,
                panelCornerRadius: 0,
                onDragChanged: { offset in
                    if appEnvironment?.navigationCoordinator.isPanelDragging != true {
                        appEnvironment?.navigationCoordinator.isPanelDragging = true
                    }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if isBelowPanelExpanded {
                            // When expanded, only track drag down to collapse
                            belowPanelExpandOffset = max(0, offset)
                        } else if offset < 0 {
                            // Dragging UP - expand panel over the video
                            belowPanelExpandOffset = offset
                            belowPanelDragOffset = 0
                        } else {
                            // Dragging DOWN - dismiss tracking
                            belowPanelDragOffset = offset
                            belowPanelExpandOffset = 0
                        }
                    }
                },
                onDragEnded: { offset, predicted in
                    appEnvironment?.navigationCoordinator.isPanelDragging = false
                    if isBelowPanelExpanded {
                        if offset > 80 || predicted > 160 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                isBelowPanelExpanded = false
                                belowPanelExpandOffset = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                belowPanelExpandOffset = 0
                            }
                        }
                    } else if offset < -80 || predicted < -160 {
                        // Expand panel to cover the video
                        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                            isBelowPanelExpanded = true
                            belowPanelExpandOffset = 0
                            belowPanelDragOffset = 0
                        }
                    } else if offset > 80 || predicted > 160 {
                        // Slide the panel fully off (video recenters via the
                        // drag-progress offset), then flip the hidden state
                        // without animation — the offset layout at full
                        // travel matches the hidden layout exactly.
                        withAnimation(.spring(response: 0.3, dampingFraction: 1.0), completionCriteria: .logicallyComplete) {
                            belowPanelDragOffset = hideTravel
                        } completion: {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                isBelowPanelVisible = false
                                isBelowPanelExpanded = false
                                belowPanelDragOffset = 0
                            }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            belowPanelDragOffset = 0
                            belowPanelExpandOffset = 0
                        }
                    }
                },
                onDragCancelled: {
                    appEnvironment?.navigationCoordinator.isPanelDragging = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        belowPanelDragOffset = 0
                        belowPanelExpandOffset = 0
                    }
                }
            )
            #else
            // macOS: static info panel, no drag-to-hide
            InfoPanelPage(
                context: PanelPageContext(
                    appEnvironment: appEnvironment,
                    video: video,
                    accentColor: accentColor,
                    onChannelTap: onChannelTap
                ),
                settings: infoPageSettings,
                scrollConfig: PanelScrollConfig(
                    topInset: 4,
                    bottomInset: 16
                )
            )
            .background(panelBackgroundColor.ignoresSafeArea(edges: .vertical))
            #endif
        }
        // Publish the panel frame so the window-level dismiss pan gesture
        // doesn't begin from touches inside this panel (drag handle conflict)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                        appEnvironment?.navigationCoordinator.cornerBelowPanelFrame = frame
                    }
                    .onDisappear {
                        appEnvironment?.navigationCoordinator.cornerBelowPanelFrame = .zero
                        appEnvironment?.navigationCoordinator.isPanelDragging = false
                    }
            }
        }
    }

    /// Side column with tabs for every enabled page the below-video host
    /// doesn't render.
    @ViewBuilder
    private func sideColumnPanel(video: Video) -> some View {
        PlayerPanelContentView(
            panelSettings: panelSettings,
            selectedPage: $primaryPage,
            context: PanelPageContext(
                appEnvironment: appEnvironment,
                video: video,
                accentColor: accentColor,
                onChannelTap: onChannelTap
            ),
            scrollConfig: PanelScrollConfig(
                topInset: 4,
                bottomInset: 16
            ),
            pageBarTopPadding: 8,
            excludedPages: belowVideoPageTypes
        )
        .background(panelBackgroundColor.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Actions

    private func togglePanel() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isPanelVisible.toggle()
            settingsManager?.landscapeDetailsPanelVisible = isPanelVisible
            settingsManager?.detailsPanelLastVisible = isPanelVisible
        }
    }
}

#endif
