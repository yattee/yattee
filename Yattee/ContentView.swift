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
            if appEnvironment.settingsManager.macPlayerMode.usesWindow {
                presentExpandedPlayerWindow(appEnvironment: appEnvironment)
            }
        }
        .onChange(of: appEnvironment.navigationCoordinator.isPlayerExpanded) { _, isExpanded in
            if !isExpanded {
                ExpandedPlayerWindowManager.shared.hide()
            }
        }
        .onChange(of: appEnvironment.settingsManager.macPlayerMode) { oldMode, newMode in
            guard appEnvironment.navigationCoordinator.isPlayerExpanded else { return }

            if oldMode.usesWindow && newMode.usesWindow {
                ExpandedPlayerWindowManager.shared.updateWindowLevel(floating: newMode.isFloating)
            } else if oldMode.usesWindow && !newMode.usesWindow {
                ExpandedPlayerWindowManager.shared.hide(animated: false)
            } else if !oldMode.usesWindow && newMode.usesWindow {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    if appEnvironment.navigationCoordinator.isPlayerExpanded {
                        presentExpandedPlayerWindow(appEnvironment: appEnvironment)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: {
                appEnvironment.navigationCoordinator.isPlayerExpanded &&
                !appEnvironment.settingsManager.macPlayerMode.usesWindow
            },
            set: { appEnvironment.navigationCoordinator.isPlayerExpanded = $0 }
        )) {
            ExpandedPlayerSheet()
                .frame(minWidth: 640, minHeight: 480)
                .presentationSizing(.fitted)
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
    #endif

    #if os(macOS)
    @ViewBuilder
    private func miniPlayerOverlay(appEnvironment: AppEnvironment) -> some View {
        let playerState = appEnvironment.playerService.state
        let hasActiveVideo = playerState.currentVideo != nil
        let isExpanded = appEnvironment.navigationCoordinator.isPlayerExpanded

        if hasActiveVideo && !isExpanded {
            VStack(spacing: 0) {
                Spacer()
                MiniPlayerView()
            }
            // Add padding for tab bar
            .padding(.bottom, 49)
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
