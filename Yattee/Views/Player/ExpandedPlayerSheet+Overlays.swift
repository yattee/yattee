//
//  ExpandedPlayerSheet+Overlays.swift
//  Yattee
//
//  Overlay views and playback actions for the expanded player sheet.
//

import SwiftUI

#if os(iOS) || os(macOS) || os(tvOS)

extension ExpandedPlayerSheet {
    // MARK: - Playback Actions

    /// Starts playback of the current video.
    func startPlayback() {
        guard let playerService, let video = playerState?.currentVideo else { return }

        Task {
            await playerService.playPreferringDownloaded(video: video)
        }
    }

    /// Restarts playback from the beginning.
    func restartPlayback() {
        guard let playerService else { return }

        Task {
            await playerService.seek(to: 0)
            playerService.resume()
        }
    }

    /// Retries playback after a failure.
    func retryPlayback() {
        guard let playerService, let video = playerState?.currentVideo else { return }

        Task {
            await playerService.play(video: video)
        }
    }

    /// Tries to play a fallback stream.
    func tryFallbackStream(_ stream: Stream) {
        guard let playerService else { return }

        Task {
            await playerService.switchToOnlineStream(stream, audioStream: nil)
        }
    }

    /// Returns the first muxed stream available.
    var firstMuxedStream: Stream? {
        playerService?.availableStreams.first { $0.isMuxed }
    }

    // MARK: - Thumbnail Overlay Content

    /// Main overlay content that switches based on playback state.
    @ViewBuilder
    func thumbnailOverlayContent(
        isIdle: Bool,
        isEnded: Bool,
        isFailed: Bool,
        isLoading: Bool
    ) -> some View {
        ZStack {
            if isIdle {
                PlayerOverlayButton(icon: "play.fill", action: startPlayback)
                    .transition(.opacity)
            } else if isEnded {
                endedOverlay
                    .transition(.opacity)
            } else if isFailed {
                loadFailedOverlay
                    .transition(.opacity)
            } else if playerState?.retryState.exhausted == true {
                retryExhaustedOverlay
                    .transition(.opacity)
            } else if isLoading {
                loadingOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isIdle)
        .animation(.easeInOut(duration: 0.3), value: isEnded)
        .animation(.easeInOut(duration: 0.3), value: isFailed)
        .animation(.easeInOut(duration: 0.3), value: isLoading)
    }

    // MARK: - State Overlays

    /// Overlay shown while video is loading.
    @ViewBuilder
    var loadingOverlay: some View {
        // Don't show buffer progress for downloaded videos - local files load quickly
        let showBufferProgress = playerService?.currentDownload == nil
        LoadingOverlayView(
            bufferProgress: showBufferProgress ? playerState?.bufferProgress : nil
        )
    }

    /// Overlay shown when video fails to load.
    @ViewBuilder
    var loadFailedOverlay: some View {
        Color.black.opacity(0.4)
        VStack(spacing: 16) {
            // Error details button
            Button {
                showingErrorSheet = true
            } label: {
                Label(String(localized: "player.error.button"), systemImage: "info.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassBackground(.regular, in: .capsule, fallback: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .environment(\.colorScheme, .dark)
            .accessibilityLabel(String(localized: "player.error.showDetails.accessibilityLabel"))

            // Retry and Close buttons side by side
            HStack(spacing: 12) {
                // Retry button
                Button(action: retryPlayback) {
                    Label(String(localized: "player.error.retry"), systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassBackground(.regular, in: .capsule, fallback: .ultraThinMaterial)
                }
                .buttonStyle(.plain)
                .environment(\.colorScheme, .dark)
                .accessibilityLabel(String(localized: "player.error.retry.accessibilityLabel"))

                // Play Next button (when queue has next video) or Close button (when queue is empty)
                if nextQueuedVideo != nil {
                    Button {
                        playNextInQueue()
                    } label: {
                        Label(String(localized: "player.autoplay.playNext"), systemImage: "forward.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassBackground(.regular, in: .capsule, fallback: .ultraThinMaterial)
                    }
                    .buttonStyle(.plain)
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel(String(localized: "player.autoplay.playNext"))
                } else {
                    Button {
                        closeVideo()
                    } label: {
                        Label(String(localized: "player.close"), systemImage: "xmark")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassBackground(.regular, in: .capsule, fallback: .ultraThinMaterial)
                    }
                    .buttonStyle(.plain)
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel(String(localized: "player.close.accessibilityLabel"))
                }
            }
        }
    }

    /// Overlay shown when retry attempts are exhausted.
    @ViewBuilder
    var retryExhaustedOverlay: some View {
        Color.black.opacity(0.4)
        VStack(spacing: 16) {
            PlayerOverlayButton(icon: "arrow.clockwise", action: retryPlayback)
            Text(String(localized: "player.retry.button"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))

            // Fallback muxed stream button (if available and different from current)
            if let fallbackStream = firstMuxedStream,
               fallbackStream.id != playerState?.currentStream?.id {
                Button(action: { tryFallbackStream(fallbackStream) }) {
                    Text(String(localized: "player.retry.tryResolution \(fallbackStream.resolution?.description ?? "")"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Overlay shown when video playback ends.
    @ViewBuilder
    var endedOverlay: some View {
        let showCountdown = isAutoPlayEnabled && nextQueuedVideo != nil && !isAutoplayCancelled && autoplayCountdown > 0
        let relatedVideos = playerState?.currentVideo?.relatedVideos

        Color.black.opacity(0.4)

        if showCountdown, let nextVideo = nextQueuedVideo {
            // Autoplay countdown UI
            autoplayCountdownOverlay(nextVideo: nextVideo)
        } else if let videos = relatedVideos, !videos.isEmpty {
            // Show recommended videos carousel with replay/close buttons
            recommendedVideosOverlay(videos: videos)
        } else if nextQueuedVideo == nil && isQueueEnabled && hasQueueItems == false {
            // End of queue - show message and replay button
            endOfQueueOverlay
        } else {
            // No autoplay or cancelled - show replay button and close button
            replayWithCloseButtons
        }
    }
}

#endif
