//
//  TapGestureFeedbackView.swift
//  Yattee
//
//  Visual feedback overlay for tap gesture actions.
//

import SwiftUI

#if os(tvOS)
private let tapFeedbackIconSize: CGFloat = 88
private let tapFeedbackTextSize: CGFloat = 32
private let tapFeedbackCircleSize: CGFloat = 240
private let tapFeedbackVStackSpacing: CGFloat = 16
private let tapFeedbackPadding: CGFloat = 40
#else
private let tapFeedbackIconSize: CGFloat = 44
private let tapFeedbackTextSize: CGFloat = 16
private let tapFeedbackCircleSize: CGFloat = 120
private let tapFeedbackVStackSpacing: CGFloat = 8
private let tapFeedbackPadding: CGFloat = 20
#endif

/// Position for tap feedback display.
enum TapFeedbackPosition {
    case left
    case center
    case right

    /// Determines position based on action type (YouTube-style).
    static func forAction(_ action: TapGestureAction) -> TapFeedbackPosition {
        switch action {
        case .seekBackward:
            .left
        case .seekForward:
            .right
        default:
            .center
        }
    }
}

/// Visual feedback shown when a tap gesture is triggered.
struct TapGestureFeedbackView: View {
    let action: TapGestureAction
    let accumulatedSeconds: Int?
    let onComplete: () -> Void

    @State private var isVisible = false
    @State private var scale: CGFloat = 0.8
    @State private var dismissTask: Task<Void, Never>?

    private var position: TapFeedbackPosition {
        TapFeedbackPosition.forAction(action)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack {
                if position == .right {
                    Spacer()
                }

                feedbackContent
                    .frame(width: position == .center ? nil : geometry.size.width * 0.3)
                    .frame(maxWidth: position == .center ? 200 : nil)

                if position == .left {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(scale)
        .onAppear {
            showAndScheduleDismiss()
        }
        .onChange(of: accumulatedSeconds) { _, _ in
            // Reset dismiss timer when accumulated value changes (user tapped again)
            scheduleDismiss()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func showAndScheduleDismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            isVisible = true
            scale = 1.0
        }
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        // Cancel any existing dismiss task
        dismissTask?.cancel()

        // Schedule new dismiss
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.15)) {
                isVisible = false
                scale = 0.8
            }

            try? await Task.sleep(for: .seconds(0.15))
            guard !Task.isCancelled else { return }

            onComplete()
        }
    }

    @ViewBuilder
    private var feedbackContent: some View {
        VStack(spacing: tapFeedbackVStackSpacing) {
            Image(systemName: iconName)
                .font(.system(size: tapFeedbackIconSize, weight: .medium))
                .foregroundStyle(.white)

            if let text = feedbackText {
                Text(text)
                    .font(.system(size: tapFeedbackTextSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(tapFeedbackPadding)
        .background(
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: tapFeedbackCircleSize, height: tapFeedbackCircleSize)
        )
    }

    private var iconName: String {
        switch action {
        case .togglePlayPause:
            "playpause.fill"
        case .seekForward:
            "arrow.trianglehead.clockwise"
        case .seekBackward:
            "arrow.trianglehead.counterclockwise"
        case .toggleFullscreen:
            "arrow.up.left.and.arrow.down.right"
        case .togglePiP:
            "pip"
        case .playNext:
            "forward.fill"
        case .playPrevious:
            "backward.fill"
        case .cyclePlaybackSpeed:
            "gauge.with.dots.needle.67percent"
        case .toggleMute:
            "speaker.slash.fill"
        }
    }

    private var feedbackText: String? {
        switch action {
        case .seekForward(let seconds):
            if let accumulated = accumulatedSeconds, accumulated != seconds {
                return "+\(accumulated)s"
            }
            return "+\(seconds)s"

        case .seekBackward(let seconds):
            if let accumulated = accumulatedSeconds, accumulated != seconds {
                return "-\(accumulated)s"
            }
            return "-\(seconds)s"

        case .cyclePlaybackSpeed:
            // This should be passed in from the action handler
            return nil

        default:
            return nil
        }
    }
}

// MARK: - Seek Feedback (YouTube-style ripple)

/// YouTube-style seek feedback with multiple ripples.
struct SeekFeedbackView: View {
    let isForward: Bool
    let seconds: Int
    let onComplete: () -> Void

    @State private var rippleCount = 0

    var body: some View {
        GeometryReader { geometry in
            HStack {
                if isForward {
                    Spacer()
                }

                ZStack {
                    // Ripple circles
                    ForEach(0..<3) { index in
                        SeekRipple(
                            isForward: isForward,
                            delay: Double(index) * 0.1,
                            isActive: rippleCount > index
                        )
                    }

                    // Icon and text
                    VStack(spacing: 4) {
                        Image(systemName: isForward ? "arrow.trianglehead.clockwise" : "arrow.trianglehead.counterclockwise")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.white)

                        Text("\(isForward ? "+" : "-")\(seconds)s")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: geometry.size.width * 0.35, height: geometry.size.height)

                if !isForward {
                    Spacer()
                }
            }
        }
        .onAppear {
            // Animate ripples
            withAnimation(.easeOut(duration: 0.1)) {
                rippleCount = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.1)) {
                    rippleCount = 2
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.1)) {
                    rippleCount = 3
                }
            }

            // Auto-dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onComplete()
            }
        }
    }
}

private struct SeekRipple: View {
    let isForward: Bool
    let delay: Double
    let isActive: Bool

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.2))
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.easeOut(duration: 0.3).delay(delay)) {
                        scale = 1.0
                        opacity = 0.3
                    }
                    withAnimation(.easeIn(duration: 0.5).delay(delay + 0.3)) {
                        opacity = 0
                    }
                }
            }
    }
}

#Preview {
    ZStack {
        Color.black

        TapGestureFeedbackView(
            action: .seekForward(seconds: 10),
            accumulatedSeconds: 30,
            onComplete: {}
        )
    }
}
