//
//  ExpandedPlayerSheet+Layouts.swift
//  Yattee
//
//  Layout views for the expanded player sheet (portrait, widescreen, player areas).
//

import SwiftUI
import NukeUI

#if os(iOS) || os(macOS) || os(tvOS)

extension ExpandedPlayerSheet {
    // MARK: - Layout Constants

    /// Minimum width required for the corner layout; below this the corner
    /// preset setting falls back to the stacked widescreen layout (Split View,
    /// narrow windows).
    static let minWidthForCornerLayout: CGFloat = 900

    /// Minimum height (safe areas included) for the corner layout on iOS:
    /// keeps it off tall-phone landscape (iPhone Pro Max is 956×440) while
    /// the iPhone Duo interior (951×669) and every iPad qualify. The gate is
    /// size-only — the Duo interior behaves like a small iPad, and the
    /// exterior display never reaches the width. On macOS it is not a gate
    /// but the player window's resize floor while the corner layout is on.
    static let minHeightForCornerLayout: CGFloat = 600

    /// Tabletop (foldable, hinge partially open): vertical room reserved on
    /// the lower half for the top bar row and for the bottom bar, keeping the
    /// center controls and side sliders clear of both.
    static let tabletopTopBarInset: CGFloat = 72
    static let tabletopBottomBarInset: CGFloat = 96
    /// Book posture (hinge vertical): clearance between the hinge line and
    /// the controls confined to the trailing half.
    static let bookFoldHingeGap: CGFloat = 16

    #if os(iOS)
    /// Reflection strength at the hinge line; it fades to nothing at
    /// `tabletopReflectionFadeEnd` of the mirrored video height.
    static let tabletopReflectionOpacity: Double = 0.4
    static let tabletopReflectionFadeEnd: CGFloat = 0.7
    /// Softens the mirrored frames so the reflection reads as a glow, not a second video.
    static let tabletopReflectionBlurRadius: CGFloat = 16

    private var showsTabletopReflection: Bool {
        guard appEnvironment?.settingsManager.tabletopReflection ?? true,
              let playerState else { return false }
        return playerState.isFirstFrameReady && playerState.isBufferReady
            && playerState.currentStream?.isAudioOnly != true
            && playerState.pipState != .active
    }

    /// Mirrored video frames sized like the fitted video, fading out downwards.
    private func tabletopReflection(backend: MPVBackend, width: CGFloat, height: CGFloat) -> some View {
        MPVReflectionView(backend: backend)
            .frame(width: width, height: height)
            .blur(radius: Self.tabletopReflectionBlurRadius)
            .mask(
                LinearGradient(
                    colors: [.white.opacity(Self.tabletopReflectionOpacity), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: Self.tabletopReflectionFadeEnd)
                )
            )
            .allowsHitTesting(false)
    }
    #endif

    // MARK: - Layout Detection

    /// Check if widescreen layout should be used based on available size.
    func isWideScreenLayout(size: CGSize) -> Bool {
        #if os(iOS)
        let isLandscape = size.width > size.height
        return isLandscape // All landscape orientations use widescreen
        #elseif os(macOS)
        // macOS: Always use widescreen layout
        return true
        #else
        return false // tvOS uses different layout
        #endif
    }

    #if os(iOS) || os(macOS)
    /// Whether the corner layout should be used for the given size: opted into
    /// via the preset's panel settings, large enough (iPad, macOS, iPhone Duo
    /// interior), and in a widescreen orientation. Evaluated per layout pass
    /// so window resizes and Split View changes fall back automatically.
    /// `size` must include the safe areas so the status bar toggling with the
    /// layout can't feed back into the decision.
    func isCornerLayout(size: CGSize) -> Bool {
        playerControlsLayout.effectivePanelSettings.effectiveLayoutMode == .corner
            && cornerLayoutFits(size: size)
    }

    /// The size half of `isCornerLayout(size:)`, independent of the preset's
    /// layout mode.
    func cornerLayoutFits(size: CGSize) -> Bool {
        #if os(iOS)
        guard size.height >= Self.minHeightForCornerLayout else { return false }
        #endif
        return size.width >= Self.minWidthForCornerLayout
            && isWideScreenLayout(size: size)
    }
    #endif

    // MARK: - Standard/Portrait Layout

    /// Standard player content for portrait mode with video at top and panel below.
    @ViewBuilder
    func standardPlayerContent(geometry: GeometryProxy) -> some View {
        // Ensure valid aspect ratio (avoid division by zero)
        let rawAspectRatio = playerState?.displayAspectRatio ?? (16.0 / 9.0)
        let aspectRatio = rawAspectRatio > 0 ? rawAspectRatio : (16.0 / 9.0)
        // Content area size (excludes safe areas)
        let contentHeight = max(1, geometry.size.height)
        let contentWidth = max(1, geometry.size.width)
        // Full screen size including safe areas (for portrait fullscreen)
        let safeAreaInsets = geometry.safeAreaInsets
        let fullScreenHeight = max(1, contentHeight + safeAreaInsets.top + safeAreaInsets.bottom)
        // Displays with a vertical status bar (iPhone Duo exterior) inset the
        // content horizontally too. With the panel hidden the video and the
        // controls layer span the full width and shift under the leading
        // inset, mirroring `fullscreenPlayerOffset` vertically; the controls
        // pad their edges by the window's horizontal safe area themselves.
        let fullScreenWidth = max(1, contentWidth + safeAreaInsets.leading + safeAreaInsets.trailing)
        // Use content size for layout, full screen size for portrait fullscreen controls
        let screenHeight = contentHeight
        let screenWidth = isPortraitPanelVisible ? contentWidth : fullScreenWidth
        let fullscreenPlayerXOffset: CGFloat = isPortraitPanelVisible ? 0 : -safeAreaInsets.leading

        // Reserve minimum space for panel when pinned
        // Dynamic height based on description content
        // Only use compact panel when we've confirmed video has no description
        // (detailsState == .loaded and hasDescription == false)
        // During idle/loading states, use larger panel to prevent jump when description loads
        let hasDescription = !(playerState?.currentVideo?.description ?? "").isEmpty
        let videoDetailsState = playerState?.videoDetailsState ?? .idle
        let shouldUseCompactPanel = videoDetailsState == .loaded && !hasDescription

        // Check if expanded comments pill will be visible (needs extra panel height)
        let pillSettings = playerControlsLayout.effectivePlayerPillSettings
        let commentsPillMode = playerControlsLayout.effectivePanelSettings.commentsPillMode
        let hasCommentsPill = playerState?.commentsState == .loaded &&
            !(playerState?.comments.isEmpty ?? true) &&
            commentsPillMode != .disabled
        let hasExpandedCommentsPill = hasCommentsPill &&
            pillSettings.visibility.isVisible(isWideLayout: false) &&
            !pillSettings.buttons.isEmpty &&
            !commentsPillMode.alwaysCollapsed

        let minPanelHeight: CGFloat = useCompactPanel ? 150 : 200
        // When compact panel but expanded comments pill visible, need taller panel (~250pt)
        let maxPanelHeight: CGFloat = useCompactPanel ? (hasExpandedCommentsPill ? 250 : 190) : .infinity

        let maxVideoHeight = max(1, screenHeight - minPanelHeight)

        // Tabletop (foldable hinge partially open, panel hidden): the upper
        // half of the screen is the video area, the lower half holds every
        // control. `layoutHeight` replaces the full screen height wherever the
        // fullscreen video is fitted and positioned.
        #if os(iOS)
        let isHingeSplit = isTabletopHinge
        let isTabletop = isTabletopHinge && !isPortraitPanelVisible
        #else
        let isHingeSplit = false
        let isTabletop = false
        #endif
        let layoutHeight = isTabletop ? fullScreenHeight / 2 : fullScreenHeight

        // Calculate fit size (aspect-fit within screen bounds, but capped to show panel)
        let fitHeightFromWidth = screenWidth / aspectRatio
        let fitWidthFromHeight = screenHeight * aspectRatio
        let uncappedFitHeight: CGFloat = fitHeightFromWidth > screenHeight ? screenHeight : fitHeightFromWidth
        let uncappedFitWidth: CGFloat = fitHeightFromWidth > screenHeight ? fitWidthFromHeight : screenWidth

        // Apply max height constraint to leave space for panel (or to the
        // upper half while the hinge is partially open, panel shown or not)
        let fitHeightCap = isHingeSplit ? min(maxVideoHeight, fullScreenHeight / 2) : maxVideoHeight
        let fitHeight = max(1, min(uncappedFitHeight, fitHeightCap))
        let fitWidth = max(1, fitHeight < uncappedFitHeight ? fitHeight * aspectRatio : uncappedFitWidth)

        // Calculate fullscreen fit size (aspect-fit within full screen including safe areas)
        let fullscreenFitHeightFromWidth = screenWidth / aspectRatio
        let fullscreenFitHeight: CGFloat = max(1, fullscreenFitHeightFromWidth > layoutHeight ? layoutHeight : fullscreenFitHeightFromWidth)

        // Calculate fill size (aspect-fill to cover the video area: the whole
        // screen, or the upper half in tabletop)
        let fillAreaHeight = isTabletop ? layoutHeight : screenHeight
        let fillHeight: CGFloat = max(1, fitHeightFromWidth >= fillAreaHeight ? fitHeightFromWidth : fillAreaHeight)
        let fillWidth: CGFloat = max(1, fitHeightFromWidth >= fillAreaHeight ? screenWidth : fillAreaHeight * aspectRatio)

        #if os(iOS)
        // Use UIKit pinch gesture panscan from NavigationCoordinator.
        let panscan = !isPortraitPanelVisible ? (navigationCoordinator?.pinchPanscan ?? 0.0) : 0.0
        #else
        let panscan = 0.0
        #endif

        // Video layer uses panscan-interpolated size, controls stay at fit size
        let videoHeight = max(1, fitHeight + (fillHeight - fitHeight) * panscan)
        let videoWidth = max(1, fitWidth + (fillWidth - fitWidth) * panscan)

        // In fullscreen, offset the player up by top safe area to align with screen top
        let fullscreenPlayerOffset: CGFloat = !isPortraitPanelVisible ? -safeAreaInsets.top : 0

        let isDismissing = navigationCoordinator?.isPlayerDismissGestureActive == true

        // Calculate player height - animates between fit and fullscreen
        // Use full screen height when panel is hidden for immersive controls
        let playerHeight = !isPortraitPanelVisible ? layoutHeight : fitHeight

        // Panel height when pinned (capped by maxPanelHeight for widescreen videos without description)
        let naturalPanelHeight = screenHeight - fitHeight
        // Hinge partially open: the panel takes the whole lower half, its top
        // edge on the hinge, so the video keeps the upper half either way.
        let hingeY = fullScreenHeight / 2 - safeAreaInsets.top
        let pinnedPanelHeight = isHingeSplit ? max(1, screenHeight - hingeY) : min(naturalPanelHeight, maxPanelHeight)
        let pillsOverlayOpacity: CGFloat = {
            guard isPanelDragging, panelDragOffset > 0 else { return 1 }
            let fadeDistance: CGFloat = 48
            let progress = min(1, panelDragOffset / fadeDistance)
            return 1 - progress
        }()

        // Video area height (space above panel) - may be larger than fitHeight when panel is capped
        let videoAreaHeight = screenHeight - pinnedPanelHeight

        // Calculate video Y position
        // Note: Coordinate system starts at top of content area (after safe area insets)
        // so we don't add safeAreaInsets.top for positioning within content area
        //
        // videoYOffset is a @State that we animate explicitly for smooth drag release animation.
        // Base positions are computed, then videoYOffset is added.
        // Video center when the panel is hidden, in content-area coordinates:
        // full-screen center shifted up by the top safe area. NOT screenHeight/2 —
        // top and bottom insets differ (the player window adds extra bottom
        // inset), so animating to screenHeight/2 and then flipping to the hidden
        // base position causes a visible jump of (bottom - top) / 2 points.
        //
        // Tabletop: the hidden position is the center of the upper half. This
        // must follow the hinge, not `isTabletop` (which is false while the
        // panel is visible): dragging the panel down interpolates the video
        // towards this point, and using the full-screen center there moved
        // the video down during the drag, only to snap it back up once the
        // hidden state flipped to the half-height layout.
        #if os(iOS)
        let hiddenLayoutHeight = isTabletopHinge ? fullScreenHeight / 2 : fullScreenHeight
        #else
        let hiddenLayoutHeight = fullScreenHeight
        #endif
        let hiddenVideoY = hiddenLayoutHeight / 2 - safeAreaInsets.top
        // Video centered in video area (above panel). Hinge split: the same
        // spot as with the panel hidden, so toggling the panel never moves it.
        let topY = isHingeSplit ? hiddenVideoY : videoAreaHeight / 2

        let videoY: CGFloat = {
            if isPortraitPanelVisible {
                // Panel is visible - base position is at top, offset is animated
                return topY + videoYOffset
            } else {
                // Panel is hidden - interpolate based on reveal offset (swipe up to reveal)
                if panelRevealOffset < 0 {
                    // Revealing panel - move video towards top
                    let revealProgress = min(1.0, -panelRevealOffset / pinnedPanelHeight)
                    return hiddenVideoY - (hiddenVideoY - topY) * revealProgress
                }
                // Fullscreen: fill entire screen (need to offset for safe area)
                return hiddenVideoY
            }
        }()

        // Create player view with stable identity for smooth animations (no controls - rendered separately)
        let playerView = portraitPlayerArea(
            fitWidth: fitWidth,
            fitHeight: fitHeight,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            screenWidth: screenWidth,
            screenHeight: layoutHeight,
            isFullscreen: !isPortraitPanelVisible,
            showControls: false,
            activeLayout: playerControlsLayout
        )
        .frame(width: screenWidth, height: playerHeight)
        .clipped()
        // Black background hides during dismiss gesture
        .background(isDismissing && isPortraitPanelVisible ? Color.clear : (isDismissing || !isPortraitPanelVisible ? Color.clear : Color.black))
        .geometryGroup()
        .id("player") // Stable identity for aspect ratio animations

        // Controls layer - rendered separately
        // When panel visible: sized to video area, positioned at top
        // When fullscreen: sized and positioned exactly like playerView to align perfectly

        // During drag, expand controls layer to follow the panel
        // This keeps the bottom bar close to the panel as it drags down
        // Note: We check panelDragOffset > 0 without isPanelDragging so the animation
        // continues smoothly when drag ends (panelDragOffset animates back to 0)
        let draggedControlsHeight: CGFloat = {
            if isPortraitPanelVisible && panelDragOffset > 0 {
                return videoAreaHeight + panelDragOffset
            }
            return isPortraitPanelVisible ? videoAreaHeight : fullScreenHeight
        }()

        let controlsLayer = portraitControlsOverlay(
            screenWidth: screenWidth,
            // Both modes use their respective heights
            screenHeight: draggedControlsHeight,
            fitHeight: fitHeight,
            isFullscreen: !isPortraitPanelVisible,
            forceHidden: hideControlsDuringTransition,
            onTogglePanel: { toggleFloatingPanelVisibility() },
            isPanelVisible: isPortraitPanelVisible,
            isPanelPinned: isPortraitPanelVisible,
            // Video area bounds for positioning center controls, sliders, bottom bar
            // When panel visible: video fills the controls area (0 to fitHeight)
            // When fullscreen: video centered on full screen
            // During drag: expand videoAreaHeight so bottom bar moves down with panel
            // Tabletop: the controls' "video area" is the lower half so the
            // center controls, sliders and top bar all land below the hinge.
            // The center zone excludes the top bar row and the bottom bar so
            // the side sliders don't collide with either.
            videoAreaTop: isTabletop ? layoutHeight + Self.tabletopTopBarInset : (isPortraitPanelVisible ? 0 : (fullScreenHeight - fullscreenFitHeight) / 2),
            videoAreaHeight: isTabletop ? layoutHeight - Self.tabletopTopBarInset - Self.tabletopBottomBarInset : (isPortraitPanelVisible ? draggedControlsHeight : fullscreenFitHeight),
            // Pass stable fitHeight for slider sizing (doesn't change during drag)
            // Panel visible or dragging: use fitHeight for stable sizing
            // Fullscreen (after drag completes): pass nil so sliders use geometry.size.height
            videoFitHeight: isTabletop ? layoutHeight : ((isPortraitPanelVisible || isPanelDragging) ? fitHeight : nil),
            isTabletop: isTabletop,
            horizontalSafeArea: (safeAreaInsets.leading, safeAreaInsets.trailing),
            activeLayout: playerControlsLayout
        )
        .frame(width: screenWidth, height: draggedControlsHeight)

        ZStack {
            // Black background - clear during dismiss to avoid black bar in safe area
            (isDismissing ? Color.clear : Color.black)
                .ignoresSafeArea(.all)

            // Player positioned based on panel state
            playerView
                .position(x: screenWidth / 2 + fullscreenPlayerXOffset, y: videoY)
                // Animate video position when not dragging (matches panel animation behavior)
                .animation(isPanelDragging ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: videoYOffset)
                .animation(panelRevealOffset != 0 ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: isPortraitPanelVisible)

            #if os(iOS)
            // Tabletop: mirror the video across the hinge line into the lower
            // half, like a screen standing on a glossy table. The mirrored
            // frames come from the render view; this only places and fades them.
            // Clipped to the lower half: a filled (panscanned) video is taller
            // than the upper half, and its mirror would otherwise spill back
            // over the hinge onto the video itself.
            if isTabletop, showsTabletopReflection,
               let backend = playerService?.currentBackend as? MPVBackend {
                let hingeY = layoutHeight - safeAreaInsets.top
                tabletopReflection(backend: backend, width: videoWidth, height: videoHeight)
                    .position(x: screenWidth / 2 + fullscreenPlayerXOffset, y: hingeY - videoY)
                    .frame(width: screenWidth, height: layoutHeight)
                    .clipped()
                    .position(x: screenWidth / 2, y: hingeY + layoutHeight / 2)
                    .transition(.opacity)
            }
            #endif

            // Controls layer - positioned based on panel state
            // When panel visible: positioned to cover from top down to panel
            // When fullscreen: positioned exactly like playerView so they align
            Group {
                if isPortraitPanelVisible {
                    controlsLayer
                        .position(x: screenWidth / 2, y: draggedControlsHeight / 2)
                        // Animate controls position when not dragging (matches panel animation)
                        .animation(isPanelDragging ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: panelDragOffset)
                } else {
                    // Position exactly like playerView - at videoY with same offset
                    // This ensures controls y=0 aligns with screen y=0
                    controlsLayer
                        .position(x: screenWidth / 2 + fullscreenPlayerXOffset, y: fullScreenHeight / 2 + fullscreenPlayerOffset)
                }
            }
            // Reveal gesture - swipe up to show panel when hidden (simultaneous so taps still work for controls)
            #if !os(tvOS)
            .simultaneousGesture(
                    !isPortraitPanelVisible ?
                    DragGesture()
                        .onChanged { value in
                            // Skip if user is adjusting sliders
                            guard navigationCoordinator?.isAdjustingPlayerSliders != true else { return }

                            // Dragging up = negative translation
                            if value.translation.height < 0 {
                                hideControlsDuringTransition = true
                                panelRevealOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            // Skip if user is adjusting sliders
                            guard navigationCoordinator?.isAdjustingPlayerSliders != true else {
                                // Reset any partial reveal state
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    panelRevealOffset = 0
                                }
                                hideControlsDuringTransition = false
                                return
                            }

                            let threshold: CGFloat = -80
                            let currentRevealOffset = panelRevealOffset

                            if value.translation.height < threshold || value.predictedEndTranslation.height < threshold * 2 {
                                // Revealing panel - single panel approach
                                // Position panel at current location using panelDragOffset before switching to visible
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    isPanelDragging = true
                                    navigationCoordinator?.isPanelDragging = true
                                    // Transfer current visual position to panelDragOffset
                                    // Before: offset = pinnedPanelHeight + safeAreaInsets.bottom + panelRevealOffset
                                    // After:  offset = panelDragOffset (since isPortraitPanelVisible will be true)
                                    panelDragOffset = pinnedPanelHeight + safeAreaInsets.bottom + currentRevealOffset
                                    panelRevealOffset = 0
                                    isPortraitPanelVisible = true
                                    navigationCoordinator?.isPortraitPanelVisible = true
                                    appEnvironment?.settingsManager.portraitDetailsPanelLastVisible = true
                                    // Match video position from reveal formula
                                    let revealProgress = min(1.0, -currentRevealOffset / pinnedPanelHeight)
                                    let maxVideoOffset = hiddenVideoY - topY
                                    videoYOffset = maxVideoOffset * (1.0 - revealProgress)
                                }

                                // Now animate to final position
                                isPanelDragging = false
                                panelDragOffset = 0
                                videoYOffset = 0

                                // Delay NavigationCoordinator update until after position animation starts
                                // This keeps pill animations suppressed during the transition
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    navigationCoordinator?.isPanelDragging = false
                                }
                                hideControlsDuringTransition = false
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    panelRevealOffset = 0
                                }
                                hideControlsDuringTransition = false
                            }
                        }
                    : nil
                )
            #endif

            // Pinned panel (fills space below video) - iOS only
            #if os(iOS)
            // Always rendered; use offset to hide when not visible
            if isPortraitPanelVisible || panelRevealOffset != 0 {
                if let video = playerState?.currentVideo {
                    VStack(spacing: 0) {
                        // Spacer shrinks as panel expands (follows drag)
                        // panelExpandOffset is negative when dragging up
                        // Use videoAreaHeight (not fitHeight) to account for capped panel height
                        Spacer()
                            .frame(height: {
                                if isPanelExpanded {
                                    // When expanded, spacer grows as user drags down to collapse
                                    return min(videoAreaHeight, panelExpandOffset)
                                } else {
                                    // When normal, spacer shrinks as user drags up
                                    return max(0, videoAreaHeight + panelExpandOffset)
                                }
                            }())

                        PortraitDetailsPanel(
                            onChannelTap: video.author.hasRealChannelInfo ? {
                                navigationCoordinator?.navigateToChannel(for: video, collapsePlayer: true)
                            } : nil,
                            playerControlsLayout: playerControlsLayout,
                            onFullscreen: { [self] in toggleFullscreen() },
                            pillsOverlayOpacity: pillsOverlayOpacity,
                            onDragChanged: { [self] offset in
                                // Set drag flags only on transition to avoid 120/sec @Observable writes
                                if !isPanelDragging {
                                    isPanelDragging = true
                                    navigationCoordinator?.isPanelDragging = true
                                }
                                // Use transaction to disable animations during drag
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    if isPanelExpanded {
                                        // When expanded, only track drag for collapse
                                        // Positive offset = dragging down = collapse
                                        panelExpandOffset = max(0, offset)
                                    } else if offset < 0 {
                                        // Dragging UP - expand panel
                                        panelExpandOffset = offset  // Negative value
                                        panelDragOffset = 0
                                        videoYOffset = 0  // Video stays in place
                                    } else {
                                        // Dragging DOWN - existing dismiss logic
                                        panelDragOffset = offset
                                        panelExpandOffset = 0
                                        // Calculate video offset: interpolate from 0 to (hiddenVideoY - topY) based on drag
                                        let maxOffset = hiddenVideoY - topY
                                        let dragProgress = min(1.0, offset / pinnedPanelHeight)
                                        videoYOffset = maxOffset * dragProgress
                                    }
                                }
                            },
                            onDragEnded: { [self] offset, predictedOffset in
                                let dismissThreshold: CGFloat = 80
                                let expandThreshold: CGFloat = -80  // Upward threshold
                                let targetOffset = pinnedPanelHeight + safeAreaInsets.bottom
                                let maxVideoOffset = hiddenVideoY - topY

                                // Setting isPanelDragging = false activates the .animation modifiers
                                isPanelDragging = false
                                navigationCoordinator?.isPanelDragging = false

                                if isPanelExpanded {
                                    // In expanded state, drag down to collapse
                                    let collapseThreshold: CGFloat = 80
                                    if offset > collapseThreshold || predictedOffset > collapseThreshold * 2 {
                                        // Collapse back to normal
                                        isPanelExpanded = false
                                        panelExpandOffset = 0
                                    } else {
                                        // Snap back to expanded
                                        panelExpandOffset = 0
                                    }
                                } else if offset < expandThreshold || predictedOffset < expandThreshold * 2 {
                                    // Expand panel to fullscreen
                                    isPanelExpanded = true
                                    panelExpandOffset = 0
                                    panelDragOffset = 0
                                    videoYOffset = 0
                                } else if offset > dismissThreshold || predictedOffset > dismissThreshold * 2 {
                                    // Dismissing - animate panel sliding off and video to center.
                                    // The hidden-state flip must wait for the spring to finish:
                                    // a fixed-delay timer fired mid-animation and snapped the
                                    // video the rest of the way (visible jump on release).
                                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0), completionCriteria: .logicallyComplete) {
                                        panelDragOffset = targetOffset
                                        videoYOffset = maxVideoOffset
                                    } completion: {
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            isPortraitPanelVisible = false
                                            navigationCoordinator?.isPortraitPanelVisible = false
                                            appEnvironment?.settingsManager.portraitDetailsPanelLastVisible = false
                                            isCommentsExpanded = false
                                            navigationCoordinator?.isCommentsExpanded = false
                                            navigationCoordinator?.commentsFrame = .zero
                                            panelDragOffset = 0
                                            videoYOffset = 0  // Reset offset (hiddenVideoY is now the base)
                                        }
                                    }
                                } else {
                                    // Snap back - animate panel and video back to rest position
                                    panelDragOffset = 0
                                    panelExpandOffset = 0
                                    videoYOffset = 0
                                }
                            },
                            onDragCancelled: { [self] in
                                // Reset drag state on cancellation - snap back to rest position
                                isPanelDragging = false
                                navigationCoordinator?.isPanelDragging = false

                                withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                    panelDragOffset = 0
                                    panelExpandOffset = 0
                                    videoYOffset = 0
                                }
                            },
                            onRequestExpand: { [self] in
                                // Comments pill routed to the comments page:
                                // expand the panel to fullscreen
                                guard !isPanelExpanded else { return }
                                withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                    isPanelExpanded = true
                                    panelExpandOffset = 0
                                    panelDragOffset = 0
                                    videoYOffset = 0
                                }
                            }
                        )
                        .frame(height: {
                            let normalHeight = pinnedPanelHeight + safeAreaInsets.bottom
                            let expandedHeight = screenHeight + safeAreaInsets.bottom
                            if isPanelExpanded {
                                // When expanded, shrink as user drags down to collapse
                                return max(normalHeight, expandedHeight - panelExpandOffset)
                            } else {
                                // When normal, grow as user drags up (panelExpandOffset is negative)
                                return min(expandedHeight, normalHeight - panelExpandOffset)
                            }
                        }())
                        .offset(y: panelDragOffset)  // Only use dismiss offset, expand is handled by height
                        // When hidden: offset panel below screen; during reveal: panelRevealOffset (negative) brings it up
                        .offset(y: !isPortraitPanelVisible ? (pinnedPanelHeight + safeAreaInsets.bottom + panelRevealOffset) : 0)
                        .opacity(!isPortraitPanelVisible ? min(1, -panelRevealOffset / 80) : 1)
                        .allowsHitTesting(isPortraitPanelVisible)
                        .animation(isPanelDragging ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: panelDragOffset)
                        .animation(isPanelDragging ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: panelExpandOffset)
                        .animation(isPanelDragging ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: isPanelExpanded)
                        .background(
                            GeometryReader { panelGeometry in
                                Color.clear
                                    .onAppear {
                                        navigationCoordinator?.portraitPanelFrame = panelGeometry.frame(in: .global)
                                    }
                                    .onChange(of: panelGeometry.frame(in: .global)) { _, newFrame in
                                        // Skip updates during drag to avoid 120/sec coordinator writes
                                        guard !isPanelDragging else { return }
                                        navigationCoordinator?.portraitPanelFrame = newFrame
                                    }
                            }
                        )
                    }
                    .ignoresSafeArea(edges: .bottom)  // Only ignore bottom safe area, preserve top
                }
            }
            #endif

        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(!isPortraitPanelVisible ? Color.black : Color.clear)
        // Only animate when aspect ratio changes, not when geometry changes during sheet presentation
        .animation(.easeInOut(duration: 0.3), value: aspectRatio)
        .animation(.easeInOut(duration: 0.3), value: isPortraitPanelVisible)
        .animation(.easeInOut(duration: 0.3), value: useCompactPanel)
        // Animate panel height change when comments load (expanded comments pill becomes visible)
        .animation(.easeInOut(duration: 0.3), value: playerState?.commentsState)
        .onAppear {
            currentPlayerHeight = fitHeight
            // Sync panel visibility with NavigationCoordinator (preserve existing state)
            navigationCoordinator?.isPortraitPanelVisible = isPortraitPanelVisible
            // Initialize compact panel state without animation (prevent animation on sheet re-expand)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                useCompactPanel = shouldUseCompactPanel
            }
        }
        .onChange(of: fitHeight) { _, newHeight in
            currentPlayerHeight = newHeight
        }
        // Note: We intentionally do NOT clear portraitPanelFrame when panel hides.
        // The GeometryReader will track the off-screen position naturally.
        // Clearing to .zero causes race conditions where the frame stays .zero
        // after reveal, allowing sheet dismiss gesture to incorrectly fire.
        .onChange(of: isPortraitPanelVisible) { _, isVisible in
            if !isVisible {
                // Clear panel frame when hidden
                navigationCoordinator?.portraitPanelFrame = .zero
                // Reset panel expansion state
                isPanelExpanded = false
                panelExpandOffset = 0
            }
        }
        .onChange(of: playerState?.videoDetailsState) { _, newState in
            // Update compact panel state with animation when video details finish loading
            // When state goes to .idle (video changing), this resets to non-compact
            // When state goes to .loaded with no description, this enables compact
            let hasDescription = !(playerState?.currentVideo?.description ?? "").isEmpty
            let shouldUseCompact = newState == .loaded && !hasDescription
            if shouldUseCompact != useCompactPanel {
                useCompactPanel = shouldUseCompact
            }
        }
        .onChange(of: playerState?.currentVideo?.description) { _, newDesc in
            // Description may load after videoDetailsState changes to .loaded
            // Update compact panel state when description changes
            let videoDetailsState = playerState?.videoDetailsState ?? .idle
            let hasDescription = !(newDesc ?? "").isEmpty
            let shouldUseCompact = videoDetailsState == .loaded && !hasDescription
            if shouldUseCompact != useCompactPanel {
                useCompactPanel = shouldUseCompact
            }
        }
    }

    /// Toggle floating panel visibility (for tall videos only)
    private func toggleFloatingPanelVisibility() {
        let newValue = !isPortraitPanelVisible
        withAnimation(.easeInOut(duration: 0.3)) {
            isPortraitPanelVisible = newValue
        }
        navigationCoordinator?.isPortraitPanelVisible = newValue
        appEnvironment?.settingsManager.portraitDetailsPanelLastVisible = newValue
    }

    // MARK: - Portrait Player Area

    /// Player area for portrait layout that separates video (panscan-scaled) from controls.
    /// In fullscreen: controls cover full screen, video scales with panscan.
    /// In normal mode: both video and controls at fit size.
    @ViewBuilder
    func portraitPlayerArea(
        fitWidth: CGFloat,
        fitHeight: CGFloat,
        videoWidth: CGFloat,
        videoHeight: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        isFullscreen: Bool,
        showControls: Bool = true,
        activeLayout: PlayerControlsLayout = .default
    ) -> some View {
        let info = playbackInfo

        // Ensure valid dimensions (guard against negative or zero values)
        let safeVideoWidth = max(1, videoWidth)
        let safeVideoHeight = max(1, videoHeight)
        let safeFitHeight = max(1, fitHeight)
        let safeScreenWidth = max(1, screenWidth)
        let safeScreenHeight = max(1, screenHeight)

        // Container size for the overall player area (video + black bars)
        let containerHeight = isFullscreen ? safeScreenHeight : safeFitHeight

        // Controls ALWAYS use full screen size to prevent layout shifts during fullscreen toggle
        // In non-fullscreen, we offset them so they appear centered in the player area
        // but their internal layout stays constant
        let controlsWidth = safeScreenWidth
        let controlsHeight = safeScreenHeight

        // Calculate vertical offset to center controls in player area when not fullscreen
        // When fullscreen, offset is 0 (controls fill screen)
        // When not fullscreen, offset controls up so they center on the player area
        let controlsVerticalOffset = isFullscreen ? 0.0 : (safeFitHeight - safeScreenHeight) / 2

        ZStack {
            // Black background - fills full screen width to prevent content leaking on sides
            // Hidden during PiP (so system placeholder is visible) UNLESS dismissing (to prevent content leak)
            let isPiPActive = playerState?.pipState == .active
            let isDismissing = appEnvironment?.navigationCoordinator.isPlayerDismissGestureActive == true
            if !isPiPActive || isDismissing {
                Color.black
                    .frame(width: safeScreenWidth, height: containerHeight)
            }

            // Video layer - scaled with panscan, centered
            ZStack {
                // Thumbnail layer - fades in on appear, fades out when player is ready and buffer is loaded
                // During transition, use frozen URL to prevent old thumbnail flash
                if let video = playerState?.currentVideo {
                    let isFirstFrameReady = playerState?.isFirstFrameReady ?? false
                    let isBufferReady = playerState?.isBufferReady ?? false
                    let isAudioOnly = playerState?.currentStream?.isAudioOnly == true
                    let showThumbnail = !info.hasBackend || !isFirstFrameReady || !isBufferReady || isAudioOnly
                    // Use frozen URL during transition, otherwise current video's thumbnail chain
                    let thumbnailURLs = isThumbnailFrozen ? [displayedThumbnailURL].compactMap { $0 } : video.thumbnailURLsByQuality

                    // Hidden loader - loads image into @State (invisible)
                    FallbackLazyImage(urls: thumbnailURLs) { state in
                        Color.clear
                            .onChange(of: state.image) { _, newImage in
                                if let newImage { displayedThumbnailImage = newImage }
                            }
                            .onAppear {
                                if let image = state.image { displayedThumbnailImage = image }
                            }
                    }
                    .frame(width: 1, height: 1)
                    .opacity(0)

                    // Stable display - @State image never flashes during re-renders
                    Group {
                        if let thumbnailImage = displayedThumbnailImage {
                            thumbnailImage.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.black
                        }
                    }
                    .frame(width: safeVideoWidth, height: safeVideoHeight)
                    .opacity(showThumbnail ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showThumbnail)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .animation(.easeInOut(duration: 0.3), value: video.id)
                }

                // Video player layer - fades in when ready
                if let backend = playerService?.currentBackend as? MPVBackend,
                   let playerState,
                   let playerService,
                   info.hasBackend {
                    let isAudioOnlyStream = playerState.currentStream?.isAudioOnly == true
                    MPVVideoView(
                        backend: backend,
                        playerState: playerState,
                        playerService: playerService,
                        showsControls: false, // Controls rendered separately
                        showsDebugOverlay: false // Debug overlay rendered at sheet level
                    )
                    .frame(width: safeVideoWidth, height: safeVideoHeight)
                    // Only show video when both first frame is ready AND buffer is ready
                    // This prevents showing a frozen frame before playback can start smoothly
                    // Hide for audio-only streams - show thumbnail instead
                    .opacity(info.hasBackend && playerState.isFirstFrameReady && playerState.isBufferReady && !isAudioOnlyStream ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: info.hasBackend && playerState.isFirstFrameReady && playerState.isBufferReady && !isAudioOnlyStream)
                }

                // Fallback when no video is set
                if playerState?.currentVideo == nil {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }
            }
            .frame(width: safeVideoWidth, height: safeVideoHeight)

            // Loading overlay - covers full container width (including letterbox bars)
            if playerState?.currentVideo != nil {
                let isWaitingForBuffer = !(playerState?.isBufferReady ?? true)
                thumbnailOverlayContent(
                    isIdle: info.isIdle,
                    isEnded: info.isEnded,
                    isFailed: info.isFailed,
                    isLoading: info.isLoading || isWaitingForBuffer
                )
                .frame(width: safeScreenWidth, height: containerHeight)
            }

            // Controls layer - covers full screen in fullscreen mode, fit size otherwise
            // Only render here if showControls is true (controls will be rendered externally otherwise)
            #if os(iOS)
            if showControls,
               let backend = playerService?.currentBackend,
               backend.backendType == .mpv,
               let playerState,
               let playerService,
               playerState.pipState != .active && !playerState.showDebugOverlay {
                PlayerControlsView(
                    playerState: playerState,
                    onPlayPause: {
                        playerService.togglePlayPause()
                    },
                    onSeek: { time in
                        await playerService.seek(to: time)
                    },
                    onSeekForward: { seconds in
                        playerService.seekForward(by: seconds)
                    },
                    onSeekBackward: { seconds in
                        playerService.seekBackward(by: seconds)
                    },
                    onToggleFullscreen: { [self] in
                        toggleFullscreen()
                    },
                    isFullscreen: !isPortraitPanelVisible,
                    isWidescreenVideo: playerState.displayAspectRatio > 1.0,
                    onClose: { [self] in
                        closeVideo()
                    },
                    onTogglePiP: {
                        if let mpvBackend = playerService.currentBackend as? MPVBackend {
                            mpvBackend.togglePiP()
                        }
                    },
                    onToggleDebug: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            playerState.showDebugOverlay.toggle()
                        }
                    },
                    isWideScreenLayout: isFullscreen, // In fullscreen, use widescreen-style safe area handling
                    onTogglePanel: nil,
                    isPanelVisible: true,
                    panelSide: .right,
                    onToggleOrientationLock: { [weak appEnvironment] in
                        appEnvironment?.settingsManager.inAppOrientationLock.toggle()
                    },
                    isOrientationLocked: inAppOrientationLock,
                    onToggleDetailsVisibility: { [self] in
                        scrollPosition.scrollTo(y: 0)
                        if !isPortraitPanelVisible {
                            navigationCoordinator?.pinchPanscan = 0
                        }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isPortraitPanelVisible.toggle()
                        }
                        navigationCoordinator?.isPortraitPanelVisible = isPortraitPanelVisible
                        appEnvironment?.settingsManager.portraitDetailsPanelLastVisible = isPortraitPanelVisible
                    },
                    onShowSettings: { [self] in
                        showingQualitySheet = true
                    },
                    onPlayNext: {
                        await playerService.playNext()
                    },
                    onPlayPrevious: {
                        await playerService.playPrevious()
                    },
                    onShowQueue: { [self] in
                        presentSheet(.queue())
                    },
                    onVolumeChanged: { [weak appEnvironment] volume in
                        playerService.currentBackend?.volume = volume
                        appEnvironment?.settingsManager.playerVolume = volume
                        appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                    },
                    onMuteToggled: { [weak appEnvironment] in
                        let newMuted = !playerState.isMuted
                        playerService.currentBackend?.isMuted = newMuted
                        playerState.isMuted = newMuted
                        appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                    },
                    currentVideo: playerState.currentVideo,
                    availableCaptions: playerService.availableCaptions,
                    currentCaption: playerService.currentCaption,
                    availableStreams: playerService.availableStreams,
                    currentStream: playerState.currentStream,
                    currentAudioStream: playerState.currentAudioStream,
                    onRateChanged: { rate in
                        playerState.rate = rate
                        playerService.currentBackend?.rate = Float(rate.rawValue)
                    },
                    onCaptionSelected: { caption in
                        playerService.loadCaption(caption)
                    },
                    onStreamSelected: { [self] stream, audioStream in
                        switchToStream(stream, audioStream: audioStream)
                    },
                    embeddedAudioTracks: playerService.embeddedAudioTracks,
                    embeddedSubtitleTracks: playerService.embeddedSubtitleTracks,
                    currentEmbeddedAudioTrackID: playerService.selectedEmbeddedAudioTrackID,
                    currentEmbeddedSubtitleTrackID: playerService.selectedEmbeddedSubtitleTrackID,
                    embeddedVideoTrack: playerService.primaryEmbeddedVideoTrack,
                    onEmbeddedAudioTrackSelected: { trackID in
                        playerService.selectEmbeddedAudioTrack(trackID)
                    },
                    onEmbeddedSubtitleTrackSelected: { trackID in
                        playerService.selectEmbeddedSubtitleTrack(trackID)
                    },
                    panscanValue: navigationCoordinator?.pinchPanscan ?? 0.0,
                    isPanscanAllowed: !isPortraitPanelVisible,
                    onTogglePanscan: { [weak navigationCoordinator] in
                        navigationCoordinator?.togglePanscan()
                    },
                    activeLayout: activeLayout
                )
                .frame(width: controlsWidth, height: controlsHeight)
                .offset(y: controlsVerticalOffset)
            }
            #elseif os(macOS)
            // No backend gate: the backend is created only after the video
            // details fetch, and controls should be visible while loading.
            if let playerState,
               let playerService,
               playerState.pipState != .active && !playerState.showDebugOverlay {
                MacOSPlayerControlsView(
                    playerState: playerState,
                    onPlayPause: {
                        playerService.togglePlayPause()
                    },
                    onSeek: { time in
                        await playerService.seek(to: time)
                    },
                    onSeekForward: { seconds in
                        playerService.seekForward(by: seconds)
                    },
                    onSeekBackward: { seconds in
                        playerService.seekBackward(by: seconds)
                    },
                    isFullscreen: !isPortraitPanelVisible,
                    onClose: { [self] in
                        closeVideo()
                    },
                    onTogglePiP: {
                        if let mpvBackend = playerService.currentBackend as? MPVBackend {
                            mpvBackend.togglePiP()
                        }
                    },
                    onPlayNext: {
                        await playerService.playNext()
                    },
                    onPlayPrevious: {
                        await playerService.playPrevious()
                    },
                    onVolumeChanged: { [weak appEnvironment] volume in
                        playerService.currentBackend?.volume = volume
                        appEnvironment?.settingsManager.playerVolume = volume
                        appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                    },
                    onMuteToggled: { [weak appEnvironment] in
                        let newMuted = !playerState.isMuted
                        playerService.currentBackend?.isMuted = newMuted
                        playerState.isMuted = newMuted
                        appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                    },
                    onShowSettings: { [self] in
                        showingQualitySheet = true
                    },
                    onShowQueue: { [self] in
                        presentSheet(.queue())
                    },
                    onShowPlaylistSelector: { [self] in
                        presentAddToPlaylist()
                    },
                    onRateChanged: { rate in
                        playerState.rate = rate
                        playerService.currentBackend?.rate = Float(rate.rawValue)
                    }
                )
                .frame(width: controlsWidth, height: controlsHeight)
                .offset(y: controlsVerticalOffset)
            }
            #endif

            // Debug overlay
            #if os(iOS)
            if let playerState {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerState.showDebugOverlay = false
                    }
                    .opacity(playerState.showDebugOverlay ? 1 : 0)
                    .allowsHitTesting(playerState.showDebugOverlay)

                VStack {
                    HStack {
                        MPVDebugOverlay(
                            stats: debugStats,
                            isVisible: Binding(
                                get: { playerState.showDebugOverlay },
                                set: { playerState.showDebugOverlay = $0 }
                            ),
                            isLandscape: false
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
                .allowsHitTesting(false)
                .opacity(playerState.showDebugOverlay ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: playerState.showDebugOverlay)
            }
            #endif

            // Debug overlay (macOS)
            #if os(macOS)
            if let playerState, playerState.showDebugOverlay {
                // Tap anywhere to dismiss
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerState.showDebugOverlay = false
                    }

                VStack {
                    HStack {
                        MPVDebugOverlay(
                            stats: debugStats,
                            isVisible: Binding(
                                get: { playerState.showDebugOverlay },
                                set: { playerState.showDebugOverlay = $0 }
                            ),
                            isLandscape: true  // macOS uses landscape layout
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 80) // Avoid window traffic light buttons
                .padding(.top, 16)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            #endif
        }
    }

    // MARK: - Portrait Controls Overlay

    /// Renders just the player controls for portrait mode (used as overlay outside clipped area).
    @ViewBuilder
    func portraitControlsOverlay(
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        fitHeight: CGFloat,
        isFullscreen: Bool,
        forceHidden: Bool = false,
        onTogglePanel: (() -> Void)? = nil,
        isPanelVisible: Bool = true,
        isPanelPinned: Bool = true,
        videoAreaTop: CGFloat = 0,
        videoAreaHeight: CGFloat? = nil,
        videoFitHeight: CGFloat? = nil,
        isTabletop: Bool = false,
        horizontalSafeArea: (leading: CGFloat, trailing: CGFloat) = (0, 0),
        activeLayout: PlayerControlsLayout = .default
    ) -> some View {
        // Controls always use full screen dimensions to prevent layout shifts
        let controlsWidth = max(1, screenWidth)
        let controlsHeight = max(1, screenHeight)
        // Tabletop: controls y=0 is the screen top, so the top bar moves just
        // below the hinge (the center zone starts one top-bar inset lower),
        // and the pinch-to-fill is off
        let topBarOffset: CGFloat = isTabletop ? (videoAreaTop - Self.tabletopTopBarInset + 8) : 0

        #if os(iOS)
        if let backend = playerService?.currentBackend,
           backend.backendType == .mpv,
           let playerState,
           let playerService,
           playerState.pipState != .active && !playerState.showDebugOverlay {
            PlayerControlsView(
                playerState: playerState,
                onPlayPause: {
                    playerService.togglePlayPause()
                },
                onSeek: { time in
                    await playerService.seek(to: time)
                },
                onSeekForward: { seconds in
                    playerService.seekForward(by: seconds)
                },
                onSeekBackward: { seconds in
                    playerService.seekBackward(by: seconds)
                },
                onToggleFullscreen: { [self] in
                    toggleFullscreen()
                },
                isFullscreen: !isPortraitPanelVisible,
                isWidescreenVideo: playerState.displayAspectRatio > 1.0,
                onClose: { [self] in
                    closeVideo()
                },
                onTogglePiP: {
                    if let mpvBackend = backend as? MPVBackend {
                        mpvBackend.togglePiP()
                    }
                },
                onToggleDebug: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        playerState.showDebugOverlay.toggle()
                    }
                },
                isWideScreenLayout: !isPortraitPanelVisible,
                onTogglePanel: onTogglePanel,
                isPanelVisible: isPanelVisible,
                panelSide: .right,
                isPanelPinned: isPanelPinned,
                onToggleOrientationLock: { [weak appEnvironment] in
                    appEnvironment?.settingsManager.inAppOrientationLock.toggle()
                },
                isOrientationLocked: inAppOrientationLock,
                onToggleDetailsVisibility: { [self] in
                    // Hide controls during transition to avoid animation glitch
                    hideControlsDuringTransition = true
                    if !isPortraitPanelVisible {
                        navigationCoordinator?.pinchPanscan = 0
                    }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPortraitPanelVisible.toggle()
                    }
                    navigationCoordinator?.isPortraitPanelVisible = isPortraitPanelVisible
                    appEnvironment?.settingsManager.portraitDetailsPanelLastVisible = isPortraitPanelVisible
                    // Re-enable controls after animation completes (0.35s)
                    // Controls will still be hidden (forceInitialHidden) until user taps
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        hideControlsDuringTransition = false
                    }
                },
                onShowSettings: { [self] in
                    showingQualitySheet = true
                },
                onPlayNext: {
                    await playerService.playNext()
                },
                onPlayPrevious: {
                    await playerService.playPrevious()
                },
                onShowQueue: { [self] in
                    presentSheet(.queue())
                },
                forceInitialHidden: forceHidden,
                videoAreaTop: videoAreaTop,
                videoAreaHeight: videoAreaHeight,
                videoFitHeight: videoFitHeight,
                topBarOffset: topBarOffset,
                horizontalSafeArea: horizontalSafeArea,
                onVolumeChanged: { [weak appEnvironment] volume in
                    playerService.currentBackend?.volume = volume
                    appEnvironment?.settingsManager.playerVolume = volume
                    appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                },
                onMuteToggled: { [weak appEnvironment] in
                    let newMuted = !playerState.isMuted
                    playerService.currentBackend?.isMuted = newMuted
                    playerState.isMuted = newMuted
                    appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                },
                currentVideo: playerState.currentVideo,
                availableCaptions: playerService.availableCaptions,
                currentCaption: playerService.currentCaption,
                availableStreams: playerService.availableStreams,
                currentStream: playerState.currentStream,
                currentAudioStream: playerState.currentAudioStream,
                onRateChanged: { rate in
                    playerState.rate = rate
                    playerService.currentBackend?.rate = Float(rate.rawValue)
                },
                onCaptionSelected: { caption in
                    playerService.loadCaption(caption)
                },
                onStreamSelected: { [self] stream, audioStream in
                    switchToStream(stream, audioStream: audioStream)
                },
                embeddedAudioTracks: playerService.embeddedAudioTracks,
                embeddedSubtitleTracks: playerService.embeddedSubtitleTracks,
                currentEmbeddedAudioTrackID: playerService.selectedEmbeddedAudioTrackID,
                currentEmbeddedSubtitleTrackID: playerService.selectedEmbeddedSubtitleTrackID,
                embeddedVideoTrack: playerService.primaryEmbeddedVideoTrack,
                onEmbeddedAudioTrackSelected: { trackID in
                    playerService.selectEmbeddedAudioTrack(trackID)
                },
                onEmbeddedSubtitleTrackSelected: { trackID in
                    playerService.selectEmbeddedSubtitleTrack(trackID)
                },
                panscanValue: navigationCoordinator?.pinchPanscan ?? 0.0,
                isPanscanAllowed: !isPortraitPanelVisible && !isTabletop,
                onTogglePanscan: { [weak navigationCoordinator] in
                    navigationCoordinator?.togglePanscan()
                },
                activeLayout: activeLayout
            )
            .frame(width: controlsWidth, height: controlsHeight)
        }
        #elseif os(macOS)
        // No backend gate: the backend is created only after the video
        // details fetch, and controls should be visible while loading.
        if let playerState,
           let playerService,
           playerState.pipState != .active && !playerState.showDebugOverlay {
            MacOSPlayerControlsView(
                playerState: playerState,
                onPlayPause: {
                    playerService.togglePlayPause()
                },
                onSeek: { time in
                    await playerService.seek(to: time)
                },
                onSeekForward: { seconds in
                    playerService.seekForward(by: seconds)
                },
                onSeekBackward: { seconds in
                    playerService.seekBackward(by: seconds)
                },
                isFullscreen: !isPortraitPanelVisible,
                onClose: { [self] in
                    closeVideo()
                },
                onTogglePiP: {
                    if let mpvBackend = playerService.currentBackend as? MPVBackend {
                        mpvBackend.togglePiP()
                    }
                },
                onPlayNext: {
                    await playerService.playNext()
                },
                onPlayPrevious: {
                    await playerService.playPrevious()
                },
                onVolumeChanged: { [weak appEnvironment] volume in
                    playerService.currentBackend?.volume = volume
                    appEnvironment?.settingsManager.playerVolume = volume
                    appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                },
                onMuteToggled: { [weak appEnvironment] in
                    let newMuted = !playerState.isMuted
                    playerService.currentBackend?.isMuted = newMuted
                    playerState.isMuted = newMuted
                    appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                },
                onShowSettings: { [self] in
                    showingQualitySheet = true
                },
                onShowQueue: { [self] in
                    presentSheet(.queue())
                },
                onShowPlaylistSelector: { [self] in
                    presentAddToPlaylist()
                },
                onRateChanged: { rate in
                    playerState.rate = rate
                    playerService.currentBackend?.rate = Float(rate.rawValue)
                }
            )
            .frame(width: controlsWidth, height: controlsHeight)
        }
        #endif
    }
}

// MARK: - Widescreen Layout (iOS/macOS only)

#if os(iOS) || os(macOS)

extension ExpandedPlayerSheet {
    // MARK: - Widescreen Content

    /// Widescreen layout with floating panel.
    @ViewBuilder
    func wideScreenContent(video: Video) -> some View {
        WideScreenPlayerLayout(
            playerControlsLayout: playerControlsLayout,
            playerContent: { onTogglePanel, isPanelVisible, isPanelPinned, panelSide, onHidePanel, leadingSafeArea, trailingSafeArea, fullWidth, fullHeight in
                playerAreaForWidescreen(
                    onTogglePanel: onTogglePanel,
                    isPanelVisible: isPanelVisible,
                    isPanelPinned: isPanelPinned,
                    panelSide: panelSide,
                    onHidePanel: onHidePanel,
                    leadingSafeArea: leadingSafeArea,
                    trailingSafeArea: trailingSafeArea,
                    fullWidth: fullWidth,
                    fullHeight: fullHeight
                )
            },
            onChannelTap: video.author.hasRealChannelInfo ? {
                navigationCoordinator?.navigateToChannel(for: video, collapsePlayer: true)
            } : nil,
            onFullscreen: {
                #if os(iOS)
                self.toggleFullscreen()
                #endif
            }
        )
    }

    // MARK: - Corner Content

    /// Corner layout: video top-left, side column, optional below-video
    /// region. Reuses `playerAreaForWidescreen` so the MPV hosting path is
    /// identical to the stacked layout — only the container size differs.
    @ViewBuilder
    func cornerContent(video: Video) -> some View {
        // Seed the panel visibility before the first frame: once the
        // session's default visibility is applied the setting is the truth;
        // until then resolve the preset's landscape default (same policy the
        // sheet's applyPanelDefaultVisibility writes moments later).
        let initialPanelVisible = appEnvironment?.navigationCoordinator.hasAppliedPanelDefaultVisibility == true
            ? (appEnvironment?.settingsManager.landscapeDetailsPanelVisible ?? true)
            : Self.initialPanelVisibility(for: .landscape, settingsManager: appEnvironment?.settingsManager)

        CornerPlayerLayout(
            playerControlsLayout: playerControlsLayout,
            initialPanelVisible: initialPanelVisible,
            initialColumnWidth: appEnvironment?.settingsManager.cornerPanelColumnWidth,
            playerContent: { onTogglePanel, isPanelVisible, width, height in
                // isPanelPinned=true keeps the controls visible alongside the
                // panel regions (corner regions behave like a pinned panel).
                playerAreaForWidescreen(
                    onTogglePanel: onTogglePanel,
                    isPanelVisible: isPanelVisible,
                    isPanelPinned: true,
                    panelSide: .right,
                    onHidePanel: {},
                    leadingSafeArea: 0,
                    trailingSafeArea: 0,
                    fullWidth: width,
                    fullHeight: height
                )
                #if os(iOS)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                                navigationCoordinator?.cornerVideoFrame = frame
                            }
                            .onDisappear {
                                navigationCoordinator?.cornerVideoFrame = .zero
                            }
                    }
                }
                #endif
            },
            onChannelTap: video.author.hasRealChannelInfo ? {
                navigationCoordinator?.navigateToChannel(for: video, collapsePlayer: true)
            } : nil,
            onFullscreen: {
                #if os(iOS)
                self.toggleFullscreen()
                #endif
            },
            isHingeSplit: isHingeSplitActive
        )
    }

    /// The corner layout splits on the hinge while it's partially open.
    private var isHingeSplitActive: Bool {
        #if os(iOS)
        isTabletopHinge
        #else
        false
        #endif
    }

    // MARK: - Widescreen Player Area

    /// Player area for widescreen layout with panel support.
    @ViewBuilder
    func playerAreaForWidescreen(
        onTogglePanel: @escaping () -> Void,
        isPanelVisible: Bool,
        isPanelPinned: Bool,
        panelSide: FloatingPanelSide,
        onHidePanel: @escaping () -> Void,
        leadingSafeArea: CGFloat = 0,
        trailingSafeArea: CGFloat = 0,
        fullWidth: CGFloat = 0,
        fullHeight: CGFloat = 0
    ) -> some View {
        let info = playbackInfo

        // Hide controls when floating panel is visible (not pinned)
        // Controls only shown when panel is pinned or panel is not visible
        let shouldShowControls = isPanelPinned || !isPanelVisible

        // Use consistent aspect ratio - actual video ratio when known, otherwise 16:9
        // Ensure valid aspect ratio (avoid division by zero)
        let rawAspectRatio = playerState?.displayAspectRatio ?? (16.0 / 9.0)
        let aspectRatio = rawAspectRatio > 0 ? rawAspectRatio : (16.0 / 9.0)

        // Use geometry passed from WideScreenPlayerLayout (no nested GeometryReader needed)
        // Calculate usable area after accounting for safe areas
        let availableWidth = max(1, fullWidth - leadingSafeArea - trailingSafeArea)
        let availableHeight = max(1, fullHeight)

        // Calculate offset for controls positioning (used for animation)
        let controlsOffset = (leadingSafeArea - trailingSafeArea) / 2

        #if os(iOS)
        // Foldable in book posture (hinge partially open, landscape, the
        // player spanning the fold): the buttons move to the trailing half so
        // nothing sits on the hinge; dimming and taps still cover the whole
        // screen. The corner layout's hinge split with panels shown already
        // gives the player one half only.
        let bookFoldButtonsInset: CGFloat = {
            guard isTabletopHinge,
                  fullWidth > fullHeight,
                  fullWidth >= Self.minWidthForCornerLayout else { return 0 }
            // Controls frame starts at the leading safe area
            return max(0, fullWidth / 2 + Self.bookFoldHingeGap - leadingSafeArea)
        }()
        #endif

        // Calculate video frame size based on panscan
        // At panscan 0: aspect-fit (may have black bars)
        // At panscan 1: aspect-fill (cropped to fill)
        let fitSize: CGSize = {
            let widthBasedHeight = availableWidth / aspectRatio
            let heightBasedWidth = availableHeight * aspectRatio
            if widthBasedHeight <= availableHeight {
                return CGSize(width: max(1, availableWidth), height: max(1, widthBasedHeight))
            } else {
                return CGSize(width: max(1, heightBasedWidth), height: max(1, availableHeight))
            }
        }()

        let fillSize: CGSize = {
            let widthBasedHeight = availableWidth / aspectRatio
            let heightBasedWidth = availableHeight * aspectRatio
            if widthBasedHeight >= availableHeight {
                return CGSize(width: max(1, availableWidth), height: max(1, widthBasedHeight))
            } else {
                return CGSize(width: max(1, heightBasedWidth), height: max(1, availableHeight))
            }
        }()

        #if os(iOS)
        // Use UIKit pinch gesture panscan from NavigationCoordinator
        let panscan = navigationCoordinator?.pinchPanscan ?? 0.0
        #else
        let panscan = 0.0
        #endif

        // Interpolate between fit and fill based on panscan
        let videoWidth = max(1, fitSize.width + (fillSize.width - fitSize.width) * panscan)
        let videoHeight = max(1, fitSize.height + (fillSize.height - fitSize.height) * panscan)

        ZStack {
            // Black background fills entire space (extends under safe areas)
            Color.black

            // Content container - constrained by safe area padding
            // Both video and controls share the same constrained space
            ZStack {
                // Invisible layer to force ZStack to fill frame
                Color.black.opacity(0.001)
                    .frame(width: availableWidth, height: availableHeight)

                // Video layer - sized based on panscan, centered within available area
                ZStack {
                    // Thumbnail layer - fades in on appear, fades out when player is ready and buffer is loaded
                    // During transition, use frozen URL to prevent old thumbnail flash
                    if let video = playerState?.currentVideo {
                        let isFirstFrameReady = playerState?.isFirstFrameReady ?? false
                        let isBufferReady = playerState?.isBufferReady ?? false
                        let isAudioOnly = playerState?.currentStream?.isAudioOnly == true
                        let showThumbnail = !info.hasBackend || !isFirstFrameReady || !isBufferReady || isAudioOnly
                        // Use frozen URL during transition, otherwise current video's thumbnail chain
                        let thumbnailURLs = isThumbnailFrozen ? [displayedThumbnailURL].compactMap { $0 } : video.thumbnailURLsByQuality

                        // Hidden loader - loads image into @State (invisible)
                        FallbackLazyImage(urls: thumbnailURLs) { state in
                            Color.clear
                                .onChange(of: state.image) { _, newImage in
                                    if let newImage { displayedThumbnailImage = newImage }
                                }
                                .onAppear {
                                    if let image = state.image { displayedThumbnailImage = image }
                                }
                        }
                        .frame(width: 1, height: 1)
                        .opacity(0)

                        // Stable display - @State image never flashes during re-renders
                        Group {
                            if let thumbnailImage = displayedThumbnailImage {
                                thumbnailImage.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.black
                            }
                        }
                        .frame(width: videoWidth, height: videoHeight)
                        .opacity(showThumbnail ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: showThumbnail)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        .animation(.easeInOut(duration: 0.3), value: video.id)
                    }

                    // Video player layer - fades in when ready
                    if let backend = playerService?.currentBackend as? MPVBackend,
                       let playerState,
                       let playerService,
                       info.hasBackend {
                        let isAudioOnlyStream = playerState.currentStream?.isAudioOnly == true
                        MPVVideoView(
                            backend: backend,
                            playerState: playerState,
                            playerService: playerService,
                            showsControls: false, // Controls rendered separately at full size
                            isWideScreenLayout: true,
                            onTogglePanel: onTogglePanel,
                            isPanelVisible: isPanelVisible,
                            panelSide: panelSide
                        )
                        .frame(width: videoWidth, height: videoHeight)
                        // Only show video when both first frame is ready AND buffer is ready
                        // This prevents showing a frozen frame before playback can start smoothly
                        // Hide for audio-only streams - show thumbnail instead
                        .opacity(info.hasBackend && playerState.isFirstFrameReady && playerState.isBufferReady && !isAudioOnlyStream ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: info.hasBackend && playerState.isFirstFrameReady && playerState.isBufferReady && !isAudioOnlyStream)
                    }

                    // Fallback when no video is set
                    if playerState?.currentVideo == nil {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.large)
                    }
                }
                .frame(width: videoWidth, height: videoHeight)
                .geometryGroup()
                .clipped()

                // Loading overlay - covers full available area (including letterbox bars)
                if playerState?.currentVideo != nil {
                    let isWaitingForBuffer = !(playerState?.isBufferReady ?? true)
                    thumbnailOverlayContent(
                        isIdle: info.isIdle,
                        isEnded: info.isEnded,
                        isFailed: info.isFailed,
                        isLoading: info.isLoading || isWaitingForBuffer
                    )
                    .frame(width: availableWidth, height: availableHeight)
                }
            }
            .frame(width: availableWidth, height: availableHeight)
            .position(x: leadingSafeArea + availableWidth / 2, y: availableHeight / 2)
            .clipped()

            // Controls layer - positioned using offset for smooth animation
            // Hidden when floating panel is visible (unless paused)
            #if os(iOS)
            if let backend = playerService?.currentBackend,
               backend.backendType == .mpv,
               let playerState,
               let playerService,
               shouldShowControls,
               playerState.pipState != .active && !playerState.showDebugOverlay {
                // Controls using offset for smooth animation when panel side changes
                PlayerControlsView(
                    playerState: playerState,
                    onPlayPause: {
                        playerService.togglePlayPause()
                    },
                    onSeek: { time in
                        await playerService.seek(to: time)
                    },
                    onSeekForward: { seconds in
                        playerService.seekForward(by: seconds)
                    },
                    onSeekBackward: { seconds in
                        playerService.seekBackward(by: seconds)
                    },
                    onToggleFullscreen: { [self] in
                        toggleFullscreen()
                    },
                    isFullscreen: true, // In widescreen layout = fullscreen
                    isWidescreenVideo: playerState.displayAspectRatio > 1.0,
                    onClose: { [self] in
                        closeVideo()
                    },
                    onTogglePiP: {
                        if let mpvBackend = playerService.currentBackend as? MPVBackend {
                            mpvBackend.togglePiP()
                        }
                    },
                    onToggleDebug: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            playerState.showDebugOverlay.toggle()
                        }
                    },
                    isWideScreenLayout: !(isPanelPinned && isPanelVisible),
                    onTogglePanel: onTogglePanel,
                    isPanelVisible: isPanelVisible,
                    panelSide: panelSide,
                    isPanelPinned: isPanelPinned,
                    isCornerLayout: appEnvironment?.navigationCoordinator.isCornerLayoutActive == true,
                    onToggleOrientationLock: { [weak appEnvironment] in
                        appEnvironment?.settingsManager.inAppOrientationLock.toggle()
                    },
                    isOrientationLocked: inAppOrientationLock,
                    onShowSettings: { [self] in
                        showingQualitySheet = true
                    },
                    onPlayNext: {
                        await playerService.playNext()
                    },
                    onPlayPrevious: {
                        await playerService.playPrevious()
                    },
                    onShowQueue: { [self] in
                        presentSheet(.queue())
                    },
                    videoAreaTop: (availableHeight - videoHeight) / 2,
                    videoAreaHeight: videoHeight,
                    videoFitHeight: fitSize.height,
                    onVolumeChanged: { [weak appEnvironment] volume in
                        playerService.currentBackend?.volume = volume
                        appEnvironment?.settingsManager.playerVolume = volume
                        appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                    },
                    onMuteToggled: { [weak appEnvironment] in
                        let newMuted = !playerState.isMuted
                        playerService.currentBackend?.isMuted = newMuted
                        playerState.isMuted = newMuted
                        appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                    },
                    currentVideo: playerState.currentVideo,
                    availableCaptions: playerService.availableCaptions,
                    currentCaption: playerService.currentCaption,
                    availableStreams: playerService.availableStreams,
                    currentStream: playerState.currentStream,
                    currentAudioStream: playerState.currentAudioStream,
                    onRateChanged: { rate in
                        playerState.rate = rate
                        playerService.currentBackend?.rate = Float(rate.rawValue)
                    },
                    onCaptionSelected: { caption in
                        playerService.loadCaption(caption)
                    },
                    onStreamSelected: { [self] stream, audioStream in
                        switchToStream(stream, audioStream: audioStream)
                    },
                    embeddedAudioTracks: playerService.embeddedAudioTracks,
                    embeddedSubtitleTracks: playerService.embeddedSubtitleTracks,
                    currentEmbeddedAudioTrackID: playerService.selectedEmbeddedAudioTrackID,
                    currentEmbeddedSubtitleTrackID: playerService.selectedEmbeddedSubtitleTrackID,
                    embeddedVideoTrack: playerService.primaryEmbeddedVideoTrack,
                    onEmbeddedAudioTrackSelected: { trackID in
                        playerService.selectEmbeddedAudioTrack(trackID)
                    },
                    onEmbeddedSubtitleTrackSelected: { trackID in
                        playerService.selectEmbeddedSubtitleTrack(trackID)
                    },
                    panscanValue: navigationCoordinator?.pinchPanscan ?? 0.0,
                    // Corner layout: the video owns its own region, so it can
                    // fill it even with the panels showing
                    isPanscanAllowed: !(isPanelPinned && isPanelVisible)
                        || appEnvironment?.navigationCoordinator.isCornerLayoutActive == true,
                    onTogglePanscan: { [weak navigationCoordinator] in
                        navigationCoordinator?.togglePanscan()
                    },
                    activeLayout: playerControlsLayout,
                    buttonsLeadingInset: bookFoldButtonsInset
                )
                .frame(width: availableWidth, height: availableHeight)
                .offset(x: controlsOffset)
                // DEBUG: Show layout values when setting enabled
                .overlay(alignment: panelSide == .right ? .topLeading : .topTrailing) {
                    if appEnvironment?.settingsManager.showPlayerAreaDebug == true {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Layout (yellow):")
                                .fontWeight(.bold)
                            Text(verbatim: "leadSA: \(Int(leadingSafeArea)) trailSA: \(Int(trailingSafeArea))")
                            Text(verbatim: "availW: \(Int(availableWidth)) fullW: \(Int(fullWidth))")
                            Text(verbatim: "fullH: \(Int(fullHeight)) offset: \(Int(controlsOffset))")
                            Text(verbatim: "pinned: \(isPanelPinned ? "Y" : "N") vis: \(isPanelVisible ? "Y" : "N") side: \(panelSide == .left ? "L" : "R")")
                            #if os(iOS)
                            let orientation = UIApplication.shared.foregroundWindowScene?.interfaceOrientation
                            Text(verbatim: "orient: \(orientation == .landscapeLeft ? "LL" : orientation == .landscapeRight ? "LR" : "P")")
                            #endif
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.yellow)
                        .padding(4)
                        .background(.black.opacity(0.8))
                        .padding(panelSide == .right ? .leading : .trailing, 8)
                        .padding(.top, 50)
                    }
                }
                .overlay {
                    if appEnvironment?.settingsManager.showPlayerAreaDebug == true {
                        Rectangle()
                            .stroke(Color.red, lineWidth: 2)
                    }
                }
            }
            #elseif os(macOS)
            // No backend gate: the backend is created only after the video
            // details fetch, and controls should be visible while loading.
            if let playerState,
               let playerService,
               playerState.pipState != .active && !playerState.showDebugOverlay {
                MacOSPlayerControlsView(
                    playerState: playerState,
                    onPlayPause: {
                        playerService.togglePlayPause()
                    },
                    onSeek: { time in
                        await playerService.seek(to: time)
                    },
                    onSeekForward: { seconds in
                        playerService.seekForward(by: seconds)
                    },
                    onSeekBackward: { seconds in
                        playerService.seekBackward(by: seconds)
                    },
                    onToggleFullscreen: {
                        // Toggle native macOS fullscreen (drops the floating
                        // config first so a pinned window can enter fullscreen)
                        ExpandedPlayerWindowManager.shared.toggleFullScreen()
                    },
                    // The coordinator flag covers the inline overlay (where the
                    // main window is the fullscreen one) and, being @Observable,
                    // refreshes the button icon on toggle; the keyWindow check
                    // covers the separate-window presentation.
                    isFullscreen: navigationCoordinator?.isMacInlinePlayerFullScreen == true
                        || NSApp.keyWindow?.styleMask.contains(.fullScreen) == true,
                    // Esc collapses the inline overlay to the mini bar; in
                    // separate-window mode Esc keeps its default handling.
                    onCollapse: appEnvironment?.settingsManager.macPlayerSeparateWindow == true
                        ? nil
                        : { [weak navigationCoordinator] in
                            navigationCoordinator?.isPlayerExpanded = false
                        },
                    onClose: { [self] in
                        closeVideo()
                    },
                    onTogglePiP: {
                        if let mpvBackend = playerService.currentBackend as? MPVBackend {
                            mpvBackend.togglePiP()
                        }
                    },
                    onPlayNext: {
                        await playerService.playNext()
                    },
                    onPlayPrevious: {
                        await playerService.playPrevious()
                    },
                    onVolumeChanged: { [weak appEnvironment] volume in
                        playerService.currentBackend?.volume = volume
                        appEnvironment?.settingsManager.playerVolume = volume
                        appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                    },
                    onMuteToggled: { [weak appEnvironment] in
                        let newMuted = !playerState.isMuted
                        playerService.currentBackend?.isMuted = newMuted
                        playerState.isMuted = newMuted
                        appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
                    },
                    onShowSettings: { [self] in
                        showingQualitySheet = true
                    },
                    onShowQueue: { [self] in
                        presentSheet(.queue())
                    },
                    onShowPlaylistSelector: { [self] in
                        presentAddToPlaylist()
                    },
                    onTitleTap: {
                        onTogglePanel()
                    },
                    // Only a floating (unpinned) panel covers the video and
                    // takes the controls with it. Pinned and corner layout
                    // panels sit beside the video: showing them again (e.g.
                    // the restore after native fullscreen) must not leave the
                    // controls hidden with hover unable to bring them back.
                    isDetailsPanelVisible: isPanelVisible && !isPanelPinned,
                    onRateChanged: { rate in
                        playerState.rate = rate
                        playerService.currentBackend?.rate = Float(rate.rawValue)
                    }
                )
                .frame(width: availableWidth, height: availableHeight)
                .offset(x: controlsOffset)
            }
            #endif

            #if os(iOS)
            // Debug overlay - tap to dismiss layer (widescreen)
            if let playerState, playerState.showDebugOverlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerState.showDebugOverlay = false
                    }
            }

            // Debug overlay content (widescreen)
            if let playerState, playerState.showDebugOverlay {
                VStack {
                    HStack {
                        MPVDebugOverlay(
                            stats: debugStats,
                            isVisible: Binding(
                                get: { playerState.showDebugOverlay },
                                set: { playerState.showDebugOverlay = $0 }
                            ),
                            isLandscape: true
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, windowSafeAreaInsets.left + 16)
                .padding(.top, windowSafeAreaInsets.top + 16)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            #endif

            #if os(macOS)
            // Debug overlay - tap to dismiss layer (widescreen macOS)
            if let playerState, playerState.showDebugOverlay {
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerState.showDebugOverlay = false
                    }

                // Debug overlay content (widescreen macOS)
                VStack {
                    HStack {
                        MPVDebugOverlay(
                            stats: debugStats,
                            isVisible: Binding(
                                get: { playerState.showDebugOverlay },
                                set: { playerState.showDebugOverlay = $0 }
                            ),
                            isLandscape: true
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, 80) // Avoid window traffic light buttons
                .padding(.top, 16)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            #endif

            // Tap to hide panel overlay - only active when panel visible and not pinned
            if isPanelVisible && !isPanelPinned {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onHidePanel()
                    }
            }
        }
        .clipped() // Clip to screen bounds
        .animation(.easeInOut(duration: 0.3), value: panelSide)
    }
}

#endif

#endif
