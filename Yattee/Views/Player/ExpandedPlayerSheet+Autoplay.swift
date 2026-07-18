//
//  ExpandedPlayerSheet+Autoplay.swift
//  Yattee
//
//  Autoplay countdown functionality for the expanded player sheet.
//

import SwiftUI
import NukeUI

#if os(iOS) || os(macOS) || os(tvOS)

extension ExpandedPlayerSheet {
    // MARK: - Autoplay Countdown Timer

    /// Starts the autoplay countdown timer.
    func startAutoplayCountdown() {
        stopAutoplayCountdown()
        autoplayCountdown = autoPlayCountdownDuration

        autoplayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            Task { @MainActor in
                if autoplayCountdown > 1 {
                    autoplayCountdown -= 1
                } else {
                    // Countdown finished, play next
                    stopAutoplayCountdown()
                    playNextInQueue()
                }
            }
        }
    }

    /// Stops the autoplay countdown timer and resets the countdown.
    func stopAutoplayCountdown() {
        autoplayTimer?.invalidate()
        autoplayTimer = nil
        autoplayCountdown = 0
    }

    /// Plays the next video in the queue.
    func playNextInQueue() {
        guard let playerService else { return }

        // Clear loaded image so next video gets fresh thumbnail
        displayedThumbnailImage = nil
        // Immediately switch to next video's thumbnail to prevent old thumbnail flash
        displayedThumbnailURL = nextQueuedVideo?.video.bestThumbnail?.url
        isThumbnailFrozen = true

        Task {
            await playerService.playNext()
        }
    }

    /// Cancels the autoplay countdown.
    func cancelAutoplay() {
        stopAutoplayCountdown()
        isAutoplayCancelled = true
    }

    // MARK: - Autoplay UI

    /// Overlay showing the autoplay countdown with next video preview.
    @ViewBuilder
    func autoplayCountdownOverlay(nextVideo: QueuedVideo) -> some View {
        VStack(spacing: 16) {
            // Countdown text
            Text(String(localized: "player.autoplay.playingIn \(autoplayCountdown)"))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white)

            // Next video preview - tappable to play immediately
            Button {
                stopAutoplayCountdown()
                playNextInQueue()
            } label: {
                videoPreviewCard(video: nextVideo.video)
            }
            .buttonStyle(.plain)

            // Cancel button
            Button {
                cancelAutoplay()
            } label: {
                Text(String(localized: "player.autoplay.cancel"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .glassBackground(.regular, in: .capsule, fallback: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Overlay shown at end of queue.
    @ViewBuilder
    var endOfQueueOverlay: some View {
        replayWithCloseButtons
    }

    /// Replay and close buttons overlay.
    @ViewBuilder
    var replayWithCloseButtons: some View {
        VStack(spacing: 16) {
            // Replay button
            PlayerOverlayButton(icon: "arrow.counterclockwise", action: restartPlayback)

            // Close button (styled like cancel button from countdown screen)
            Button {
                closeVideo()
            } label: {
                Text(String(localized: "player.close"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .glassBackground(.regular, in: .capsule, fallback: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - Recommended Videos Overlay

    /// Overlay showing recommended videos carousel when video ends.
    @ViewBuilder
    func recommendedVideosOverlay(videos: [Video]) -> some View {
        VStack(spacing: 8) {
            // Header
            Text(String(localized: "videoInfo.section.relatedVideos"))
                .font(.headline)
                .foregroundStyle(.white)

            // Carousel
            recommendedVideosCarousel(videos: videos)

            // Page indicators
            pageIndicators(count: videos.count, current: recommendedScrollPosition ?? 0)

            // Replay and Close buttons in one row
            HStack(spacing: 16) {
                Button {
                    restartPlayback()
                } label: {
                    Text(String(localized: "player.replay"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .glassBackground(.regular, in: .capsule, fallback: .ultraThinMaterial)
                }
                .buttonStyle(.plain)

                Button {
                    closeVideo()
                } label: {
                    Text(String(localized: "player.close"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .glassBackground(.regular, in: .capsule, fallback: .ultraThinMaterial)
                }
                .buttonStyle(.plain)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    /// Horizontal carousel of recommended video cards.
    @ViewBuilder
    private func recommendedVideosCarousel(videos: [Video]) -> some View {
        TabView(selection: Binding(
            get: { recommendedScrollPosition ?? 0 },
            set: { recommendedScrollPosition = $0 }
        )) {
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                Button {
                    playRecommendedVideo(video)
                } label: {
                    videoPreviewCard(video: video)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        #if os(iOS) || os(tvOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        .frame(height: 100)
    }

    /// Reusable horizontal video preview card (same style as autoplay countdown).
    @ViewBuilder
    func videoPreviewCard(video: Video) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            LazyImage(url: video.bestThumbnail?.url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Video info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(video.author.name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: 200, alignment: .leading)
        }
        .padding(12)
        .glassBackground(.regular, in: .rect(cornerRadius: 12), fallback: .ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    /// Page indicator dots for carousel.
    @ViewBuilder
    private func pageIndicators(count: Int, current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }

    /// Play a recommended video.
    func playRecommendedVideo(_ video: Video) {
        guard let playerService else { return }
        recommendedScrollPosition = 0
        Task {
            await playerService.play(video: video)
        }
    }
}

#endif
