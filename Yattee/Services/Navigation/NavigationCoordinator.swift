//
//  NavigationCoordinator.swift
//  Yattee
//
//  Centralized navigation state management.
//

import SwiftUI

/// Centralized navigation coordinator for the app.
@Observable
@MainActor
final class NavigationCoordinator {
    /// Selected section and per-section stacks, shared by every layout.
    let router = NavigationRouter()

    /// Shared sheets requested from outside the view tree.
    let presenter = PresentationRouter()

    init() {
        router.onSelectionChange = { [weak self] _ in
            self?.updateHandoffForCurrentTab()
        }
    }

    /// Currently selected home sub-tab.
    var selectedHomeTab: HomeTab = .playlists {
        didSet {
            if router.selection == .home {
                updateHandoffForCurrentTab()
            }
        }
    }

    /// Bumped when navigation arriving from outside the app (a notification,
    /// a deep link, Handoff) needs the main window's sheets out of the way.
    /// Sheets observe it via `.dismissesOnExternalNavigation(_:)`.
    var dismissPresentationsGeneration = 0

    #if os(macOS)
    /// Bumped to ask the main window to open the Settings window, which only a
    /// view can do (`openWindow`).
    var openSettingsWindowRequest = 0
    #endif

    /// Whether the mini player is expanded to full screen.
    var isPlayerExpanded = false {
        didSet {
            // Each expanded player session applies the preset's default panel
            // visibility once; closing the player arms the next application.
            if !isPlayerExpanded {
                hasAppliedPanelDefaultVisibility = false
                isCornerLayoutActive = false
                isWideScreenLayoutActive = false
            }
        }
    }

    /// Whether the current expanded player session already applied the active
    /// preset's default details panel visibility. Lives here (not view @State)
    /// so window-mode switches and layout re-mounts don't re-apply it.
    var hasAppliedPanelDefaultVisibility = false

    /// Whether the expanded player currently resolves to the corner layout
    /// (iPad/macOS). Drives macOS window aspect-lock gating, which lives in a
    /// different view than the layout resolver.
    var isCornerLayoutActive = false

    /// Whether the expanded player currently resolves to the widescreen
    /// (landscape) layout. Set from the sheet's layout pass so non-view code
    /// (remote control state) reads the real layout instead of screen bounds.
    var isWideScreenLayoutActive = false

    /// Resolved short-link URL awaiting user confirmation ("Try in Yattee" vs
    /// "Open in Browser"). Dual-hosted (root and expanded player)
    /// so the dialog is visible whether or not the expanded player is covering
    /// the main app view.
    var resolvedShortLinkPrompt: URL?

    /// Candidate URL that isn't confidently a video (loose `.externalVideo`
    /// match) awaiting user confirmation before yt-dlp extraction. Dual-hosted.
    var ambiguousExternalLinkPrompt: URL?

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

    /// macOS only: true while the main window is native-fullscreen for the
    /// inline player overlay. Mirrors the window's fullscreen state (kept in
    /// sync by ExpandedPlayerWindowManager via NSWindow fullscreen
    /// notifications) so player controls update reactively.
    var isMacInlinePlayerFullScreen = false

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

    /// Corner layout below-video panel frame in screen coordinates — touches
    /// inside it must not start the sheet dismiss pan (drag handle conflict).
    var cornerBelowPanelFrame: CGRect = .zero

    /// Panel resize grabber strip frame in screen coordinates — touches inside
    /// it must not start the sheet dismiss pan (a diagonal resize drag would
    /// otherwise be cancelled and dismiss the player instead).
    var panelResizeGrabberFrame: CGRect = .zero

    /// Corner layout: width of the trailing screen-edge strip reserved for
    /// the side column reveal swipe while the column is collapsed (0 when
    /// not collapsed) — the seek pan must not begin from inside it.
    var cornerSideColumnEdgeRevealInset: CGFloat = 0

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

    /// Navigate to a destination by pushing it onto the selected section's stack.
    func navigate(to destination: NavigationDestination) {
        // Settings has its own navigation stack, so it can't be pushed onto a
        // section's stack: it is a section, a sheet, or a window instead.
        if case .settings = destination {
            openSettings()
            return
        }
        router.push(destination)
        handoffManager?.updateActivity(for: destination)
    }

    /// Shows Settings the way the current layout presents it: the Settings
    /// section where the layout has one, otherwise the Home screen's sheet
    /// (`NavigationRouter.ensureSelectionIsAvailable`), or on macOS its window.
    func openSettings() {
        #if os(macOS)
        openSettingsWindowRequest += 1
        #else
        router.select(.settings)
        #endif
    }

    // MARK: - Sheet Presentation

    /// Dismiss the main window's sheets so external navigation lands on a
    /// visible screen instead of changing tabs underneath a sheet. Call it
    /// only from external entry points: in-app navigation and layout swaps
    /// must keep an open sheet.
    func dismissPresentations() {
        dismissPresentationsGeneration += 1
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

    // MARK: - Convenience Navigation

    /// Navigate to the subscriptions tab/feed.
    func navigateToSubscriptions(collapsePlayer: Bool = false) {
        if collapsePlayer, isPlayerExpanded {
            isPlayerCollapsing = true
            isPlayerExpanded = false
        }
        router.select(.subscriptionsFeed)
    }

    /// Navigate to an opened link's screen, collapsing the full-screen player
    /// so the pushed screen is visible instead of landing underneath it.
    func navigateToOpenedLink(_ destination: NavigationDestination) {
        if isPlayerExpanded {
            isPlayerCollapsing = true
            isPlayerExpanded = false
        }
        navigate(to: destination)
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
            CachedChannelData.cacheAuthor(video.author)
            navigate(to: .channel(video.author.id, video.authorSource))
        }
    }

    // MARK: - Handoff Updates

    /// Updates Handoff activity based on the selected section.
    private func updateHandoffForCurrentTab() {
        let destination: NavigationDestination?

        switch router.selection {
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
        case .mediaSource, .instance, .sources:
            destination = nil
        default:
            destination = router.selection.navigationDestination()
        }

        if let destination {
            handoffManager?.updateActivity(for: destination)
        }
    }
}
