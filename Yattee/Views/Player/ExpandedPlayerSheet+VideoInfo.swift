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

        guard let video = playerState.currentVideo,
              let contentService = appEnvironment?.contentService,
              let instancesManager = appEnvironment?.instancesManager else { return }

        // Capture video ID at start for validation after async call
        let requestedVideoID = video.id

        // Don't load comments for non-YouTube videos
        guard video.supportsComments else {
            playerState.commentsState = .disabled
            return
        }

        guard let instance = instancesManager.instance(for: video) else { return }

        playerState.commentsState = .loading

        do {
            let page = try await contentService.comments(
                videoID: video.id.videoID,
                instance: instance,
                continuation: nil
            )

            // Validate video hasn't changed and task wasn't cancelled
            guard !Task.isCancelled,
                  playerState.currentVideo?.id == requestedVideoID else { return }

            playerState.comments = page.comments
            playerState.commentsContinuation = page.continuation
            playerState.commentsState = .loaded
        } catch let error as APIError where error == .commentsDisabled {
            guard !Task.isCancelled,
                  playerState.currentVideo?.id == requestedVideoID else { return }
            playerState.commentsState = .disabled
        } catch {
            guard !Task.isCancelled,
                  playerState.currentVideo?.id == requestedVideoID else { return }
            playerState.commentsState = .error
        }
    }

    // MARK: - DeArrow Title Helpers

    /// Returns the DeArrow title if available and enabled.
    func deArrowTitle(for video: Video) -> String? {
        appEnvironment?.deArrowBrandingProvider.title(for: video)
    }

    /// Returns the display title based on toggle state.
    /// Shows DeArrow title by default when available, original when toggled.
    func displayTitle(for video: Video) -> String {
        if let deArrow = deArrowTitle(for: video) {
            return showOriginalTitle ? video.title : deArrow
        }
        return video.title
    }

    /// Whether the title can be toggled (DeArrow title is available).
    func canToggleTitle(for video: Video) -> Bool {
        deArrowTitle(for: video) != nil
    }

    // MARK: - Video Info Views

    /// Video info section with title, stats, and channel.
    @ViewBuilder
    func videoInfo(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title - full width
            Text(displayTitle(for: video))
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(3)
                .onTapGesture {
                    if canToggleTitle(for: video) {
                        showOriginalTitle.toggle()
                    }
                }

            // Stats row - only show for non-media-source videos
            if !video.isFromMediaSource {
                VideoStatsRow(
                    playerState: playerState,
                    showFormattedDate: $showFormattedDate,
                    returnYouTubeDislikeEnabled: appEnvironment?.settingsManager.returnYouTubeDislikeEnabled ?? false
                )
            }

            // Channel row with context menu
            VideoChannelRow(
                author: video.author,
                source: video.authorSource,
                yatteeServerURL: yatteeServerURL,
                onChannelTap: video.author.hasRealChannelInfo ? {
                    navigationCoordinator?.navigateToChannel(for: video, collapsePlayer: true)
                } : nil,
                video: video,
                accentColor: accentColor,
                showSubscriberCount: !video.isFromMediaSource,
                isLoadingDetails: playerState?.videoDetailsState == .loading
            )
        }
        .padding()
    }

    /// Returns the first enabled Yattee Server instance URL, if any.
    var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    // MARK: - Info Tab Section

    /// Info tab section with video description.
    @ViewBuilder
    func infoTabSection(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description only (no picker)
            descriptionContent(video.description ?? "")

            // Extra space at bottom so content can scroll above the comments pill
            Spacer()
                .frame(height: 80)
        }
        .padding(.vertical)
    }

    /// Description content view.
    @ViewBuilder
    func descriptionContent(_ description: String) -> some View {
        let isLoadingDetails = playerState?.videoDetailsState == .loading

        VStack(alignment: .leading, spacing: 8) {
            if !description.isEmpty {
                Text(DescriptionText.attributed(description, linkColor: accentColor))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .tint(accentColor)
                    .padding(.horizontal)
                    .handleTimestampLinks(using: playerService)
            } else if isLoadingDetails {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else {
                Text(String(localized: "player.noDescription"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
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
        guard let video = playerState?.currentVideo else { return }

        // Capture current playback position before switching streams
        let currentTime = playerState?.currentTime
        // Also get time directly from backend as backup
        let backendTime = playerService?.currentBackend?.currentTime

        LoggingService.shared.logPlayer("switchToStream: stateTime=\(currentTime ?? -1), backendTime=\(backendTime ?? -1), switching to \(stream.qualityLabel)")

        Task {
            await playerService?.play(video: video, stream: stream, audioStream: audioStream, startTime: currentTime)
        }
    }
}

#endif
