//
//  MacOSControlBar.swift
//  Yattee
//
//  Condensed QuickTime-style control bar for macOS player.
//

#if os(macOS)

import SwiftUI

/// Condensed QuickTime-style control bar with a preset-driven button row and timeline.
struct MacOSControlBar: View {
    @Bindable var playerState: PlayerState

    // MARK: - Layout & Actions

    /// The button row rendered above the timeline, from the active preset's bottom section.
    let section: LayoutSection
    /// Global appearance settings from the active preset.
    let globalSettings: GlobalLayoutSettings
    /// Consolidated actions and state for the section renderer.
    let actions: PlayerControlsActions

    // MARK: - Callbacks

    let onSeek: (TimeInterval) async -> Void
    /// Whether to show chapter markers on the progress bar (default: true)
    var showChapters: Bool = true
    /// SponsorBlock segments to display on the progress bar.
    var sponsorSegments: [SponsorBlockSegment] = []
    /// Settings for SponsorBlock segment display.
    var sponsorBlockSettings: SponsorBlockSegmentSettings = .default
    /// Color for the played portion of the progress bar.
    var playedColor: Color = .red

    /// Called when user starts interacting (scrubbing, adjusting volume)
    var onInteractionStarted: (() -> Void)? = nil
    /// Called when user stops interacting
    var onInteractionEnded: (() -> Void)? = nil

    // MARK: - State

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var isHoveringProgress = false
    @State private var hoverProgress: Double = 0

    // MARK: - Computed Properties

    /// Whether the controls are locked (playback buttons/gestures disabled except Settings).
    private var isLocked: Bool {
        playerState.isControlsLocked
    }

    private var displayProgress: Double {
        isDragging ? dragProgress : playerState.progress
    }

    private var bufferedProgress: Double {
        guard playerState.duration > 0 else { return 0 }
        return playerState.bufferedTime / playerState.duration
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            // Top row: preset-driven button row
            MacOSControlsSectionRenderer(
                section: section,
                actions: actions,
                globalSettings: globalSettings,
                context: .bar
            )

            // Bottom row: timeline (expanded width)
            timelineControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 500)
        .glassBackground(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        // Seek preview overlay - positioned above the control bar
        .overlay(alignment: .bottom) {
            if (isDragging || isHoveringProgress), !playerState.isLive {
                GeometryReader { geometry in
                    let pos = seekPreviewPosition(geometry: geometry, previewWidth: playerState.preferredStoryboard != nil ? 176 : 80)

                    if let storyboard = playerState.preferredStoryboard {
                        seekPreviewView(storyboard: storyboard)
                            .offset(x: pos.clampedX, y: -150)

                        if showChapters, let chapter = playerState.chapters.last(where: { $0.startTime <= pos.progress * playerState.duration }) {
                            ChapterCapsuleView(title: chapter.title, buttonBackground: .none)
                                .positioned(xTarget: pos.centerX, availableWidth: geometry.size.width)
                                .offset(y: -176)
                        }
                    } else {
                        SeekTimePreviewView(
                            seekTime: pos.progress * playerState.duration,
                            buttonBackground: .none,
                            theme: .dark
                        )
                        .offset(x: pos.clampedX, y: -60)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .animation(.easeInOut(duration: 0.15), value: isDragging || isHoveringProgress)

                        if showChapters, let chapter = playerState.chapters.last(where: { $0.startTime <= pos.progress * playerState.duration }) {
                            ChapterCapsuleView(title: chapter.title, buttonBackground: .none)
                                .positioned(xTarget: pos.centerX, availableWidth: geometry.size.width)
                                .offset(y: -86)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Timeline Controls

    private var timelineControls: some View {
        HStack(spacing: 8) {
            if playerState.isLive {
                // Live indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text(String(localized: "player.live"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                }
            } else {
                // Current time
                Text(playerState.formattedCurrentTime)
                    .font(globalSettings.fontStyle.font(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()

                // Progress bar (expands to fill available width)
                progressBar

                // Duration
                Text(playerState.formattedDuration)
                    .font(globalSettings.fontStyle.font(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Progress bar with chapter segments
                SegmentedProgressBar(
                    chapters: showChapters ? playerState.chapters : [],
                    duration: playerState.duration,
                    currentTime: isDragging ? dragProgress * playerState.duration : playerState.currentTime,
                    bufferedTime: playerState.bufferedTime,
                    height: 4,
                    gapWidth: 2,
                    playedColor: playedColor,
                    bufferedColor: .primary.opacity(0.3),
                    backgroundColor: .primary.opacity(0.2),
                    sponsorSegments: sponsorSegments,
                    sponsorBlockSettings: sponsorBlockSettings
                )

                // Scrubber handle
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: geometry.size.width * displayProgress - 6)
                    .opacity(isDragging || isHoveringProgress ? 1 : 0)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isLocked else { return }
                        if !isDragging {
                            isDragging = true
                            onInteractionStarted?()
                        }
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = progress
                    }
                    .onEnded { value in
                        guard !isLocked else { return }
                        isDragging = false
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        let seekTime = progress * playerState.duration
                        Task { await onSeek(seekTime) }
                        onInteractionEnded?()
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isHoveringProgress = true
                    hoverProgress = max(0, min(1, location.x / geometry.size.width))
                case .ended:
                    isHoveringProgress = false
                }
            }
            .allowsHitTesting(!isLocked)
        }
        .frame(height: 20)
        .opacity(isLocked ? 0.5 : 1.0)
    }

    private func seekPreviewPosition(
        geometry: GeometryProxy,
        previewWidth: CGFloat
    ) -> (progress: Double, clampedX: CGFloat, centerX: CGFloat) {
        let previewProgress = isDragging ? dragProgress : hoverProgress
        let horizontalPadding: CGFloat = 16
        let timeLabelWidth: CGFloat = 50
        let spacing: CGFloat = 8
        let progressBarOffset = horizontalPadding + timeLabelWidth + spacing
        let progressBarWidth = geometry.size.width - (2 * horizontalPadding) - (2 * timeLabelWidth) - (2 * spacing)
        let xOffset = progressBarOffset + (progressBarWidth * previewProgress) - (previewWidth / 2)
        let clampedX = max(0, min(geometry.size.width - previewWidth, xOffset))
        return (previewProgress, clampedX, clampedX + previewWidth / 2)
    }

    @ViewBuilder
    private func seekPreviewView(storyboard: Storyboard) -> some View {
        let previewProgress = isDragging ? dragProgress : hoverProgress
        let seekTime = previewProgress * playerState.duration

        SeekPreviewView(
            storyboard: storyboard,
            seekTime: seekTime,
            storyboardService: StoryboardService.shared,
            buttonBackground: .none,
            theme: .dark
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.easeInOut(duration: 0.15), value: isDragging || isHoveringProgress)
    }

}

// MARK: - Preview

#Preview {
    let playerState = PlayerState()

    ZStack {
        Color.gray.opacity(0.3)

        MacOSControlBar(
            playerState: playerState,
            section: PlayerControlsLayout.default.bottomSection,
            globalSettings: .default,
            actions: PlayerControlsActions(
                playerState: playerState,
                isWideScreenLayout: true,
                isFullscreen: false,
                isWidescreenVideo: true,
                isPanelVisible: false,
                panelSide: .right,
                showVolumeControls: true,
                showDebugButton: false,
                showCloseButton: false,
                currentVideo: nil,
                availableCaptions: [],
                currentCaption: nil,
                availableStreams: [],
                currentStream: nil,
                currentAudioStream: nil,
                isAutoPlayNextEnabled: true,
                yatteeServerURL: nil,
                deArrowBrandingProvider: nil
            ),
            onSeek: { _ in }
        )
        .frame(width: 650)
    }
    .frame(width: 800, height: 200)
}

#endif
