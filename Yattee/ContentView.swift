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
                if #available(iOS 26.1, *) {
                    iOS26AdaptiveTabView(appEnvironment: appEnvironment)
                } else {
                    iOS18AdaptiveTabView(appEnvironment: appEnvironment)
                }
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
            UnifiedTabView(
                selectedTab: Binding(
                    get: { appEnvironment.navigationCoordinator.selectedTab },
                    set: { appEnvironment.navigationCoordinator.selectedTab = $0 }
                )
            )
            .environment(appEnvironment.settingsManager)
            #elseif os(tvOS)
            UnifiedTabView(
                selectedTab: Binding(
                    get: { appEnvironment.navigationCoordinator.selectedTab },
                    set: { appEnvironment.navigationCoordinator.selectedTab = $0 }
                )
            )
            .environment(appEnvironment.settingsManager)
            #endif

            // Mini player overlay (macOS only)
            #if os(macOS)
            miniPlayerOverlay(appEnvironment: appEnvironment)
            #endif
        }
        #if os(macOS)
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
                // Inline sheet → separate window: let the sheet dismiss first, then
                // present the window (mirrors the previous inline→window transition).
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    if appEnvironment.navigationCoordinator.isPlayerExpanded {
                        presentExpandedPlayerWindow(appEnvironment: appEnvironment)
                    }
                }
            } else {
                // Separate window → inline sheet: hide the window so the sheet binding
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
            get: {
                appEnvironment.navigationCoordinator.isPlayerExpanded &&
                !appEnvironment.settingsManager.macPlayerSeparateWindow
            },
            set: { appEnvironment.navigationCoordinator.isPlayerExpanded = $0 }
        )) {
            let size = expandedSheetSize(appEnvironment: appEnvironment)
            let lockAspect = sheetLockAspectRatio(appEnvironment: appEnvironment)
            ExpandedPlayerSheet()
                // Floor keeps the content flexible so it tracks the window's
                // animated resize with no gap — do NOT pin an exact (max) size:
                // a fixed frame snaps instantly while the window animates,
                // exposing the window background as bars. The ideal size makes
                // `.presentationSizing(.fitted)` open the sheet at the correct
                // aspect immediately when the video size is already known (e.g.
                // re-opening while playing), avoiding a small-then-resize flash.
                .frame(
                    minWidth: 640, idealWidth: size.width,
                    minHeight: 360, idealHeight: size.height
                )
                .presentationSizing(.fitted)
                // `.presentationSizing(.fitted)` only fits the sheet once, at
                // presentation. Resize the backing window directly when the
                // aspect-ratio-derived size changes so the sheet tracks the video,
                // and lock interactive resize to the video ratio (no black bars).
                .sheetWindowSize(size, aspectRatio: lockAspect)
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

    /// Size for the expanded-player sheet, derived from the current video aspect
    /// ratio (when auto-resize is enabled) so the sheet re-fits like window mode.
    /// Reading `videoAspectRatio` / `playerSheetAutoResize` here registers the
    /// @Observable dependency that drives the re-fit.
    private func expandedSheetSize(appEnvironment: AppEnvironment) -> CGSize {
        let settings = appEnvironment.settingsManager
        let aspect: Double
        if settings.playerSheetAutoResize,
           let ratio = appEnvironment.playerService.state.videoAspectRatio, ratio > 0 {
            aspect = ratio
        } else {
            aspect = 16.0 / 9.0 // fixed default when auto-resize is off / not yet known
        }
        return ExpandedPlayerWindowManager.fittedSheetSize(for: aspect)
    }

    /// Real video aspect ratio to lock the sheet's interactive resize to, or `0`
    /// when unknown. Unlike the sheet *size* (which honors `playerSheetAutoResize`),
    /// the resize lock always follows the actual video ratio — mirroring the
    /// standalone window, which locks unconditionally. Reading `videoAspectRatio`
    /// here registers the @Observable dependency that keeps the lock in sync.
    private func sheetLockAspectRatio(appEnvironment: AppEnvironment) -> Double {
        let ratio = appEnvironment.playerService.state.videoAspectRatio ?? 0
        return ratio > 0 ? ratio : 0
    }
    #endif

    #if os(macOS)
    @ViewBuilder
    private func miniPlayerOverlay(appEnvironment: AppEnvironment) -> some View {
        let playerState = appEnvironment.playerService.state
        let hasActiveVideo = playerState.currentVideo != nil
        let isExpanded = appEnvironment.navigationCoordinator.isPlayerExpanded
        // The expanded player is a separate window in window mode, so keep the capsule
        // visible alongside it. In sheet mode the sheet covers the window, so hide it.
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

// MARK: - iOS 18+ Adaptive Tab View

#if os(iOS)
/// Switches between CompactTabView and UnifiedTabView based on horizontal size class.
/// Compact width (iPhone, iPad Stage Manager small): CompactTabView with settings-based customization
/// Regular width (iPad full, iPad larger windows): UnifiedTabView with sidebar adaptable
struct iOS18AdaptiveTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            if horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone {
                CompactTabView()
                    .environment(appEnvironment.settingsManager)
            } else {
                UnifiedTabView(
                    selectedTab: Binding(
                        get: { appEnvironment.navigationCoordinator.selectedTab },
                        set: { appEnvironment.navigationCoordinator.selectedTab = $0 }
                    )
                )
                .environment(appEnvironment.settingsManager)
            }

            // Mini player overlay
            miniPlayerOverlay

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
        .onChange(of: appEnvironment.navigationCoordinator.isMiniPlayerQueueSheetPresented) { _, newValue in
            showingMiniPlayerQueueSheet = newValue
        }
        .onChange(of: appEnvironment.navigationCoordinator.isMiniPlayerPlaylistSheetPresented) { _, newValue in
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
            .padding(.bottom, 49)
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

// MARK: - iOS 26+ Adaptive Tab View

/// iOS 26.1+ version with bottom accessory mini player support.
/// Uses UnifiedTabView with sidebarAdaptable for regular width, CompactTabView for compact.
@available(iOS 26.1, *)
struct iOS26AdaptiveTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        ZStack {
            Group {
                if horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone {
                    // Compact: Use CompactTabView with settings-based customization
                    // No bottom accessory since we're not using sidebarAdaptable style
                    CompactTabView()
                        .environment(appEnvironment.settingsManager)
                } else {
                    // Regular: Use UnifiedTabView which has bottom accessory support via sidebarAdaptable
                    UnifiedTabView(
                        selectedTab: Binding(
                            get: { appEnvironment.navigationCoordinator.selectedTab },
                            set: { appEnvironment.navigationCoordinator.selectedTab = $0 }
                        )
                    )
                    .environment(appEnvironment.settingsManager)
                }
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
        .onChange(of: appEnvironment.navigationCoordinator.isMiniPlayerQueueSheetPresented) { _, newValue in
            showingMiniPlayerQueueSheet = newValue
        }
        .onChange(of: appEnvironment.navigationCoordinator.isMiniPlayerPlaylistSheetPresented) { _, newValue in
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
