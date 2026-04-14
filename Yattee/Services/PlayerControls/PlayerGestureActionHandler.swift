//
//  PlayerGestureActionHandler.swift
//  Yattee
//
//  Handles execution of gesture actions on the player.
//

import Foundation

/// Result of executing a tap gesture action.
struct TapActionResult: Sendable {
    /// The action that was executed.
    let action: TapGestureAction

    /// The zone that was tapped.
    let position: TapZonePosition

    /// Accumulated seek seconds (for rapid seek taps).
    let accumulatedSeconds: Int?

    /// New state description (e.g., "1.5x" for speed, "Muted" for mute).
    let newState: String?
}

/// Actor that handles gesture action execution with seek accumulation.
actor PlayerGestureActionHandler {
    /// Playback speed sequence (YouTube-style).
    static let playbackSpeedSequence: [Double] = [
        0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
    ]

    /// Accumulation window duration in seconds.
    private let accumulationWindow: TimeInterval = 2.0

    // MARK: - State

    private var accumulatedSeekSeconds: Int = 0
    private var lastSeekPosition: TapZonePosition?
    private var lastSeekTime: Date?
    private var lastSeekDirection: SeekDirection?
    private var accumulationResetTask: Task<Void, Never>?

    /// Direction of seek for clamping calculations.
    private enum SeekDirection {
        case forward
        case backward
    }

    // MARK: - Current Player State

    private var currentTime: TimeInterval = 0
    private var duration: TimeInterval = 0

    // MARK: - Tap Action Handling

    /// Handles a tap gesture action.
    /// - Parameters:
    ///   - action: The action to execute.
    ///   - position: The zone that was tapped.
    ///   - playerState: Current player state for context.
    /// - Returns: Result describing what was executed.
    func handleTapAction(
        _ action: TapGestureAction,
        position: TapZonePosition
    ) async -> TapActionResult {
        switch action {
        case .seekForward(let seconds), .seekBackward(let seconds):
            return await handleSeekAction(action, position: position, seconds: seconds)
        default:
            return TapActionResult(
                action: action,
                position: position,
                accumulatedSeconds: nil,
                newState: nil
            )
        }
    }

    private func handleSeekAction(
        _ action: TapGestureAction,
        position: TapZonePosition,
        seconds: Int
    ) async -> TapActionResult {
        let now = Date()

        // Determine seek direction
        let direction: SeekDirection
        switch action {
        case .seekForward:
            direction = .forward
        case .seekBackward:
            direction = .backward
        default:
            return TapActionResult(action: action, position: position, accumulatedSeconds: nil, newState: nil)
        }

        // Calculate max seekable time in this direction
        let maxSeekable: Int
        switch direction {
        case .forward:
            maxSeekable = max(0, Int(duration - currentTime))
        case .backward:
            maxSeekable = max(0, Int(currentTime))
        }

        // Check if we should accumulate with previous seek (same position AND same direction)
        let shouldAccumulate = lastSeekTime.map { now.timeIntervalSince($0) < accumulationWindow } ?? false
            && lastSeekPosition == position
            && lastSeekDirection == direction

        if shouldAccumulate {
            // Only accumulate if we haven't hit the max
            if accumulatedSeekSeconds < maxSeekable {
                accumulatedSeekSeconds = min(accumulatedSeekSeconds + seconds, maxSeekable)
            }
            // If already at max, don't increment (stop incrementing behavior)
        } else {
            // Start new accumulation (direction changed or new gesture)
            accumulatedSeekSeconds = min(seconds, maxSeekable)
        }

        lastSeekPosition = position
        lastSeekTime = now
        lastSeekDirection = direction

        // Cancel previous reset task and schedule new one
        accumulationResetTask?.cancel()
        accumulationResetTask = Task { [accumulationWindow] in
            try? await Task.sleep(for: .seconds(accumulationWindow))
            guard !Task.isCancelled else { return }
            self.resetAccumulation()
        }

        return TapActionResult(
            action: action,
            position: position,
            accumulatedSeconds: accumulatedSeekSeconds,
            newState: nil
        )
    }

    private func resetAccumulation() {
        accumulatedSeekSeconds = 0
        lastSeekPosition = nil
        lastSeekTime = nil
        lastSeekDirection = nil
    }

    /// Cancels any pending seek accumulation and resets state.
    /// Call this when switching seek direction or executing a different action.
    func cancelAccumulation() {
        accumulationResetTask?.cancel()
        accumulationResetTask = nil
        resetAccumulation()
    }

    /// Returns the current accumulated seek seconds.
    func currentAccumulatedSeconds() -> Int {
        accumulatedSeekSeconds
    }

    // MARK: - Playback Speed Cycling

    /// Returns the next playback speed in the sequence.
    /// - Parameter currentSpeed: The current playback speed.
    /// - Returns: The next speed (wraps around).
    func nextPlaybackSpeed(currentSpeed: Double) -> Double {
        let sequence = Self.playbackSpeedSequence

        // Find current index
        if let index = sequence.firstIndex(where: { abs($0 - currentSpeed) < 0.01 }) {
            let nextIndex = (index + 1) % sequence.count
            return sequence[nextIndex]
        }

        // If current speed not in sequence, find closest and go to next
        let closest = sequence.min { abs($0 - currentSpeed) < abs($1 - currentSpeed) } ?? 1.0
        if let index = sequence.firstIndex(of: closest) {
            let nextIndex = (index + 1) % sequence.count
            return sequence[nextIndex]
        }

        return 1.0
    }

    /// Formats a playback speed for display.
    /// - Parameter speed: The playback speed.
    /// - Returns: Formatted string (e.g., "1.5x").
    func formatPlaybackSpeed(_ speed: Double) -> String {
        if speed == floor(speed) {
            return String(format: "%.0fx", speed)
        } else {
            return String(format: "%.2gx", speed)
        }
    }

    // MARK: - Player State Updates

    /// Updates the current player state for seek clamping calculations.
    func updatePlayerState(
        currentTime: TimeInterval,
        duration: TimeInterval
    ) {
        self.currentTime = currentTime
        self.duration = duration
    }
}
