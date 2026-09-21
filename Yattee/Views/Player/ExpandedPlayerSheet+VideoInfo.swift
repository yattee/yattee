//
//  ExpandedPlayerSheet+VideoInfo.swift
//  Yattee
//
//  Video info, description, and comments functionality for the expanded player sheet.
//

import SwiftUI

#if os(iOS) || os(macOS) || os(tvOS)

extension ExpandedPlayerSheet {
    // MARK: - Scroll & Comments

    /// Scrolls the content to the top.
    func scrollToTop() {
        withAnimation(.easeOut(duration: 0.25)) {
            scrollPosition.scrollTo(y: 0)
        }
    }

    /// Expands the comments overlay.
    func expandComments() {
        // Scroll player to top so video is fully visible
        scrollPosition.scrollTo(y: 0)
        // Use same animation as player sheet expand (0.3s, no bounce)
        withAnimation(.smooth(duration: 0.3)) {
            isCommentsExpanded = true
        }
    }

    /// Collapses the comments overlay.
    func collapseComments() {
        navigationCoordinator?.commentsFrame = .zero
        // Use same animation as player sheet dismiss (0.3s, no bounce)
        withAnimation(.smooth(duration: 0.3)) {
            isCommentsExpanded = false
            commentsDismissOffset = 0
        }
    }

    /// Starts preloading comments, cancelling any in-flight task.
    func startPreloadingComments() {
        commentsPreloadTask?.cancel()
        commentsPreloadTask = Task { await preloadComments() }
    }

    /// Cancels any in-flight comments preload task.
    func cancelCommentsPreload() {
        commentsPreloadTask?.cancel()
        commentsPreloadTask = nil
    }

    /// Handles comments dismiss offset during drag.
    func handleCommentsDismissOffset(_ offset: CGFloat) {
        // Don't apply real-time offset during drag - it causes feedback loop
        // with scroll geometry. The scroll view bounces naturally with iOS rubber-banding.
    }

    /// Handles the end of comments dismiss gesture.
    func handleCommentsDismissGestureEnded(_ finalOffset: CGFloat) {
        let dismissThreshold: CGFloat = 30
        if finalOffset >= dismissThreshold {
            collapseComments()
        }
        // Below threshold - scroll view will rubber-band back naturally
    }

    /// Preloads comments for the current video.
    func preloadComments() async {
        guard let playerState, playerState.commentsState == .idle else { return }

        // Check if comments pill is disabled in preset settings
        let pillSettings = playerControlsLayout.effectivePlayerPillSettings
        guard pillSettings.shouldLoadComments else {
            playerState.commentsState = .disabled
            return
        }

        guard let contentService = appEnvironment?.contentService,
              let instancesManager = appEnvironment?.instancesManager else { return }

        await playerState.loadComments(contentService: contentService, instancesManager: instancesManager)
    }

    // MARK: - Actions

    /// Closes the current video and dismisses the player.
    func closeVideo() {
        // Mark as closing to hide tab accessory before dismissal
        playerState?.isClosingVideo = true

        // Clear the queue when closing video
        appEnvironment?.queueManager.clearQueue()

        // Reset panel state when closing player
        appEnvironment?.settingsManager.landscapeDetailsPanelVisible = false
        appEnvironment?.settingsManager.landscapeDetailsPanelPinned = false

        // Stop player FIRST before dismissing window
        // This ensures MPVRenderView and backend are properly cleaned up
        // before the window's content view hierarchy is destroyed
        playerService?.stop()

        // Then dismiss player window (after backend is stopped)
        navigationCoordinator?.isPlayerExpanded = false
    }

    /// Switches to a different stream.
    func switchToStream(_ stream: Stream, audioStream: Stream? = nil) {
        Task {
            await playerService?.selectStreamManually(stream, audioStream: audioStream)
        }
    }
}

#endif
