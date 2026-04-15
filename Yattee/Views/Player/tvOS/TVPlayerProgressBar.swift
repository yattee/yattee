//
//  TVPlayerProgressBar.swift
//  Yattee
//
//  Focusable progress bar for tvOS with smooth touchpad scrubbing support.
//

#if os(tvOS)
import SwiftUI
import UIKit

/// Progress bar with smooth scrubbing support for tvOS Siri Remote touchpad.
struct TVPlayerProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedTime: TimeInterval
    let storyboard: Storyboard?
    let chapters: [VideoChapter]
    let onSeek: (TimeInterval) -> Void
    /// Called when scrubbing state changes - parent should stop auto-hide timer when true
    var onScrubbingChanged: ((Bool) -> Void)?
    /// Whether the current stream is live
    let isLive: Bool
    /// Whether to show chapter markers on the progress bar (default: true)
    var showChapters: Bool = true
    /// SponsorBlock segments to display on the progress bar.
    var sponsorSegments: [SponsorBlockSegment] = []
    /// Settings for SponsorBlock segment display.
    var sponsorBlockSettings: SponsorBlockSegmentSettings = .default
    /// Color for the played portion of the progress bar.
    var playedColor: Color = .red
    /// Pending target time from the parent's accumulating remote-seek flow
    /// (arrow presses while the bar is focused but not in SELECT scrub mode).
    /// When set, the handle and played portion reflect this value.
    var remoteSeekTime: TimeInterval? = nil
    /// Called when the bar is focused (not scrubbing) and user presses left/right.
    /// Parameter: `forward` — true for right, false for left.
    var onRemoteSeek: ((Bool) -> Void)? = nil
    /// Parent bumps this to request the bar to cancel any in-progress scrub
    /// without performing a seek (used for the Menu button).
    var cancelScrubTrigger: UUID? = nil

    /// Track focus state internally.
    @FocusState private var isFocused: Bool

    /// Time during active scrubbing (nil when not scrubbing).
    @State private var scrubTime: TimeInterval?

    /// Whether user is actively scrubbing.
    @State private var isScrubbing = false

    /// Accumulated pan translation for scrubbing.
    @State private var panAccumulator: CGFloat = 0

    /// Consecutive-event streak for rapid D-pad/touchpad scrubbing.
    /// tvOS routes touchpad swipes as rapid `onMoveCommand` events, so we
    /// amplify step size when events arrive in quick succession.
    @State private var dpadStreakCount: Int = 0
    @State private var lastDPadTime: Date?
    @State private var lastDPadDirection: MoveCommandDirection?

    /// The time to display. SELECT-based scrub takes priority, then the
    /// parent's pending remote-seek target, then the actual playback time.
    private var displayTime: TimeInterval {
        scrubTime ?? remoteSeekTime ?? currentTime
    }

    /// Progress as a fraction (0-1).
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(displayTime / duration, 0), 1)
    }

    /// Buffered progress as a fraction (0-1).
    private var bufferedProgress: Double {
        guard duration > 0 else { return 0 }
        return min(bufferedTime / duration, 1)
    }

    var body: some View {
        Button {
            if isScrubbing {
                commitScrub()
            } else if !isLive {
                enterScrubMode()
            }
        } label: {
            progressContent
        }
        .buttonStyle(TVProgressBarButtonStyle(isFocused: isFocused))
        .disabled(isLive)
        .overlay {
            // Gesture capture layer (only when scrubbing). Siri Remote pan
            // gestures are indirect touches, so matching the button's size
            // is sufficient — no need to expand and disturb parent layout.
            if isScrubbing {
                TVPanGestureView(
                    onPanChanged: { translation, velocity in
                        handlePan(translation: translation, velocity: velocity)
                    },
                    onPanEnded: {
                        handlePanEnded()
                    }
                )
            }
        }
        .focused($isFocused)
        .onMoveCommand { direction in
            if isScrubbing {
                // D-pad fallback while in SELECT-based scrub mode.
                handleDPad(direction: direction)
            } else if !isLive, direction == .left || direction == .right {
                // Focused but not scrubbing: delegate accumulating remote seek
                // to parent. Up/down falls through to normal focus navigation.
                onRemoteSeek?(direction == .right)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitScrub()
            }
        }
        .onChange(of: cancelScrubTrigger) { _, newValue in
            guard newValue != nil, isScrubbing else { return }
            cancelScrub()
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .animation(.easeInOut(duration: 0.1), value: isScrubbing)
    }

    private func enterScrubMode() {
        scrubTime = currentTime
        panAccumulator = 0
        withAnimation(.easeOut(duration: 0.15)) {
            isScrubbing = true
        }
        onScrubbingChanged?(true)
    }

    private var progressContent: some View {
        VStack(spacing: 12) {
            // Progress bar (hide for live streams)
            if !isLive {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Progress bar with chapter segments (4pt gaps for tvOS visibility)
                        SegmentedProgressBar(
                            chapters: showChapters ? chapters : [],
                            duration: duration,
                            currentTime: displayTime,
                            bufferedTime: bufferedTime,
                            height: isFocused ? (isScrubbing ? 16 : 12) : 6,
                            gapWidth: 4,
                            playedColor: isFocused ? playedColor : .white,
                            bufferedColor: .white.opacity(0.4),
                            backgroundColor: .white.opacity(0.2),
                            sponsorSegments: sponsorSegments,
                            sponsorBlockSettings: sponsorBlockSettings
                        )

                        // Scrub handle (visible when focused)
                        if isFocused {
                            Circle()
                                .fill(.white)
                                .frame(width: isScrubbing ? 32 : 24, height: isScrubbing ? 32 : 24)
                                .shadow(color: .black.opacity(0.3), radius: 4)
                                .offset(x: (geometry.size.width * progress) - (isScrubbing ? 16 : 12))
                                .animation(.easeOut(duration: 0.1), value: progress)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .overlay(alignment: .top) {
                        scrubPreviewOverlay(geometry: geometry)
                    }
                }
                .frame(height: 20)
            }

            // Time labels
            HStack {
                // Current time or LIVE indicator
                if isLive {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "player.live"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                } else {
                    Text(displayTime.formattedAsTimestamp)
                        .monospacedDigit()
                        .font(.subheadline)
                        .fontWeight(isScrubbing ? .semibold : .regular)
                        .foregroundStyle(.white)
                }

                Spacer()

                // Remaining time (only for non-live)
                if !isLive {
                    Text("-\(max(0, duration - displayTime).formattedAsTimestamp)")
                        .monospacedDigit()
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

        }
    }

    @ViewBuilder
    private func scrubPreviewOverlay(geometry: GeometryProxy) -> some View {
        if isScrubbing {
            let seekTime = scrubTime ?? currentTime
            let currentChapter = showChapters ? chapters.last(where: { $0.startTime <= seekTime }) : nil
            // Storyboard panel is 320 thumbnail + 4pt horizontal padding * 2 = 328, plus shadow.
            // Use a slightly larger clamp width so the shadow stays on screen.
            let panelWidth: CGFloat = 344
            // Panel height: thumbnail 180 + 4pt vertical padding * 2 = 188 (round up for shadow).
            let panelHeight: CGFloat = 200
            let capsuleSpacing: CGFloat = 8
            // Approximate capsule height (24pt text + 6pt padding * 2 + shadow) — used only
            // for vertical positioning, not for layout sizing.
            let capsuleApproxHeight: CGFloat = 44

            let xTarget = geometry.size.width * progress
            let halfPanel = panelWidth / 2
            let clampedPanelX = max(halfPanel, min(geometry.size.width - halfPanel, xTarget))
            let panelCenterY = -panelHeight / 2 - 16
            let capsuleCenterY = -panelHeight - 16 - capsuleSpacing - capsuleApproxHeight / 2

            ZStack {
                // Storyboard panel — follows scrub handle, tight horizontal clamp.
                Group {
                    if let storyboard {
                        TVSeekPreviewView(
                            storyboard: storyboard,
                            seekTime: seekTime
                        )
                    } else {
                        Text(seekTime.formattedAsTimestamp)
                            .font(.system(size: 48, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                            )
                    }
                }
                .fixedSize()
                .position(x: clampedPanelX, y: panelCenterY)

                // Chapter capsule — sized to its title (up to screen width minus margin),
                // positioned to follow the scrub handle and clamped to stay on screen.
                if let currentChapter {
                    TVChapterCapsuleView(title: currentChapter.title)
                        .positioned(xTarget: xTarget, availableWidth: geometry.size.width)
                        .position(x: geometry.size.width / 2, y: capsuleCenterY)
                }
            }
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Pan Gesture Handling

    private func handlePan(translation: CGFloat, velocity: CGFloat) {
        guard duration > 0, isScrubbing else { return }

        // Cancel any pending seek when user starts new pan
        seekTask?.cancel()

        // Calculate scrub sensitivity based on duration
        // Lower values = slower/finer scrubbing
        let baseSensitivity: CGFloat
        if duration > 3600 {
            baseSensitivity = duration / 1500
        } else if duration > 600 {
            baseSensitivity = duration / 2000
        } else {
            baseSensitivity = duration / 3000
        }

        // Non-linear velocity response: slow swipes stay precise, fast flicks accelerate.
        let normalizedVelocity = abs(velocity) / 500
        let velocityMultiplier = min(max(pow(normalizedVelocity, 1.4), 0.3), 6.0)
        let adjustedSensitivity = baseSensitivity * velocityMultiplier

        // Update scrub time based on translation delta
        let delta = translation - panAccumulator
        panAccumulator = translation

        let timeChange = TimeInterval(delta * adjustedSensitivity)
        let currentScrubTime = scrubTime ?? currentTime
        scrubTime = min(max(0, currentScrubTime + timeChange), duration)
    }

    private func handlePanEnded() {
        // Reset accumulator for next swipe
        panAccumulator = 0
        // Schedule debounced seek but stay in scrub mode
        scheduleSeek()
    }

    @State private var seekTask: Task<Void, Never>?

    private func scheduleSeek() {
        seekTask?.cancel()
        seekTask = Task {
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let time = scrubTime {
                    onSeek(time)
                }
            }
        }
    }

    // MARK: - D-Pad Fallback

    private func handleDPad(direction: MoveCommandDirection) {
        guard duration > 0, isScrubbing else { return }

        switch direction {
        case .left, .right:
            // Track event rate. When events arrive quickly in the same
            // direction (i.e. a touchpad swipe being rasterized into move
            // commands), grow the streak and scale the step size up.
            let now = Date()
            let gap = lastDPadTime.map { now.timeIntervalSince($0) } ?? .infinity

            // tvOS throttles onMoveCommand at ~300-400ms even during a fast
            // swipe, so we need a generous window to still recognize a burst.
            if gap < 0.5, lastDPadDirection == direction {
                dpadStreakCount = min(dpadStreakCount + 1, 30)
            } else {
                dpadStreakCount = 1
            }
            lastDPadTime = now
            lastDPadDirection = direction

            // Base step based on video length.
            let baseStep: TimeInterval
            if duration > 3600 {
                baseStep = 15
            } else if duration > 600 {
                baseStep = 8
            } else {
                baseStep = 5
            }

            // Steeper curve so a swipe (few events) actually covers ground.
            let streakMultiplier = pow(Double(dpadStreakCount), 1.6)
            let scrubAmount = baseStep * streakMultiplier

            let currentScrubTime = scrubTime ?? currentTime
            if direction == .left {
                scrubTime = max(0, currentScrubTime - scrubAmount)
            } else {
                scrubTime = min(duration, currentScrubTime + scrubAmount)
            }
            scheduleSeek()

        case .up, .down:
            // Exit scrub mode and let navigation happen
            commitScrub()
            dpadStreakCount = 0
            lastDPadTime = nil
            lastDPadDirection = nil

        @unknown default:
            break
        }
    }

    // MARK: - Commit

    private func commitScrub() {
        seekTask?.cancel()
        seekTask = nil

        let wasScrubbing = isScrubbing

        if let time = scrubTime {
            onSeek(time)
        }

        withAnimation(.easeOut(duration: 0.15)) {
            scrubTime = nil
            isScrubbing = false
        }
        panAccumulator = 0
        dpadStreakCount = 0
        lastDPadTime = nil
        lastDPadDirection = nil

        if wasScrubbing {
            onScrubbingChanged?(false)
        }
    }

    private func cancelScrub() {
        seekTask?.cancel()
        seekTask = nil

        let wasScrubbing = isScrubbing

        withAnimation(.easeOut(duration: 0.15)) {
            scrubTime = nil
            isScrubbing = false
        }
        panAccumulator = 0
        dpadStreakCount = 0
        lastDPadTime = nil
        lastDPadDirection = nil

        if wasScrubbing {
            onScrubbingChanged?(false)
        }
    }

}

// MARK: - Pan Gesture View

/// UIKit view that captures pan gestures on the Siri Remote touchpad.
struct TVPanGestureView: UIViewRepresentable {
    let onPanChanged: (CGFloat, CGFloat) -> Void  // (translation, velocity)
    let onPanEnded: () -> Void

    func makeUIView(context: Context) -> TVPanGestureUIView {
        let view = TVPanGestureUIView()
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        return view
    }

    func updateUIView(_ uiView: TVPanGestureUIView, context: Context) {
        uiView.onPanChanged = onPanChanged
        uiView.onPanEnded = onPanEnded
    }
}

class TVPanGestureUIView: UIView {
    var onPanChanged: ((CGFloat, CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?

    private var panRecognizer: UIPanGestureRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGesture()
    }

    private func setupGesture() {
        panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        addGestureRecognizer(panRecognizer)

        // Make view focusable
        isUserInteractionEnabled = true
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self).x
        let velocity = gesture.velocity(in: self).x

        switch gesture.state {
        case .began, .changed:
            onPanChanged?(translation, velocity)
        case .ended, .cancelled:
            onPanEnded?()
            gesture.setTranslation(.zero, in: self)
        default:
            break
        }
    }
}

// MARK: - Button Style

/// Button style for the progress bar.
struct TVProgressBarButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

#endif
