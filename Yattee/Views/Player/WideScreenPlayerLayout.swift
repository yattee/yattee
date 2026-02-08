//
//  WideScreenPlayerLayout.swift
//  Yattee
//
//  Widescreen layout with video player and floating details panel.
//  Supports two modes:
//  - Overlay: Panel floats over full-width player, appears with controls
//  - Pinned: Player resizes to make room for panel
//

import SwiftUI

#if os(iOS) || os(macOS)

struct WideScreenPlayerLayout<PlayerContent: View>: View {
    let playerControlsLayout: PlayerControlsLayout

    @ViewBuilder let playerContent: (
        _ onTogglePanel: @escaping () -> Void,
        _ isPanelVisible: Bool,
        _ isPanelPinned: Bool,
        _ panelSide: FloatingPanelSide,
        _ onHidePanel: @escaping () -> Void,
        _ leadingSafeArea: CGFloat,
        _ trailingSafeArea: CGFloat,
        _ fullWidth: CGFloat,
        _ fullHeight: CGFloat
    ) -> PlayerContent

    // Callbacks for panel actions
    let onChannelTap: (() -> Void)?
    let onFullscreen: (() -> Void)?

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var controlsVisible = false
    @State private var isPanelVisible = false // Local state synced with settingsManager
    @State private var lastVideoId: String? // Track video ID to detect actual video changes
    @State private var panelWidth: CGFloat = FloatingDetailsPanel.defaultPanelWidth

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
    private var playerState: PlayerState? { appEnvironment?.playerService.state }

    // Read video from playerState for reactive updates
    private var video: Video? { playerState?.currentVideo }

    private var panelSide: FloatingPanelSide {
        settingsManager?.floatingDetailsPanelSide ?? .left
    }

    private var isPanelPinned: Bool {
        settingsManager?.landscapeDetailsPanelPinned ?? false
    }

    /// Base panel width including grabber and padding (without safe area)
    private var basePanelWidth: CGFloat {
        panelWidth + 20 + 12 // panelWidth + grabber (20pt) + outer edge padding (12pt)
    }

    /// Maximum panel width based on available width and pinned state
    private func maxPanelWidth(availableWidth: CGFloat) -> CGFloat {
        let minWidth = FloatingDetailsPanel.minPanelWidth
        let minVideoWidth: CGFloat = 400
        if isPanelPinned {
            // Pinned: leave at least 300pt for video
            return max(minWidth, availableWidth - minVideoWidth)
        } else {
            // Unpinned: 80% of available width, capped at 1000pt
            return max(minWidth, min(availableWidth * 0.8, 1000))
        }
    }

    /// Calculate safe area padding for panel outer edge
    /// Always use full safe area - rounded corner side is already small
    private func panelSafeAreaPadding(safeAreaLeft: CGFloat, safeAreaRight: CGFloat) -> CGFloat {
        if panelSide == .left {
            return safeAreaLeft
        } else {
            return safeAreaRight
        }
    }

    /// Total panel width including safe area padding
    /// Must include the same padding applied to the panel view
    private func totalPanelWidth(safeAreaLeft: CGFloat, safeAreaRight: CGFloat) -> CGFloat {
        basePanelWidth + panelSafeAreaPadding(safeAreaLeft: safeAreaLeft, safeAreaRight: safeAreaRight)
    }

    /// Whether to show the panel
    private var shouldShowPanel: Bool {
        isPanelVisible
    }

    /// Toggle panel visibility from controls
    private func togglePanelFromControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isPanelVisible.toggle()
            settingsManager?.landscapeDetailsPanelVisible = isPanelVisible
        }
    }

    /// Hide the panel completely
    private func hidePanel() {
        isPanelVisible = false
        settingsManager?.landscapeDetailsPanelVisible = false
    }

    /// Get safe area insets from window scene (geometry reader insets are 0 when .ignoresSafeArea is used)
    private var windowSafeAreaInsets: EdgeInsets {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first
        else { return EdgeInsets() }
        let insets = window.safeAreaInsets
        return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
        #else
        return EdgeInsets()
        #endif
    }

    /// Get full screen bounds from window scene (ignores safe area constraints from parent)
    /// On macOS, this is not used - geometry reader size is used directly
    private var windowSceneBounds: CGSize {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first
        else {
            // Fallback to screen bounds
            let screen = UIScreen.main.bounds
            return CGSize(width: max(screen.width, screen.height), height: min(screen.width, screen.height))
        }
        // Window frame gives actual size including orientation
        return window.frame.size
        #else
        return .zero // Not used on macOS - geometry reader size is used directly
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            // On iOS: Use window bounds to get full size (avoids safe area constraint from parent)
            // On macOS: Use geometry reader size directly (no safe area concerns, window is the source of truth)
            #if os(iOS)
            let windowBounds = windowSceneBounds
            let availableWidth = windowBounds.width
            let availableHeight = windowBounds.height
            let safeAreaLeft = windowSafeAreaInsets.leading
            let safeAreaRight = windowSafeAreaInsets.trailing
            #else
            let availableWidth = geometry.size.width
            let availableHeight = geometry.size.height
            let safeAreaLeft: CGFloat = 0
            let safeAreaRight: CGFloat = 0
            #endif

            // Safe area strategy:
            // - Left side (Dynamic Island): Always respect full safe area - content would be cut off
            // - Right side (rounded corners): Can extend to edge - content still visible
            // - Panel: Use half safe area on outer edge to get closer to edge while keeping content visible

            // Calculate total panel width including safe area padding
            let totalPanelW = totalPanelWidth(safeAreaLeft: safeAreaLeft, safeAreaRight: safeAreaRight)

            // Detect which side has Dynamic Island based on interface orientation
            // Note: Can't use safe area comparison because both sides have similar values (~62px each)
            #if os(iOS)
            let interfaceOrientation = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .interfaceOrientation ?? .unknown
            // landscapeLeft = home/gesture bar on left = Dynamic Island on RIGHT
            // landscapeRight = home/gesture bar on right = Dynamic Island on LEFT
            let isDynamicIslandOnLeft = interfaceOrientation == .landscapeRight
            let isDynamicIslandOnRight = interfaceOrientation == .landscapeLeft
            #else
            let isDynamicIslandOnLeft = safeAreaLeft > safeAreaRight
            let isDynamicIslandOnRight = safeAreaRight > safeAreaLeft
            #endif

            // Calculate Dynamic Island safe area on the side opposite to panel
            // Video must not extend into Dynamic Island
            let opposingDynamicIslandSafeArea: CGFloat = {
                guard isPanelPinned && isPanelVisible else { return 0 }
                if panelSide == .right && isDynamicIslandOnLeft {
                    return safeAreaLeft
                } else if panelSide == .left && isDynamicIslandOnRight {
                    return safeAreaRight
                }
                return 0
            }()

            // Calculate player width based on pinned state
            let _ = isPanelPinned && isPanelVisible
                ? availableWidth - totalPanelW - opposingDynamicIslandSafeArea
                : availableWidth

            ZStack {
                // Black background - extends under status bar and home indicator
                Color.black
                    .ignoresSafeArea(.all)

                // Calculate safe areas to pass to player content
                // When panel is pinned, the side with the panel needs space for it
                // The opposite side needs space for Dynamic Island if present
                let leadingSafeArea: CGFloat = {
                    guard isPanelPinned && isPanelVisible else { return 0 }
                    if panelSide == .left {
                        return totalPanelW
                    } else if isDynamicIslandOnLeft {
                        return safeAreaLeft
                    }
                    return 0
                }()

                let trailingSafeArea: CGFloat = {
                    guard isPanelPinned && isPanelVisible else { return 0 }
                    if panelSide == .right {
                        return totalPanelW
                    } else if isDynamicIslandOnRight {
                        return safeAreaRight
                    }
                    return 0
                }()

                // Player content - fills entire space, handles safe areas internally
                // Pass full geometry so playerContent doesn't need its own GeometryReader
                playerContent(
                    togglePanelFromControls,
                    isPanelVisible,
                    isPanelPinned,
                    panelSide,
                    { withAnimation(.easeInOut(duration: 0.3)) { hidePanel() } },
                    leadingSafeArea,
                    trailingSafeArea,
                    availableWidth,
                    availableHeight
                )

                // Panel container
                // Dynamic Island side needs full safe area, rounded corner side needs half
                let panelOuterPadding = panelSafeAreaPadding(safeAreaLeft: safeAreaLeft, safeAreaRight: safeAreaRight)

                // Panel - always in hierarchy, visibility controlled via opacity
                panelContainer(
                    safeAreaPadding: panelOuterPadding,
                    availableWidth: availableWidth,
                    availableHeight: availableHeight
                )
                .opacity(shouldShowPanel ? 1 : 0)
                .allowsHitTesting(shouldShowPanel)

            }
            .animation(.easeInOut(duration: 0.3), value: isPanelPinned)
            .animation(.easeInOut(duration: 0.3), value: isPanelVisible)
            .animation(.easeInOut(duration: 0.3), value: panelSide)
            .animation(.easeInOut(duration: 0.3), value: controlsVisible)
        }
        .onChange(of: playerState?.controlsVisible) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = newValue ?? false
            }
        }
        .onChange(of: video?.id) { _, newId in
            // Only reset panel state when video actually changes (not on view recreation)
            guard let newId, lastVideoId != newId.videoID else { return }
            lastVideoId = newId.videoID

            // Reset comments state (stored in PlayerState)
            playerState?.comments = []
            playerState?.commentsState = .idle
            playerState?.commentsContinuation = nil

            // Panel state remains unchanged - don't modify visibility or expanded state
        }
        .onAppear {
            controlsVisible = playerState?.controlsVisible ?? false

            // Track initial video ID
            if lastVideoId == nil {
                lastVideoId = video?.id.videoID
            }

            // Initialize panel state from settings (respect user/system-set visibility)
            isPanelVisible = settingsManager?.landscapeDetailsPanelVisible ?? false
            // Don't override settingsManager values - they were already set by ExpandedPlayerSheet

            // Load saved panel width from settings
            if let savedWidth = settingsManager?.floatingDetailsPanelWidth, savedWidth > 0 {
                panelWidth = savedWidth
            }
        }
        .onChange(of: panelWidth) { _, newWidth in
            // Persist panel width changes to settings
            settingsManager?.floatingDetailsPanelWidth = newWidth
        }
        .ignoresSafeArea(.all)
        #if os(iOS)
        .persistentSystemOverlays(.hidden)
        .playerStatusBarHidden(true)
        #endif
    }

    // MARK: - Panel Container

    /// Panel container for the floating details panel
    @ViewBuilder
    private func panelContainer(safeAreaPadding: CGFloat, availableWidth: CGFloat, availableHeight: CGFloat) -> some View {
        // Panel dimensions
        let panelHeight = availableHeight - 24 // 12pt top + 12pt bottom padding

        ZStack(alignment: panelSide == .right ? .topTrailing : .topLeading) {
            detailsPanel(availableWidth: availableWidth)
                .frame(height: panelHeight)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .padding(panelSide == .left ? .leading : .trailing, safeAreaPadding + 12)
                .transition(.scale(scale: 0.9, anchor: panelSide == .right ? .topTrailing : .topLeading).combined(with: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelSide == .right ? .topTrailing : .topLeading)
    }

    // MARK: - Details Panel

    @ViewBuilder
    private func detailsPanel(availableWidth: CGFloat) -> some View {
        FloatingDetailsPanel(
            onPinToggle: {
                if isPanelPinned {
                    // Unpinning - convert to floating mode (don't close)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        settingsManager?.landscapeDetailsPanelPinned = false
                    }
                } else {
                    // Pinning - ensure panel is visible first
                    isPanelVisible = true
                    settingsManager?.landscapeDetailsPanelVisible = true

                    // Animate panscan to zero and pin concurrently for smooth transition
                    appEnvironment?.navigationCoordinator.animatePanscanToZero(completion: nil)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        settingsManager?.landscapeDetailsPanelPinned = true
                    }
                }
            },
            onAlignmentToggle: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    settingsManager?.floatingDetailsPanelSide = panelSide.opposite
                }
            },
            isPinned: isPanelPinned,
            panelSide: panelSide,
            onChannelTap: onChannelTap,
            onFullscreen: onFullscreen,
            panelWidth: $panelWidth,
            availableWidth: availableWidth,
            maxPanelWidth: maxPanelWidth(availableWidth: availableWidth),
            playerControlsLayout: playerControlsLayout
        )
    }

    /// Returns the first enabled Yattee Server instance URL, if any.
    private var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }
}

#endif
