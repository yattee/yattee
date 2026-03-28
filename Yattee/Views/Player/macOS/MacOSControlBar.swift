//
//  MacOSControlBar.swift
//  Yattee
//
//  Condensed QuickTime-style control bar for macOS player.
//

#if os(macOS)

import SwiftUI

/// Condensed QuickTime-style control bar with transport, timeline, and action controls.
struct MacOSControlBar: View {
    @Bindable var playerState: PlayerState

    // MARK: - Callbacks

    let onPlayPause: () -> Void
    let onSeek: (TimeInterval) async -> Void
    let onSeekForward: (TimeInterval) async -> Void
    let onSeekBackward: (TimeInterval) async -> Void
    var onToggleFullscreen: (() -> Void)? = nil
    var isFullscreen: Bool = false
    var onTogglePiP: (() -> Void)? = nil
    var onPlayNext: (() async -> Void)? = nil
    var onVolumeChanged: ((Float) -> Void)? = nil
    var onMuteToggled: (() -> Void)? = nil
    var onShowSettings: (() -> Void)? = nil
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
    @State private var playNextTapCount = 0
    @State private var seekBackwardTrigger = 0
    @State private var seekForwardTrigger = 0

    // MARK: - Computed Properties

    /// Whether transport controls should be disabled
    private var isTransportDisabled: Bool {
        playerState.playbackState == .loading ||
        playerState.playbackState == .buffering ||
        !playerState.isFirstFrameReady ||
        !playerState.isBufferReady
    }

    private var playPauseIcon: String {
        switch playerState.playbackState {
        case .playing:
            return "pause.fill"
        default:
            return "play.fill"
        }
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
            // Top row: volume | transport (centered) | actions
            topRowControls

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
            if let storyboard = playerState.preferredStoryboard,
               (isDragging || isHoveringProgress),
               !playerState.isLive {
                GeometryReader { geometry in
                    let previewProgress = isDragging ? dragProgress : hoverProgress
                    // Progress bar spans full width minus padding and time labels
                    // Time labels ~50px each, spacing ~16px = ~116px total for labels
                    let horizontalPadding: CGFloat = 16
                    let timeLabelWidth: CGFloat = 50
                    let spacing: CGFloat = 8
                    let progressBarOffset: CGFloat = horizontalPadding + timeLabelWidth + spacing
                    let progressBarWidth: CGFloat = geometry.size.width - (2 * horizontalPadding) - (2 * timeLabelWidth) - (2 * spacing)
                    let previewWidth: CGFloat = 176 // 160 + 16 padding
                    let xOffset = progressBarOffset + (progressBarWidth * previewProgress) - (previewWidth / 2)
                    let clampedX = max(0, min(geometry.size.width - previewWidth, xOffset))

                    let storyboardCenterX = clampedX + previewWidth / 2

                    seekPreviewView(storyboard: storyboard)
                        .offset(x: clampedX, y: -150)

                    if showChapters, let chapter = playerState.chapters.last(where: { $0.startTime <= previewProgress * playerState.duration }) {
                        ChapterCapsuleView(title: chapter.title, buttonBackground: .none)
                            .positioned(xTarget: storyboardCenterX, availableWidth: geometry.size.width)
                            .offset(y: -176)
                    }
                }
            } else if (isDragging || isHoveringProgress),
                      !playerState.isLive {
                GeometryReader { geometry in
                    let previewProgress = isDragging ? dragProgress : hoverProgress
                    let horizontalPadding: CGFloat = 16
                    let timeLabelWidth: CGFloat = 50
                    let spacing: CGFloat = 8
                    let progressBarOffset: CGFloat = horizontalPadding + timeLabelWidth + spacing
                    let progressBarWidth: CGFloat = geometry.size.width - (2 * horizontalPadding) - (2 * timeLabelWidth) - (2 * spacing)
                    let previewWidth: CGFloat = 80
                    let xOffset = progressBarOffset + (progressBarWidth * previewProgress) - (previewWidth / 2)
                    let clampedX = max(0, min(geometry.size.width - previewWidth, xOffset))

                    let timeCenterX = clampedX + previewWidth / 2

                    SeekTimePreviewView(
                        seekTime: previewProgress * playerState.duration,
                        buttonBackground: .none,
                        theme: .dark
                    )
                    .offset(x: clampedX, y: -60)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .animation(.easeInOut(duration: 0.15), value: isDragging || isHoveringProgress)

                    if showChapters, let chapter = playerState.chapters.last(where: { $0.startTime <= previewProgress * playerState.duration }) {
                        ChapterCapsuleView(title: chapter.title, buttonBackground: .none)
                            .positioned(xTarget: timeCenterX, availableWidth: geometry.size.width)
                            .offset(y: -86)
                    }
                }
            }
        }
    }

    // MARK: - Top Row Controls

    private var topRowControls: some View {
        HStack(spacing: 0) {
            // Left: Volume controls
            volumeControls

            Spacer()

            // Center: Transport controls
            transportControls

            Spacer()

            // Right: Action buttons (settings, PiP, fullscreen)
            trailingActionControls
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 4) {
            // Skip backward
            Button {
                seekBackwardTrigger += 1
                Task { await onSeekBackward(10) }
            } label: {
                Image(systemName: "10.arrow.trianglehead.counterclockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekBackwardTrigger)
            }
            .buttonStyle(MacOSControlButtonStyle())
            .disabled(isTransportDisabled)

            // Play/Pause
            if !isTransportDisabled {
                Button {
                    onPlayPause()
                } label: {
                    Image(systemName: playPauseIcon)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                }
                .buttonStyle(MacOSControlButtonStyle())
            } else {
                // Spacer to maintain layout
                Color.clear
                    .frame(width: 32, height: 32)
            }

            // Skip forward
            Button {
                seekForwardTrigger += 1
                Task { await onSeekForward(10) }
            } label: {
                Image(systemName: "10.arrow.trianglehead.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .symbolEffect(.rotate.byLayer, options: .speed(2).nonRepeating, value: seekForwardTrigger)
            }
            .buttonStyle(MacOSControlButtonStyle())
            .disabled(isTransportDisabled)

            // Play next (if queue has items)
            if let onPlayNext, playerState.hasNext {
                Button {
                    playNextTapCount += 1
                    Task { await onPlayNext() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: playNextTapCount)
                }
                .buttonStyle(MacOSControlButtonStyle())
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
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()

                // Progress bar (expands to fill available width)
                progressBar

                // Duration
                Text(playerState.formattedDuration)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                        if !isDragging {
                            isDragging = true
                            onInteractionStarted?()
                        }
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = progress
                    }
                    .onEnded { value in
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
        }
        .frame(height: 20)
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

    // MARK: - Trailing Action Controls

    private var trailingActionControls: some View {
        HStack(spacing: 4) {
            // Settings
            if let onShowSettings {
                Button {
                    onShowSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MacOSControlButtonStyle())
            }

            // PiP
            if let onTogglePiP, playerState.isPiPPossible {
                Button {
                    onTogglePiP()
                } label: {
                    Image(systemName: playerState.pipState == .active ? "pip.exit" : "pip.enter")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MacOSControlButtonStyle())
            }

            // Fullscreen
            if let onToggleFullscreen {
                Button {
                    onToggleFullscreen()
                } label: {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MacOSControlButtonStyle())
            }
        }
    }

    private var volumeControls: some View {
        HStack(spacing: 2) {
            // Mute/unmute button
            Button {
                onMuteToggled?()
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MacOSControlButtonStyle())

            // Volume slider
            Slider(
                value: Binding(
                    get: { Double(playerState.volume) },
                    set: { newValue in
                        playerState.volume = Float(newValue)
                        onVolumeChanged?(Float(newValue))
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        onInteractionStarted?()
                    } else {
                        onInteractionEnded?()
                    }
                }
            )
            .frame(width: 70)
            .controlSize(.mini)
            .disabled(playerState.isMuted)
            .opacity(playerState.isMuted ? 0.5 : 1.0)
        }
    }

    private var volumeIcon: String {
        if playerState.isMuted || playerState.volume == 0 {
            return "speaker.slash.fill"
        } else if playerState.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if playerState.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Button Style

/// Subtle button style for macOS control bar buttons.
struct MacOSControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.3)

        MacOSControlBar(
            playerState: PlayerState(),
            onPlayPause: {},
            onSeek: { _ in },
            onSeekForward: { _ in },
            onSeekBackward: { _ in }
        )
        .frame(width: 650)
    }
    .frame(width: 800, height: 200)
}

#endif
