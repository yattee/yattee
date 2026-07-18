//
//  SeekGestureTests.swift
//  YatteeTests
//
//  Tests for horizontal seek gesture models and algorithm.
//

import Foundation
import Testing
@testable import Yattee

@Suite("Seek Gesture Tests")
struct SeekGestureTests {

    // MARK: - SeekGestureSensitivity Tests

    @Suite("SeekGestureSensitivity")
    struct SeekGestureSensitivityTests {

        @Test("Base seconds per screen width values")
        func baseSecondsPerScreenWidth() {
            #expect(SeekGestureSensitivity.low.baseSecondsPerScreenWidth == 30)
            #expect(SeekGestureSensitivity.medium.baseSecondsPerScreenWidth == 60)
            #expect(SeekGestureSensitivity.high.baseSecondsPerScreenWidth == 120)
        }

        @Test("All sensitivities have display names")
        func displayNames() {
            for sensitivity in SeekGestureSensitivity.allCases {
                #expect(!sensitivity.displayName.isEmpty)
                #expect(!sensitivity.description.isEmpty)
            }
        }

        @Test("Sensitivity is codable")
        func isCodable() throws {
            for original in SeekGestureSensitivity.allCases {
                let encoded = try JSONEncoder().encode(original)
                let decoded = try JSONDecoder().decode(SeekGestureSensitivity.self, from: encoded)
                #expect(decoded == original)
            }
        }
    }

    // MARK: - SeekGestureSettings Tests

    @Suite("SeekGestureSettings")
    struct SeekGestureSettingsTests {

        @Test("Default settings are disabled")
        func defaultSettingsAreDisabled() {
            let settings = SeekGestureSettings.default
            #expect(settings.isEnabled == false)
        }

        @Test("Default sensitivity is medium")
        func defaultSensitivityIsMedium() {
            let settings = SeekGestureSettings.default
            #expect(settings.sensitivity == .medium)
        }

        @Test("Settings is codable")
        func isCodable() throws {
            let original = SeekGestureSettings(isEnabled: true, sensitivity: .high)
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(SeekGestureSettings.self, from: encoded)

            #expect(decoded.isEnabled == original.isEnabled)
            #expect(decoded.sensitivity == original.sensitivity)
        }

        @Test("Settings is hashable")
        func isHashable() {
            let settings1 = SeekGestureSettings(isEnabled: true, sensitivity: .low)
            let settings2 = SeekGestureSettings(isEnabled: true, sensitivity: .low)
            let settings3 = SeekGestureSettings(isEnabled: false, sensitivity: .high)

            #expect(settings1 == settings2)
            #expect(settings1 != settings3)
            #expect(settings1.hashValue == settings2.hashValue)
        }
    }

    // MARK: - SeekGestureCalculator Tests

    @Suite("SeekGestureCalculator")
    struct SeekGestureCalculatorTests {

        // MARK: - Horizontal Movement Detection

        @Suite("isHorizontalMovement")
        struct IsHorizontalMovementTests {

            @Test("Horizontal movement exceeding threshold is recognized")
            func horizontalExceedingThreshold() {
                // 25pt horizontal, 0pt vertical - should be recognized
                let translation = CGSize(width: 25, height: 0)
                #expect(SeekGestureCalculator.isHorizontalMovement(translation: translation) == true)
            }

            @Test("Horizontal movement below threshold is not recognized")
            func horizontalBelowThreshold() {
                // 15pt horizontal - below 20pt threshold
                let translation = CGSize(width: 15, height: 0)
                #expect(SeekGestureCalculator.isHorizontalMovement(translation: translation) == false)
            }

            @Test("Negative horizontal movement is recognized")
            func negativeHorizontal() {
                // -30pt horizontal (backward direction)
                let translation = CGSize(width: -30, height: 0)
                #expect(SeekGestureCalculator.isHorizontalMovement(translation: translation) == true)
            }

            @Test("Diagonal within 30 degrees is recognized")
            func diagonalWithinAngle() {
                // tan(30°) ≈ 0.577, so for 50pt horizontal, max vertical ≈ 28.9pt
                let translation = CGSize(width: 50, height: 25)
                #expect(SeekGestureCalculator.isHorizontalMovement(translation: translation) == true)
            }

            @Test("Diagonal beyond 30 degrees is not recognized")
            func diagonalBeyondAngle() {
                // 45 degree angle - beyond 30 degree limit
                let translation = CGSize(width: 30, height: 30)
                #expect(SeekGestureCalculator.isHorizontalMovement(translation: translation) == false)
            }

            @Test("Vertical movement is not recognized")
            func verticalMovement() {
                // Purely vertical
                let translation = CGSize(width: 5, height: 50)
                #expect(SeekGestureCalculator.isHorizontalMovement(translation: translation) == false)
            }

            @Test("Zero movement is not recognized")
            func zeroMovement() {
                let translation = CGSize(width: 0, height: 0)
                #expect(SeekGestureCalculator.isHorizontalMovement(translation: translation) == false)
            }
        }

        // MARK: - Duration Multiplier

        @Suite("calculateDurationMultiplier")
        struct DurationMultiplierTests {

            @Test("5 minute video gives minimum multiplier")
            func fiveMinuteVideo() {
                let multiplier = SeekGestureCalculator.calculateDurationMultiplier(videoDuration: 300)
                #expect(multiplier == 0.5)
            }

            @Test("10 minute video gives 1.0 multiplier")
            func tenMinuteVideo() {
                let multiplier = SeekGestureCalculator.calculateDurationMultiplier(videoDuration: 600)
                #expect(multiplier == 1.0)
            }

            @Test("20 minute video gives 2.0 multiplier")
            func twentyMinuteVideo() {
                let multiplier = SeekGestureCalculator.calculateDurationMultiplier(videoDuration: 1200)
                #expect(multiplier == 2.0)
            }

            @Test("30 minute video gives maximum multiplier")
            func thirtyMinuteVideo() {
                let multiplier = SeekGestureCalculator.calculateDurationMultiplier(videoDuration: 1800)
                #expect(multiplier == 3.0)
            }

            @Test("60 minute video is capped at maximum")
            func sixtyMinuteVideo() {
                let multiplier = SeekGestureCalculator.calculateDurationMultiplier(videoDuration: 3600)
                #expect(multiplier == 3.0)
            }

            @Test("Very short video is capped at minimum")
            func veryShortVideo() {
                let multiplier = SeekGestureCalculator.calculateDurationMultiplier(videoDuration: 60)
                #expect(multiplier == 0.5)
            }

            @Test("Zero duration returns default")
            func zeroDuration() {
                let multiplier = SeekGestureCalculator.calculateDurationMultiplier(videoDuration: 0)
                #expect(multiplier == 1.0)
            }
        }

        // MARK: - Seek Delta Calculation

        @Suite("calculateSeekDelta")
        struct SeekDeltaTests {

            @Test("Full screen swipe with medium sensitivity on 10 min video")
            func fullSwipeMedium() {
                // 10 min video, medium sensitivity, full screen swipe
                // Expected: 60s * 1.0 = 60s
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 400,
                    screenWidth: 400,
                    videoDuration: 600,
                    sensitivity: .medium
                )
                #expect(delta == 60)
            }

            @Test("Half screen swipe")
            func halfScreenSwipe() {
                // Half screen swipe should give half the seek delta
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 200,
                    screenWidth: 400,
                    videoDuration: 600,
                    sensitivity: .medium
                )
                #expect(delta == 30)
            }

            @Test("Negative swipe for backward seek")
            func negativeSwipe() {
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: -200,
                    screenWidth: 400,
                    videoDuration: 600,
                    sensitivity: .medium
                )
                #expect(delta == -30)
            }

            @Test("Low sensitivity gives smaller seek")
            func lowSensitivity() {
                // Low = 30s base, vs medium = 60s
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 400,
                    screenWidth: 400,
                    videoDuration: 600,
                    sensitivity: .low
                )
                #expect(delta == 30)
            }

            @Test("High sensitivity gives larger seek")
            func highSensitivity() {
                // High = 120s base, vs medium = 60s
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 400,
                    screenWidth: 400,
                    videoDuration: 600,
                    sensitivity: .high
                )
                #expect(delta == 120)
            }

            @Test("Short video reduces seek amount")
            func shortVideoMultiplier() {
                // 5 min video has 0.5x multiplier
                // Expected: 60s * 0.5 = 30s for full swipe
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 400,
                    screenWidth: 400,
                    videoDuration: 300,
                    sensitivity: .medium
                )
                #expect(delta == 30)
            }

            @Test("Long video increases seek amount")
            func longVideoMultiplier() {
                // 30 min video has 3.0x multiplier
                // Expected: 60s * 3.0 = 180s for full swipe
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 400,
                    screenWidth: 400,
                    videoDuration: 1800,
                    sensitivity: .medium
                )
                #expect(delta == 180)
            }

            @Test("Small drag below minimum threshold returns nil")
            func belowMinimumThreshold() {
                // Very small drag that would result in < 5s seek
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 10,
                    screenWidth: 400,
                    videoDuration: 600,
                    sensitivity: .medium
                )
                #expect(delta == nil)
            }

            @Test("Drag at exactly minimum threshold returns value")
            func atMinimumThreshold() {
                // Calculate drag distance needed for exactly 5s
                // 5s = (drag/400) * 60 * 1.0 → drag = 400 * 5 / 60 ≈ 33.3pt
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 34,
                    screenWidth: 400,
                    videoDuration: 600,
                    sensitivity: .medium
                )
                #expect(delta != nil)
                if let delta {
                    #expect(delta >= 5.0)
                }
            }

            @Test("Zero screen width returns nil")
            func zeroScreenWidth() {
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 100,
                    screenWidth: 0,
                    videoDuration: 600,
                    sensitivity: .medium
                )
                #expect(delta == nil)
            }

            @Test("Zero duration returns nil")
            func zeroDuration() {
                let delta = SeekGestureCalculator.calculateSeekDelta(
                    dragDistance: 100,
                    screenWidth: 400,
                    videoDuration: 0,
                    sensitivity: .medium
                )
                #expect(delta == nil)
            }
        }

        // MARK: - Boundary Clamping

        @Suite("clampSeekTime")
        struct ClampSeekTimeTests {

            @Test("Normal forward seek within bounds")
            func normalForwardSeek() {
                let result = SeekGestureCalculator.clampSeekTime(
                    currentTime: 100,
                    seekDelta: 50,
                    duration: 600
                )
                #expect(result.seekTime == 150)
                #expect(result.hitBoundary == false)
            }

            @Test("Normal backward seek within bounds")
            func normalBackwardSeek() {
                let result = SeekGestureCalculator.clampSeekTime(
                    currentTime: 100,
                    seekDelta: -50,
                    duration: 600
                )
                #expect(result.seekTime == 50)
                #expect(result.hitBoundary == false)
            }

            @Test("Forward seek past end is clamped")
            func forwardPastEnd() {
                let result = SeekGestureCalculator.clampSeekTime(
                    currentTime: 550,
                    seekDelta: 100,
                    duration: 600
                )
                #expect(result.seekTime == 600)
                #expect(result.hitBoundary == true)
            }

            @Test("Backward seek past start is clamped")
            func backwardPastStart() {
                let result = SeekGestureCalculator.clampSeekTime(
                    currentTime: 30,
                    seekDelta: -50,
                    duration: 600
                )
                #expect(result.seekTime == 0)
                #expect(result.hitBoundary == true)
            }

            @Test("Exactly at boundary does not report hit")
            func exactlyAtBoundary() {
                // Seek to exactly the end
                let result = SeekGestureCalculator.clampSeekTime(
                    currentTime: 500,
                    seekDelta: 100,
                    duration: 600
                )
                #expect(result.seekTime == 600)
                #expect(result.hitBoundary == false)
            }

            @Test("Zero duration clamps to zero")
            func zeroDuration() {
                let result = SeekGestureCalculator.clampSeekTime(
                    currentTime: 0,
                    seekDelta: 100,
                    duration: 0
                )
                #expect(result.seekTime == 0)
                #expect(result.hitBoundary == true)
            }
        }
    }

    // MARK: - GesturesSettings Integration

    @Suite("GesturesSettings Integration")
    struct GesturesSettingsIntegrationTests {

        @Test("hasActiveGestures includes seek gesture")
        func hasActiveGesturesIncludesSeek() {
            // Only seek enabled
            let seekOnly = GesturesSettings(
                tapGestures: TapGesturesSettings(isEnabled: false),
                seekGesture: SeekGestureSettings(isEnabled: true),
                panscanGesture: PanscanGestureSettings(isEnabled: false)
            )
            #expect(seekOnly.hasActiveGestures == true)
            #expect(seekOnly.isSeekGestureActive == true)
            #expect(seekOnly.areTapGesturesActive == false)

            // Only tap enabled
            let tapOnly = GesturesSettings(
                tapGestures: TapGesturesSettings(isEnabled: true),
                seekGesture: SeekGestureSettings(isEnabled: false),
                panscanGesture: PanscanGestureSettings(isEnabled: false)
            )
            #expect(tapOnly.hasActiveGestures == true)
            #expect(tapOnly.isSeekGestureActive == false)
            #expect(tapOnly.areTapGesturesActive == true)

            // Both enabled
            let both = GesturesSettings(
                tapGestures: TapGesturesSettings(isEnabled: true),
                seekGesture: SeekGestureSettings(isEnabled: true),
                panscanGesture: PanscanGestureSettings(isEnabled: false)
            )
            #expect(both.hasActiveGestures == true)

            // Neither enabled (all disabled including panscan)
            let neither = GesturesSettings(
                tapGestures: TapGesturesSettings(isEnabled: false),
                seekGesture: SeekGestureSettings(isEnabled: false),
                panscanGesture: PanscanGestureSettings(isEnabled: false)
            )
            #expect(neither.hasActiveGestures == false)
        }

        @Test("GesturesSettings serialization with seek gesture")
        func serializationWithSeekGesture() throws {
            let original = GesturesSettings(
                tapGestures: TapGesturesSettings(isEnabled: true, layout: .quadrants),
                seekGesture: SeekGestureSettings(isEnabled: true, sensitivity: .high)
            )

            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(GesturesSettings.self, from: encoded)

            #expect(decoded.tapGestures.isEnabled == original.tapGestures.isEnabled)
            #expect(decoded.tapGestures.layout == original.tapGestures.layout)
            #expect(decoded.seekGesture.isEnabled == original.seekGesture.isEnabled)
            #expect(decoded.seekGesture.sensitivity == original.seekGesture.sensitivity)
        }
    }
}
