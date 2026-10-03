//
//  ContentView.swift
//  Yattee
//
//  Root content view with tab-based navigation.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Group {
            if let appEnvironment {
                #if os(iOS)
                AdaptiveTabView(appEnvironment: appEnvironment)
                #elseif os(macOS)
                unifiedContentView(appEnvironment: appEnvironment)
                #elseif os(tvOS)
                unifiedContentView(appEnvironment: appEnvironment)
                #endif
            } else {
                ProgressView(String(localized: "common.loading"))
            }
        }
        .toastOverlay()
    }

    // MARK: - Unified Content View (macOS 15+, tvOS 18+)

    @ViewBuilder
    private func unifiedContentView(appEnvironment: AppEnvironment) -> some View {
        ZStack(alignment: .bottom) {
            #if os(macOS)
            UnifiedTabView(router: appEnvironment.navigationCoordinator.router)
            .environment(appEnvironment.settingsManager)
            #elseif os(tvOS)
            UnifiedTabView(router: appEnvironment.navigationCoordinator.router)
            .environment(appEnvironment.settingsManager)
            #endif

            // Mini player overlay (macOS only)
            #if os(macOS)
            miniPlayerOverlay(appEnvironment: appEnvironment)

            // Inline expanded player: presented as a full-window overlay
            // (no native sheet — a window with an attached sheet can't go
            // fullscreen, so fullscreen is just the window's native toggle).
            if isInlinePlayerOverlayActive(appEnvironment: appEnvironment) {
                ZStack {
                    Color.black
                    ExpandedPlayerSheet(
                        initialPortraitPanelVisible: ExpandedPlayerSheet.initialPortraitPanelVisibility(
                            settingsManager: appEnvironment.settingsManager
                        )
                    )
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
            #endif
        }
        #if os(macOS)
        // Registers the hosting window so the inline overlay targets the real
        // main window even when another window (e.g. Settings) has focus.
        .background(MainContentWindowReader())
        .animation(.easeInOut(duration: 0.2), value: isInlinePlayerOverlayActive(appEnvironment: appEnvironment))
        .onChange(of: isInlinePlayerOverlayActive(appEnvironment: appEnvironment)) { _, active in
            if active {
                ExpandedPlayerWindowManager.shared.beginInlineOverlay()
            } else {
                ExpandedPlayerWindowManager.shared.endInlineOverlay()
            }
        }
        .onChange(of: appEnvironment.navigationCoordinator.playerExpandTrigger) { _, _ in
            if appEnvironment.settingsManager.macPlayerSeparateWindow {
                presentExpandedPlayerWindow(appEnvironment: appEnvironment)
            }
        }
        .onChange(of: appEnvironment.navigationCoordinator.isPlayerExpanded) { _, isExpanded in
            if !isExpanded {
                ExpandedPlayerWindowManager.shared.hide()
            }
        }
        .onChange(of: appEnvironment.settingsManager.macPlayerSeparateWindow) { _, separateWindow in
            guard appEnvironment.navigationCoordinator.isPlayerExpanded else { return }

            if separateWindow {
                // Inline overlay → separate window: the overlay unmounts via the
                // presentation condition; present the window directly.
                presentExpandedPlayerWindow(appEnvironment: appEnvironment)
            } else {
                // Separate window → inline overlay: hide the window so the overlay
                // (isPlayerExpanded && !separateWindow) takes over.
                ExpandedPlayerWindowManager.shared.hide(animated: false)
            }
        }
        .onChange(of: appEnvironment.settingsManager.macPlayerFloating) { _, floating in
            guard appEnvironment.navigationCoordinator.isPlayerExpanded,
                  appEnvironment.settingsManager.macPlayerSeparateWindow else { return }
            ExpandedPlayerWindowManager.shared.updateWindowLevel(floating: floating)
        }
        .sheet(isPresented: Binding(
            get: { appEnvironment.navigationCoordinator.isMiniPlayerQueueSheetPresented },
            set: { appEnvironment.navigationCoordinator.isMiniPlayerQueueSheetPresented = $0 }
        )) {
            QueueManagementSheet()
        }
        .sheet(isPresented: Binding(
            get: { appEnvironment.navigationCoordinator.isMiniPlayerPlaylistSheetPresented },
            set: { appEnvironment.navigationCoordinator.isMiniPlayerPlaylistSheetPresented = $0 }
        )) {
            if let video = appEnvironment.playerService.state.currentVideo {
                PlaylistSelectorSheet(video: video)
            }
        }
        #elseif os(tvOS)
        .fullScreenCover(isPresented: Binding(
            get: { appEnvironment.navigationCoordinator.isPlayerExpanded },
            set: { appEnvironment.navigationCoordinator.isPlayerExpanded = $0 }
        )) {
            TVPlayerView()
        }
        #endif
    }

    #if os(macOS)
    private func presentExpandedPlayerWindow(appEnvironment: AppEnvironment) {
        ExpandedPlayerWindowManager.shared.show(with: appEnvironment, animated: true)
    }

    /// Whether the inline (non-separate-window) expanded player overlay should
    /// be presented. Shared by the overlay mount and the begin/end onChange so
    /// the two can't drift apart.
    private func isInlinePlayerOverlayActive(appEnvironment: AppEnvironment) -> Bool {
        appEnvironment.navigationCoordinator.isPlayerExpanded &&
            !appEnvironment.settingsManager.macPlayerSeparateWindow
    }
    #endif

    #if os(macOS)
    @ViewBuilder
    private func miniPlayerOverlay(appEnvironment: AppEnvironment) -> some View {
        let playerState = appEnvironment.playerService.state
        let hasActiveVideo = playerState.currentVideo != nil
        let isExpanded = appEnvironment.navigationCoordinator.isPlayerExpanded
        // The expanded player is a separate window in window mode, so keep the capsule
        // visible alongside it. The inline overlay covers the window, so hide it there.
        let usesWindow = appEnvironment.settingsManager.macPlayerSeparateWindow

        if hasActiveVideo && (!isExpanded || usesWindow) {
            VStack(spacing: 0) {
                Spacer()
                MiniPlayerView()
            }
            // Float the capsule above the bottom edge (macOS uses a sidebar, not a tab bar)
            .padding(.bottom, 16)
            // Use move-only transition (no opacity) to prevent thumbnail flash during collapse
            .transition(.move(edge: .bottom))
            .animation(.spring(response: 0.3), value: hasActiveVideo)
        }
    }
    #endif
}

// MARK: - Adaptive Tab View

#if os(iOS)
/// Switches between CompactTabView and UnifiedTabView based on horizontal size class.
/// Compact width (iPhone, iPad Stage Manager small): CompactTabView with settings-based customization
/// Regular width (iPad full, iPad larger windows): UnifiedTabView with sidebar adaptable
/// Both render `NavigationRouter` state, so swapping between them keeps the
/// selection and every stack.
struct AdaptiveTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let appEnvironment: AppEnvironment

    @State private var showingMiniPlayerQueueSheet = false
    @State private var showingMiniPlayerPlaylistSheet = false

    /// Whether to show the black overlay that covers scaled content when player is expanded
    private var shouldShowExpandedOverlay: Bool {
        let nav = appEnvironment.navigationCoordinator
        // Show overlay only when:
        // - Player window is actually visible (not just isPlayerExpanded intent)
        // - Expand animation has completed (not animating)
        // - Dismiss gesture is not active (so user can see scaled content during drag)
        return nav.isPlayerWindowVisible && !nav.isPlayerSheetAnimating && !nav.isPlayerDismissGestureActive
    }

    /// Whether to show loading spinner while waiting for player window to appear
    private var shouldShowExpandPendingSpinner: Bool {
        let nav = appEnvironment.navigationCoordinator
        // Show spinner when expand is requested but window isn't visible yet
        return nav.isPlayerExpanded && !nav.isPlayerWindowVisible && !nav.isPlayerSheetAnimating
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if !usesSidebar {
                CompactTabView(router: appEnvironment.navigationCoordinator.router)
                    .environment(appEnvironment.settingsManager)
            } else {
                UnifiedTabView(router: appEnvironment.navigationCoordinator.router)
                .environment(appEnvironment.settingsManager)
            }

            // The tab bar layout on iOS 26.1+ shows the mini player as the tab
            // bar's bottom accessory; the split-view sidebar layout has no tab bar.
            if usesSidebar || !Self.usesTabBottomAccessory {
                miniPlayerOverlay
            }

            // Black overlay when player is fully expanded
            // Hides scaled content behind player sheet, removed during dismiss gesture for parallax effect
            if shouldShowExpandedOverlay {
                Color.black
                    .ignoresSafeArea()
                    .transaction { $0.animation = nil }
            }

            // Loading spinner when expand is pending but window not yet visible
            // This handles the case when scene is transitioning (e.g., Control Center)
            if shouldShowExpandPendingSpinner {
                ZStack {
                    Color.black.opacity(0.7)
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
                .ignoresSafeArea()
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .onChange(of: appEnvironment.navigationCoordinator.playerExpandTrigger) { _, _ in
            presentExpandedPlayer()
        }
        .onChange(of: appEnvironment.navigationCoordinator.isPlayerExpanded) { _, isExpanded in
            if !isExpanded {
                ExpandedPlayerWindowManager.shared.hide()
            }
        }
        .onChange(of: appEnvironment.navigationCoordinator.isMiniPlayerQueueSheetPresented, initial: true) { _, newValue in
            showingMiniPlayerQueueSheet = newValue
        }
        .onChange(of: appEnvironment.navigationCoordinator.isMiniPlayerPlaylistSheetPresented, initial: true) { _, newValue in
            showingMiniPlayerPlaylistSheet = newValue
        }
        .sheet(isPresented: $showingMiniPlayerQueueSheet, onDismiss: {
            appEnvironment.navigationCoordinator.isMiniPlayerQueueSheetPresented = false
        }) {
            QueueManagementSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingMiniPlayerPlaylistSheet, onDismiss: {
            appEnvironment.navigationCoordinator.isMiniPlayerPlaylistSheetPresented = false
        }) {
            if let video = appEnvironment.playerService.state.currentVideo {
                PlaylistSelectorSheet(video: video)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var usesSidebar: Bool {
        NavigationLayout.usesSidebar(horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
    }

    private static var usesTabBottomAccessory: Bool {
        if #available(iOS 26.1, *) { true } else { false }
    }

    @ViewBuilder
    private var miniPlayerOverlay: some View {
        let playerState = appEnvironment.playerService.state
        let hasActiveVideo = playerState.currentVideo != nil
        let isExpanded = appEnvironment.navigationCoordinator.isPlayerExpanded

        if hasActiveVideo && !isExpanded {
            VStack(spacing: 0) {
                Spacer()
                MiniPlayerView()
            }
            .padding(.horizontal, 16)
            // The tab bar layout has a bottom tab bar (49pt) to clear; the sidebar
            // layout (sidebarAdaptable) keeps its tabs at the top, so only float above the edge.
            .padding(.bottom, usesSidebar ? 12 : 49 + 8)
            // Use move-only transition (no opacity) to prevent thumbnail flash during collapse
            // The opacity transition caused video to appear faded during player sheet dismiss
            .transition(.move(edge: .bottom))
            .animation(.spring(response: 0.3), value: hasActiveVideo)
        }
    }

    private func presentExpandedPlayer() {
        let shouldAnimate = !appEnvironment.navigationCoordinator.skipNextPlayerExpandAnimation
        appEnvironment.navigationCoordinator.skipNextPlayerExpandAnimation = false
        ExpandedPlayerWindowManager.shared.show(with: appEnvironment, animated: shouldAnimate)
    }
}

#endif

// MARK: - Preview

#Preview {
    ContentView()
        .appEnvironment(.preview)
}
