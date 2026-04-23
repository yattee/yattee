//
//  SeekGestureCalculator.swift
//  Yattee
//
//  Calculator for horizontal seek gesture recognition and seek delta computation.
//

import Foundation

/// Stateless calculator for horizontal seek gesture logic.
/// Handles gesture recognition, seek delta calculation, and boundary clamping.
enum SeekGestureCalculator {
    // MARK: - Constants

    /// Minimum horizontal distance (in points) required to recognize the gesture.
    static let activationThreshold: CGFloat = 20

    /// Maximum angle from horizontal (in degrees) to recognize as horizontal gesture.
    /// Movements beyond this angle are not recognized, reserving vertical axis for future gestures.
    static let maxAngleFromHorizontal: Double = 30

    /// Minimum seek delta (in seconds) for the gesture to commit.
    /// Gestures resulting in less than this are ignored.
    static let minimumSeekSeconds: Double = 5

    /// Range for duration-based multiplier.
    static let durationMultiplierRange: ClosedRange<Double> = 0.5...3.0

    /// Reference duration (in seconds) for multiplier calculation.
    /// A 10-minute video has a multiplier of 1.0.
    static let referenceDuration: Double = 600

    // MARK: - Gesture Recognition

    /// Determines if a drag translation represents a horizontal movement.
    /// - Parameter translation: The drag translation (x, y).
    /// - Returns: `true` if the movement is predominantly horizontal and exceeds the activation threshold.
    static func isHorizontalMovement(translation: CGSize) -> Bool {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)

        // Must exceed activation threshold
        guard horizontalDistance >= activationThreshold else {
            return false
        }

        // Calculate angle from horizontal axis
        // atan2 returns angle in radians, convert to degrees
        let angleRadians = atan2(verticalDistance, horizontalDistance)
        let angleDegrees = angleRadians * 180 / .pi

        // Must be within max angle from horizontal
        return angleDegrees <= maxAngleFromHorizontal
    }

    // MARK: - Duration Multiplier

    /// Calculates the duration-based multiplier for seek sensitivity.
    /// Shorter videos get smaller multipliers (more precise), longer videos get larger multipliers (faster seeking).
    /// - Parameter videoDuration: The video duration in seconds.
    /// - Returns: A multiplier between 0.5 and 3.0.
    static func calculateDurationMultiplier(videoDuration: Double) -> Double {
        guard videoDuration > 0 else { return 1.0 }
        let rawMultiplier = videoDuration / referenceDuration
        return rawMultiplier.clamped(to: durationMultiplierRange)
    }

    // MARK: - Seek Delta Calculation

    /// Calculates the seek delta based on drag distance and video properties.
    /// - Parameters:
    ///   - dragDistance: Horizontal drag distance in points (positive = forward, negative = backward).
    ///   - screenWidth: Screen width in points for normalization.
    ///   - videoDuration: Video duration in seconds.
    ///   - sensitivity: User's selected sensitivity preset.
    /// - Returns: Seek delta in seconds, or `nil` if the delta is below minimum threshold.
    static func calculateSeekDelta(
        dragDistance: CGFloat,
        screenWidth: CGFloat,
        videoDuration: Double,
        sensitivity: SeekGestureSensitivity
    ) -> Double? {
        guard screenWidth > 0, videoDuration > 0 else { return nil }

        let baseSeconds = sensitivity.baseSecondsPerScreenWidth
        let multiplier = calculateDurationMultiplier(videoDuration: videoDuration)
        let effectiveSecondsPerScreenWidth = baseSeconds * multiplier

        let normalizedDrag = Double(dragDistance / screenWidth)
        let seekDelta = normalizedDrag * effectiveSecondsPerScreenWidth

        // Apply minimum threshold
        guard abs(seekDelta) >= minimumSeekSeconds else {
            return nil
        }

        return seekDelta
    }

    // MARK: - Boundary Clamping

    /// Result of clamping a seek time to video boundaries.
    struct ClampResult: Equatable, Sendable {
        /// The clamped seek time.
        let seekTime: Double
        /// Whether the boundary was hit (start or end).
        let hitBoundary: Bool
    }

    /// Clamps a seek operation to valid video boundaries.
    /// - Parameters:
    ///   - currentTime: Current playback position in seconds.
    ///   - seekDelta: Desired seek delta in seconds (can be negative).
    ///   - duration: Video duration in seconds.
    /// - Returns: The clamped seek time and whether a boundary was hit.
    static func clampSeekTime(
        currentTime: Double,
        seekDelta: Double,
        duration: Double
    ) -> ClampResult {
        let targetTime = currentTime + seekDelta
        let clampedTime = targetTime.clamped(to: 0...max(0, duration))
        let hitBoundary = clampedTime != targetTime

        return ClampResult(seekTime: clampedTime, hitBoundary: hitBoundary)
    }
}

// MARK: - Double Extension

private extension Double {
    /// Clamps a value to a closed range.
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
