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

    /// Resize grabber strip on the side column's leading edge — narrow,
    /// matching the panel drag handle look.
    static var grabberWidth: CGFloat { 12 }
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
    /// The below panel is layered under the video (the video grows over it
    /// to hide) except while it expands over the video. Flipped only when
    /// the panel sits at its home geometry — never mid-spring — so the
    /// z-order swap is never visible.
    @State private var isBelowPanelRaised = false
    /// Swipe-up-on-video reveal in progress: the panel renders in the shown
    /// layout, positioned by `belowPanelDragOffset` counting down from full
    /// hide travel so it follows the finger.
    @State private var isRevealDragActive = false
    /// Side column collapsed by overdragging its resize grabber past the
    /// minimum width — independent of `isPanelVisible`, like the below panel.
    @State private var isSideColumnVisible = true
    /// Overdrag travel of the side column toward the trailing edge (0 = home).
    @State private var sideColumnDragOffset: CGFloat = 0
    @State private var isSideColumnOverdragActive = false
    /// Edge-swipe reveal in progress: the column renders in the shown layout,
    /// positioned by `sideColumnDragOffset` counting down from full travel.
    @State private var isSideColumnRevealDragActive = false
    /// Bumped by the animated show/hide paths (toggle button, settings sync).
    /// The visibility-driven `.animation` modifiers key on this instead of the
    /// visibility flags themselves: drag hide/reveal flips those flags in a
    /// disabled transaction, but `.animation(_:value:)` ignores that and would
    /// still animate the frame height — an animation a quick follow-up swipe
    /// then interrupts, leaving the video clipped to a shrunken box that
    /// springs back (the "fast swipe" reveal glitch).
    @State private var panelToggleGeneration = 0
    /// Status bar height captured while the bar is visible. The layout
    /// ignores the top safe area and pads by this fixed amount instead, so
    /// hiding the bar in the fullscreen state (safe area → 0) doesn't
    /// reflow the panels mid-transition; only the video grows into the
    /// strip.
    @State private var stableTopInset: CGFloat = 0
    #if os(iOS)
    @Environment(\.statusBarVisibilityController) private var statusBarController
    #endif

    /// Trailing screen-edge strip that starts the reveal swipe while the
    /// column is collapsed; drags from anywhere else keep seeking.
    static var sideColumnEdgeRevealInset: CGFloat { 20 }

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
        GeometryReader { outer in
            let liveTopInset = outer.safeAreaInsets.top
            #if os(iOS)
            let knownTopInset = statusBarController?.knownStatusBarHeight ?? 0
            #else
            let knownTopInset: CGFloat = 0
            #endif
            let topInset = liveTopInset > 0 ? liveTopInset : max(stableTopInset, knownTopInset)

            layout(topInset: topInset)
                .padding(.top, topInset)
                .ignoresSafeArea(edges: .top)
                .onChange(of: liveTopInset, initial: true) { _, inset in
                    if inset > 0 { stableTopInset = inset }
                }
        }
        .background(Color.black.ignoresSafeArea(.all))
    }

    @ViewBuilder
    private func layout(topInset: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let height = max(1, geometry.size.height)

            let showsSideColumn = isPanelVisible && isSideColumnVisible && hasSideColumn
            let isSideColumnCollapsed = isPanelVisible && !isSideColumnVisible && hasSideColumn
            let showsBelowVideo = isPanelVisible && isBelowPanelVisible && hasBelowVideoInfo
            // What the player actually sees: every region can be dragged
            // away on its own while the panel stays nominally visible.
            let showsAnyRegion = showsSideColumn || showsBelowVideo

            let effectiveColumnWidth = clampColumnWidth(columnWidth, availableWidth: width)
            // Grabber sits on the column's leading edge, inside the column
            // background — narrow strip matching the panel drag handle look.
            let grabberWidth = Self.grabberWidth
            let totalColumnWidth = effectiveColumnWidth + grabberWidth

            // Panels never move. Both sit at their home positions (column on
            // the trailing edge, info panel under the shown video) and the
            // video — layered above them — grows over them to hide and
            // shrinks back to reveal. Every hide/reveal (button, grabber
            // overdrag, panel handle, swipe-up/edge-swipe reveal) drives the
            // video's trailing/bottom edge, never a panel offset.
            let shownVideoWidth = hasSideColumn ? max(1, width - totalColumnWidth) : width

            // Column hide travel: how far the video's trailing edge grows to
            // cover the column. `sideColumnDragOffset` counts 0 → travel
            // while hiding and travel → 0 while revealing. At full travel
            // the dragged geometry matches the hidden geometry exactly, so
            // the state flips after the animations cause no visible jump.
            let sideColumnHideTravel = totalColumnWidth
            // Column geometry ignores the panel toggle on purpose: the
            // below panel's home (width + top) follows the column state —
            // it widens over the column's lower part in lockstep with the
            // video when the column is dragged away — but must stay put
            // while the toggle grows the video over everything.
            let hasSideColumnLayout = hasSideColumn && (isSideColumnVisible || isSideColumnRevealDragActive)
            let sideColumnSlide = hasSideColumnLayout ? min(sideColumnHideTravel, max(0, sideColumnDragOffset)) : 0
            let columnVideoWidth = hasSideColumnLayout ? min(width, shownVideoWidth + sideColumnSlide) : width
            let videoWidth = isPanelVisible ? columnVideoWidth : width
            let shownVideoHeight: CGFloat = {
                let rawAspectRatio = playerState?.displayAspectRatio ?? (16.0 / 9.0)
                let aspectRatio = rawAspectRatio > 0 ? rawAspectRatio : (16.0 / 9.0)
                return max(1, min(columnVideoWidth / aspectRatio, height * Self.maxVideoHeightFraction))
            }()
            // Reveal drag renders the shown geometry so the video's bottom
            // edge can follow the finger while `isBelowPanelVisible` is
            // still false.
            let showsPanelLayout = showsBelowVideo || (isPanelVisible && isRevealDragActive)

            // Below-panel hide travel: the video's bottom edge grows from the
            // shown height to the physical bottom edge (incl. bottom safe
            // area + the player window's extra PiP inset). Same offset
            // convention as the column.
            let bottomInset = geometry.safeAreaInsets.bottom
            let fullColumnHeight = height + bottomInset
            let normalPanelHeight = max(1, fullColumnHeight - shownVideoHeight)
            let panelHideTravel = normalPanelHeight
            let belowPanelSlide = showsPanelLayout ? min(panelHideTravel, max(0, belowPanelDragOffset)) : 0
            // With the below panel hidden the video (and its bottom controls)
            // extends to the physical bottom edge, not the safe-area line.
            let videoHeight = showsPanelLayout ? min(fullColumnHeight, shownVideoHeight + belowPanelSlide) : fullColumnHeight
            // Fullscreen state: the status bar is hidden, so the video also
            // grows up into the fixed status bar strip above the layout.
            let videoTopExtension: CGFloat = isPanelVisible ? 0 : topInset

            // One shared duration for the whole panel toggle — both video
            // dimensions animate in lockstep so the video corner grows
            // diagonally over the panels and everything finishes together.
            // Scaled to the larger travel so the speed stays reasonable.
            let panelExitSpeed: CGFloat = 1400
            let panelToggleDuration = Double(min(max(max(totalColumnWidth, normalPanelHeight) / panelExitSpeed, 0.25), 0.45))

            // Portrait-style expand: dragging up grows the panel over the
            // video (expandOffset is negative while dragging up; when
            // expanded, positive while dragging down to collapse). The
            // panel's home top is the shown video height — the video's live
            // height only matters for hide/reveal, which never overlap an
            // expand.
            let panelHeight: CGFloat = {
                if isBelowPanelExpanded {
                    return max(normalPanelHeight, fullColumnHeight - belowPanelExpandOffset)
                }
                return min(fullColumnHeight, normalPanelHeight - belowPanelExpandOffset)
            }()
            let panelSpacerHeight: CGFloat = {
                if isBelowPanelExpanded {
                    return min(shownVideoHeight, belowPanelExpandOffset)
                }
                return max(0, shownVideoHeight + belowPanelExpandOffset)
            }()

            ZStack(alignment: .topLeading) {
                // Side column — pinned to the trailing edge, never moves.
                // Stays in the hierarchy while hidden (covered by the video)
                // so its scroll position and loaded content survive toggles.
                if hasSideColumn, let video {
                    HStack(spacing: 0) {
                        PanelResizeGrabber(
                            panelWidth: $columnWidth,
                            minWidth: Self.minColumnWidth,
                            maxWidth: clampColumnWidth(.infinity, availableWidth: width),
                            panelSide: .right,
                            isPinned: true,
                            isDragActive: $isGrabberActive,
                            hitWidth: grabberWidth,
                            // A covered grabber must not block the window
                            // dismiss pan from starting over its strip
                            publishesFrame: showsSideColumn,
                            onOverdragChanged: { overshoot in
                                guard overshoot > 0 || isSideColumnOverdragActive else { return }
                                if appEnvironment?.navigationCoordinator.isPanelDragging != true {
                                    appEnvironment?.navigationCoordinator.isPanelDragging = true
                                }
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    isSideColumnOverdragActive = true
                                    sideColumnDragOffset = min(sideColumnHideTravel, overshoot)
                                }
                            },
                            onOverdragEnded: { overshoot, predicted in
                                guard isSideColumnOverdragActive else { return }
                                isSideColumnOverdragActive = false
                                appEnvironment?.navigationCoordinator.isPanelDragging = false
                                if overshoot > 80 || predicted > 160 {
                                    // Grow the video fully over the column,
                                    // then flip the collapsed state without
                                    // animation — like the below panel's
                                    // hide. `.removed`, not
                                    // `.logicallyComplete`: flipping while
                                    // the spring is still registered on the
                                    // video frame leaves a stale animation
                                    // that a quick follow-up reveal swipe
                                    // interrupts, and the release spring
                                    // then starts from a bogus shrunken
                                    // rect (video clipped, growing back).
                                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0), completionCriteria: .removed) {
                                        sideColumnDragOffset = sideColumnHideTravel
                                    } completion: {
                                        // The grabber may have been picked up again
                                        guard isSideColumnVisible, !isSideColumnOverdragActive,
                                              sideColumnDragOffset == sideColumnHideTravel else { return }
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            isSideColumnVisible = false
                                            sideColumnDragOffset = 0
                                        }
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        sideColumnDragOffset = 0
                                    }
                                }
                            }
                        )

                        sideColumnPanel(video: video)
                            .frame(width: effectiveColumnWidth)
                    }
                    // Bottom only — the background must not run under
                    // the system status bar at the top
                    .background(panelBackgroundColor.ignoresSafeArea(edges: .bottom))
                    .frame(width: totalColumnWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(showsSideColumn)
                    .accessibilityHidden(!showsSideColumn)
                }

                // Below-video panel — home is directly under the shown video.
                // Its width follows the column geometry only (it covers the
                // column's lower part when the column is dragged away, in
                // lockstep with the video covering the upper part) and stays
                // put during the panel toggle. Its own handle drag slides it
                // off the bottom with the video growing in lockstep (the
                // edges coincide) — a drag on the panel should move the
                // panel. Raised above the video only while expanded over it;
                // otherwise the video covers it.
                if hasBelowVideoInfo, let video {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                            .frame(height: panelSpacerHeight)

                        belowVideoInfoPanel(video: video, hideTravel: panelHideTravel, publishesFrame: showsBelowVideo)
                            .frame(width: columnVideoWidth)
                            .frame(height: panelHeight)
                            .offset(y: belowPanelSlide)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // Extend into the bottom safe area (incl. the player
                    // window's extra PiP inset) so the panel and its pills
                    // reach the true bottom edge
                    .ignoresSafeArea(edges: .bottom)
                    .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: belowPanelDragOffset)
                    .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isBelowPanelExpanded)
                    .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: belowPanelExpandOffset)
                    .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: playerState?.displayAspectRatio)
                    .animation(isPanelDragActive ? nil : .easeInOut(duration: panelToggleDuration), value: panelToggleGeneration)
                    .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: sideColumnDragOffset)
                    .zIndex(isBelowPanelRaised ? 2 : 0)
                    .allowsHitTesting(showsBelowVideo)
                    .accessibilityHidden(!showsBelowVideo)
                }

                // Video — layered above the panels; its frame is the only
                // thing that moves during hide/reveal.
                // Sized from the live (animated) geometry, not the target
                // values — during panel toggles the video then resizes
                // smoothly through every animation frame instead of snapping
                // to the final size.
                GeometryReader { videoProxy in
                    playerContent(
                        togglePanel,
                        showsAnyRegion,
                        max(1, videoProxy.size.width),
                        max(1, videoProxy.size.height)
                    )
                }
                .frame(width: videoWidth, height: videoHeight + videoTopExtension)
                .offset(y: -videoTopExtension)
                // Keyed to gesture/visibility state, NOT to derived geometry —
                // appear settling must not animate. The drag-offset springs
                // are what animate releases (the host sheet strips
                // withAnimation transactions); every state flip happens at
                // an offset where the derived frame is continuous.
                .animation(isPanelDragActive ? nil : .easeInOut(duration: panelToggleDuration), value: panelToggleGeneration)
                .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: sideColumnDragOffset)
                .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: belowPanelDragOffset)
                // Aspect ratio changes (new video, stream switch) resize
                // the video/panel split — animate them
                .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: playerState?.displayAspectRatio)
                .clipped()
                // Swipe up on the video to bring the panel back — the
                // video's bottom edge follows the finger (like the portrait
                // reveal) via belowPanelDragOffset counting down from full
                // hide travel.
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
                                    // Grow back over the panel, then drop the
                                    // reveal geometry without animation
                                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0), completionCriteria: .removed) {
                                        belowPanelDragOffset = panelHideTravel
                                    } completion: {
                                        // A new reveal drag may have taken over
                                        guard isRevealDragActive, belowPanelDragOffset == panelHideTravel,
                                              appEnvironment?.navigationCoordinator.isPanelDragging != true else { return }
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
                // Swipe in from the trailing screen edge to bring a
                // collapsed side column back — the video's trailing edge
                // follows the finger via sideColumnDragOffset counting down
                // from full travel. Only the edge strip: the seek pan is
                // told to skip it, everywhere else seeks.
                .simultaneousGesture(
                    isSideColumnCollapsed
                        ? DragGesture(coordinateSpace: .local)
                            .onChanged { value in
                                guard appEnvironment?.navigationCoordinator.isAdjustingPlayerSliders != true else { return }
                                guard isSideColumnRevealDragActive
                                    || (value.startLocation.x >= videoWidth - Self.sideColumnEdgeRevealInset
                                        && value.translation.width < 0) else { return }
                                if appEnvironment?.navigationCoordinator.isPanelDragging != true {
                                    appEnvironment?.navigationCoordinator.isPanelDragging = true
                                }
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    isSideColumnRevealDragActive = true
                                    sideColumnDragOffset = min(sideColumnHideTravel, max(0, sideColumnHideTravel + value.translation.width))
                                }
                            }
                            .onEnded { value in
                                guard isSideColumnRevealDragActive else { return }
                                appEnvironment?.navigationCoordinator.isPanelDragging = false
                                if value.translation.width < -80 || value.predictedEndTranslation.width < -160 {
                                    // Revealing: flip to visible at the
                                    // current position, then animate home
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        isSideColumnVisible = true
                                        isSideColumnRevealDragActive = false
                                    }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                        sideColumnDragOffset = 0
                                    }
                                } else {
                                    // Grow back over the column, then drop
                                    // the reveal geometry without animation
                                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0), completionCriteria: .removed) {
                                        sideColumnDragOffset = sideColumnHideTravel
                                    } completion: {
                                        // A new reveal drag may have taken over
                                        guard isSideColumnRevealDragActive, sideColumnDragOffset == sideColumnHideTravel,
                                              appEnvironment?.navigationCoordinator.isPanelDragging != true else { return }
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            isSideColumnRevealDragActive = false
                                            sideColumnDragOffset = 0
                                        }
                                    }
                                }
                            }
                        : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Extend into the bottom safe area (incl. the player
                // window's extra PiP inset) so the full-height video reaches
                // the true bottom edge
                .ignoresSafeArea(edges: .bottom)
                .zIndex(1)
            }
            // Container-level animation so the video-area resize plays as
            // one transition (the host sheet strips withAnimation
            // transactions, so key it here)
            .animation(isPanelDragActive ? nil : .easeInOut(duration: panelToggleDuration), value: panelToggleGeneration)
            .animation(isPanelDragActive ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: sideColumnDragOffset)
            .onChange(of: isSideColumnCollapsed, initial: true) { _, collapsed in
                appEnvironment?.navigationCoordinator.cornerSideColumnEdgeRevealInset = collapsed ? Self.sideColumnEdgeRevealInset : 0
            }
            .onChange(of: width) { _, newWidth in
                // Re-clamp when the window shrinks (still above the corner
                // threshold — below it the resolver switches layouts).
                columnWidth = clampColumnWidth(columnWidth, availableWidth: newWidth)
            }
        }
        .onDisappear {
            appEnvironment?.navigationCoordinator.cornerSideColumnEdgeRevealInset = 0
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
                if newValue { restoreDraggedAwayRegions() } else { collapseBelowPanelUnderVideo() }
                isPanelVisible = newValue
                panelToggleGeneration += 1
            }
        }
    }

    // MARK: - Panels

    /// Portrait-style panel below the video: the actual PortraitDetailsPanel
    /// (drag handle, player pill, collapsible description) with the comments
    /// pill hidden and no inline chapters/related — those live in the side
    /// column tabs.
    @ViewBuilder
    private func belowVideoInfoPanel(video: Video, hideTravel: CGFloat, publishesFrame: Bool) -> some View {
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
                            // Dragging UP - expand panel over the video.
                            // Raised at home (no hide travel yet), so the
                            // z-order swap happens with nothing overlapping.
                            isBelowPanelRaised = true
                            belowPanelExpandOffset = offset
                            belowPanelDragOffset = 0
                        } else {
                            // Dragging DOWN - the video grows over the panel
                            isBelowPanelRaised = false
                            belowPanelDragOffset = offset
                            belowPanelExpandOffset = 0
                        }
                    }
                },
                onDragEnded: { offset, predicted in
                    appEnvironment?.navigationCoordinator.isPanelDragging = false
                    if isBelowPanelExpanded {
                        if offset > 80 || predicted > 160 {
                            // Collapse back to home, then drop under the
                            // video once the spring is fully gone (`.removed`
                            // — see the hide path below)
                            withAnimation(.spring(response: 0.3, dampingFraction: 1.0), completionCriteria: .removed) {
                                isBelowPanelExpanded = false
                                belowPanelExpandOffset = 0
                            } completion: {
                                lowerBelowPanelIfHome()
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
                        // Grow the video fully over the panel, then flip the
                        // hidden state without animation — the dragged
                        // geometry at full travel matches the hidden geometry
                        // exactly. Must wait
                        // for `.removed`: flipping at `.logicallyComplete`
                        // leaves the spring registered on the video frame, and
                        // a quick follow-up reveal swipe that interrupts it
                        // makes the release spring start from a bogus shrunken
                        // rect (video clipped to a short box, growing back).
                        withAnimation(.spring(response: 0.3, dampingFraction: 1.0), completionCriteria: .removed) {
                            belowPanelDragOffset = hideTravel
                        } completion: {
                            // The panel may have been grabbed again meanwhile
                            guard isBelowPanelVisible, belowPanelDragOffset == hideTravel,
                                  appEnvironment?.navigationCoordinator.isPanelDragging != true else { return }
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                isBelowPanelVisible = false
                                isBelowPanelExpanded = false
                                belowPanelDragOffset = 0
                            }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8), completionCriteria: .removed) {
                            belowPanelDragOffset = 0
                            belowPanelExpandOffset = 0
                        } completion: {
                            lowerBelowPanelIfHome()
                        }
                    }
                },
                onDragCancelled: {
                    appEnvironment?.navigationCoordinator.isPanelDragging = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8), completionCriteria: .removed) {
                        belowPanelDragOffset = 0
                        belowPanelExpandOffset = 0
                    } completion: {
                        lowerBelowPanelIfHome()
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
        // doesn't begin from touches inside this panel (drag handle conflict).
        // Not while the video covers the panel — it stays in the hierarchy
        // hidden, and must not block the pan from starting over the video.
        .background {
            GeometryReader { proxy in
                let frame = publishesFrame ? proxy.frame(in: .global) : .zero
                Color.clear
                    .onChange(of: frame, initial: true) { _, frame in
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
        // The grabber strip already separates the column from the video;
        // trim the leading inset so content sits 16pt from the column's
        // outer edge on both sides instead of grabber + 16 on the left.
        .environment(\.panelHorizontalInsets, PanelHorizontalInsets(
            leading: max(0, PanelHorizontalInsets.standard - Self.grabberWidth),
            trailing: PanelHorizontalInsets.standard
        ))
        .background(panelBackgroundColor.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Actions

    private func togglePanel() {
        // Regions dragged away on their own leave the panel nominally
        // visible — once nothing is left on screen the toggle shows
        // everything again instead of "hiding" an empty panel.
        let showsAnyRegion = isPanelVisible
            && ((isSideColumnVisible && hasSideColumn) || (isBelowPanelVisible && hasBelowVideoInfo))
        let show = !showsAnyRegion
        withAnimation(.easeInOut(duration: 0.25)) {
            if show { restoreDraggedAwayRegions() } else { collapseBelowPanelUnderVideo() }
            isPanelVisible = show
            panelToggleGeneration += 1
            settingsManager?.landscapeDetailsPanelVisible = show
            settingsManager?.detailsPanelLastVisible = show
        }
    }

    /// Hiding everything grows the video over the below panel, so an
    /// expanded panel (raised above the video) must drop back to its home
    /// geometry under the video first.
    private func collapseBelowPanelUnderVideo() {
        isBelowPanelExpanded = false
        belowPanelExpandOffset = 0
        isBelowPanelRaised = false
    }

    /// Completion of an expand-collapse / snap-back spring: drop the panel
    /// under the video once it sits at home again — unless a new drag has
    /// picked it up meanwhile.
    private func lowerBelowPanelIfHome() {
        guard !isBelowPanelExpanded, belowPanelExpandOffset == 0,
              appEnvironment?.navigationCoordinator.isPanelDragging != true else { return }
        isBelowPanelRaised = false
    }

    /// Showing the panel brings back every region hidden by its own drag
    /// handle (the portrait layout shares one flag for both, so this keeps
    /// the toggle's meaning the same across layouts).
    private func restoreDraggedAwayRegions() {
        isSideColumnVisible = true
        sideColumnDragOffset = 0
        isBelowPanelVisible = true
        belowPanelDragOffset = 0
    }
}

#endif
