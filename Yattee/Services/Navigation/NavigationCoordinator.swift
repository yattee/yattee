//
//  NavigationCoordinator.swift
//  Yattee
//
//  Centralized navigation state management.
//

import SwiftUI

/// Sheet destinations for modal presentation.
enum SheetDestination: Identifiable {
    case settings
    case addToPlaylist(Video)
    case downloadOptions(Video)
    case newPlaylist

    var id: String {
        switch self {
        case .settings: return "settings"
        case .addToPlaylist(let video): return "addToPlaylist-\(video.id.id)"
        case .downloadOptions(let video): return "downloadOptions-\(video.id.id)"
        case .newPlaylist: return "newPlaylist"
        }
    }
}

/// Centralized navigation coordinator for the app.
@Observable
@MainActor
final class NavigationCoordinator {
    /// Navigation path for NavigationStack.
    var path = NavigationPath()

    /// Currently selected tab.
    var selectedTab: AppTab = .home {
        didSet {
            updateHandoffForCurrentTab()
        }
    }

    /// Directly selected sidebar item (for extended navigation commands).
    /// When set, UnifiedTabView syncs this to its selection state.
    var selectedSidebarItem: SidebarItem?

    /// Currently selected home sub-tab.
    var selectedHomeTab: HomeTab = .playlists {
        didSet {
            if selectedTab == .home {
                updateHandoffForCurrentTab()
            }
        }
    }

    /// Currently presented sheet.
    var presentedSheet: SheetDestination?

    /// Trigger to dismiss settings sheet (incremented when dismiss is needed).
    var dismissSettingsTrigger = 0

    /// Mini player video (if playing).
    var nowPlaying: Video?

    /// Whether the mini player is expanded to full screen.
    var isPlayerExpanded = false

    /// Whether the mini player queue sheet is showing.
    var isMiniPlayerQueueSheetPresented = false

    /// Whether the mini player playlist sheet is showing.
    var isMiniPlayerPlaylistSheetPresented = false

    /// Counter that increments each time the player should expand.
    /// Used to trigger presentation even when isPlayerExpanded is already true.
    var playerExpandTrigger = 0

    /// Whether the player sheet is currently animating (presenting or dismissing).
    var isPlayerSheetAnimating = false

    /// Whether the next player expand should skip animation (for fullscreen exit).
    var skipNextPlayerExpandAnimation = false

    /// Trigger for remote control fullscreen toggle (incremented when toggle is needed).
    var pendingFullscreenToggle = 0

    /// Trigger to scroll the player into view (incremented when scroll is needed).
    var scrollPlayerIntoViewTrigger = 0

    /// Whether the player scroll animation is in progress.
    var isPlayerScrollAnimating = false

    /// Whether the player dismiss gesture is active (dragging down to dismiss).
    var isPlayerDismissGestureActive = false

    /// Whether the expanded player window is actually visible on screen.
    /// Distinct from `isPlayerExpanded` which is the intent to show the player.
    /// The window may not be visible if the scene is transitioning (e.g., Control Center open).
    var isPlayerWindowVisible = false

    /// Whether the player is currently expanding (for animation coordination with mini player).
    var isPlayerExpanding = false

    /// Whether the player is currently collapsing (for animation coordination with mini player).
    var isPlayerCollapsing = false

    /// Whether expanded comments view is currently showing (blocks sheet dismiss gesture).
    var isCommentsExpanded = false

    /// Whether user is adjusting volume/brightness sliders (blocks sheet dismiss gesture).
    var isAdjustingPlayerSliders = false

    /// Whether user is dragging the portrait panel to dismiss/reveal (blocks sheet dismiss gesture).
    var isPanelDragging = false

    /// Whether the portrait panel is currently visible (not hidden off-screen).
    var isPortraitPanelVisible = true

    /// Portrait panel frame in screen coordinates (for gesture conflict resolution).
    var portraitPanelFrame: CGRect = .zero

    /// Progress bar frame in screen coordinates (for gesture conflict resolution).
    var progressBarFrame: CGRect = .zero

    /// Comments overlay frame in screen coordinates (for gesture conflict resolution).
    var commentsFrame: CGRect = .zero

    /// Current panscan value from UIKit pinch gesture (0.0 = fit, 1.0 = fill).
    /// Updated by ExpandedPlayerWindow's pinch gesture handler.
    var pinchPanscan: Double = 0.0

    /// Whether a pinch gesture is currently active.
    var isPinchGestureActive = false

    /// Whether a seek gesture is currently active.
    var isSeekGestureActive = false

    /// Whether panscan should snap to fit/fill when released.
    /// Updated by PlayerControlsView when layout settings change.
    var shouldSnapPanscan: Bool = true

    /// Base panscan value when pinch gesture started.
    var pinchGestureBasePanscan: Double = 0.0

    /// Whether panscan animation is in progress.
    var isPanscanAnimating = false

    /// Animates panscan to zero with ease-out curve, then calls completion.
    func animatePanscanToZero(completion: (() -> Void)? = nil) {
        animatePanscan(to: 0.0, completion: completion)
    }

    /// Toggles panscan between 0 and 1 with animated ease-out curve.
    func togglePanscan() {
        let target: Double = pinchPanscan > 0.5 ? 0.0 : 1.0
        animatePanscan(to: target)
    }

    /// Animates panscan to target value with ease-out curve.
    func animatePanscan(to target: Double, completion: (() -> Void)? = nil) {
        let start = pinchPanscan
        guard abs(start - target) > 0.01 else {
            completion?()
            return
        }

        isPanscanAnimating = true
        let duration: Double = 0.25
        let steps = 15
        let stepDuration = duration / Double(steps)

        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            // Ease-out curve for smooth deceleration
            let easedProgress = 1 - pow(1 - progress, 3)
            let value = start + (target - start) * easedProgress

            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) { [weak self] in
                self?.pinchPanscan = value
                if step == steps {
                    self?.isPanscanAnimating = false
                    completion?()
                }
            }
        }
    }

    /// Pending navigation destination (used when navigating from sheets/modals).
    var pendingNavigation: NavigationDestination?

    /// Reference to HandoffManager for updating activities on navigation.
    private weak var handoffManager: HandoffManager?

    /// Reference to MediaSourcesManager for navigating to media source directories.
    private weak var mediaSourcesManager: MediaSourcesManager?

    // MARK: - Handoff Integration

    /// Set the HandoffManager reference for activity updates.
    func setHandoffManager(_ manager: HandoffManager) {
        self.handoffManager = manager
    }

    /// Set the MediaSourcesManager reference for media source navigation.
    func setMediaSourcesManager(_ manager: MediaSourcesManager) {
        self.mediaSourcesManager = manager
    }

    // MARK: - Navigation Actions

    /// Navigate to a destination.
    func navigate(to destination: NavigationDestination) {
        pendingNavigation = destination
        handoffManager?.updateActivity(for: destination)
    }

    /// Clear pending navigation after it's been handled.
    func clearPendingNavigation() {
        pendingNavigation = nil
    }

    /// Pop to the root of the current navigation stack.
    func popToRoot() {
        path.removeLast(path.count)
    }

    /// Pop one level back in the navigation stack.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    // MARK: - Sheet Presentation

    /// Dismiss the current sheet.
    func dismissSheet() {
        presentedSheet = nil
    }

    /// Dismiss the settings sheet from anywhere in the app.
    func dismissSettings() {
        dismissSettingsTrigger += 1
    }

    // MARK: - Player Actions

    /// Expand the mini player to full screen.
    func expandPlayer(animated: Bool = true) {
        LoggingService.shared.debug("NavigationCoordinator: expandPlayer(animated=\(animated)) - isPlayerExpanded was \(isPlayerExpanded), trigger=\(playerExpandTrigger)", category: .player)
        if !animated {
            skipNextPlayerExpandAnimation = true
        }
        isPlayerExpanded = true
        playerExpandTrigger += 1
        LoggingService.shared.debug("NavigationCoordinator: expandPlayer complete - isPlayerExpanded=\(isPlayerExpanded), trigger=\(playerExpandTrigger)", category: .player)
    }

    /// Waits until player sheet animation completes.
    func waitForPlayerSheetAnimation() async {
        while isPlayerSheetAnimating {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Scrolls the player into view (uncovered position).
    func scrollPlayerIntoView() {
        isPlayerScrollAnimating = true
        scrollPlayerIntoViewTrigger += 1
    }

    /// Waits until player scroll animation completes.
    func waitForPlayerScrollAnimation() async {
        while isPlayerScrollAnimating {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - URL Handling

    /// Handle an incoming URL.
    func handle(url: URL) {
        let router = URLRouter()
        if let destination = router.route(url) {
            navigate(to: destination)
        }
    }

    // MARK: - Convenience Navigation

    /// Navigate to the subscriptions tab/feed.
    func navigateToSubscriptions() {
        selectedTab = .subscriptions
    }

    /// Navigate to a video by its ID string.
    /// Creates a VideoID assuming YouTube source.
    func navigateToVideo(videoID: String) {
        let id = VideoID(source: .global(provider: ContentSource.youtubeProvider), videoID: videoID)
        navigate(to: .video(.id(id)))
    }

    /// Navigate to a video's channel/source.
    /// For media source videos (SMB, WebDAV, local), navigates to the parent directory.
    /// For extracted videos, navigates to the external channel URL.
    /// For regular videos, navigates to the channel view.
    func navigateToChannel(for video: Video, collapsePlayer: Bool = false) {
        if collapsePlayer {
            isPlayerCollapsing = true
            isPlayerExpanded = false
        }

        // Handle media source videos (SMB, WebDAV, local folders)
        if video.isFromMediaSource,
           let sourceID = video.mediaSourceID,
           let filePath = video.mediaSourceFilePath,
           let source = mediaSourcesManager?.source(byID: sourceID) {
            let directoryPath = (filePath as NSString).deletingLastPathComponent
            navigate(to: .mediaBrowser(source, path: directoryPath))
        } else if case .extracted = video.id.source, let authorURL = video.author.url {
            navigate(to: .externalChannel(authorURL))
        } else {
            navigate(to: .channel(video.author.id, video.authorSource))
        }
    }

    // MARK: - Handoff Updates

    /// Updates Handoff activity based on current tab selection.
    private func updateHandoffForCurrentTab() {
        let destination: NavigationDestination?

        switch selectedTab {
        case .subscriptions:
            destination = .subscriptionsFeed
        case .home:
            switch selectedHomeTab {
            case .playlists:
                destination = .playlists
            case .history:
                destination = .history
            case .downloads:
                destination = .downloads
            }
        case .search:
            // Search updates handoff when a search is performed, not on tab selection
            destination = nil
        #if os(tvOS)
        case .settings:
            destination = nil
        #endif
        }

        if let destination {
            handoffManager?.updateActivity(for: destination)
        }
    }
}
