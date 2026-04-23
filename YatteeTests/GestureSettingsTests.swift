//
//  GestureSettingsTests.swift
//  YatteeTests
//
//  Tests for player gesture settings models.
//

import Foundation
import Testing
@testable import Yattee

@Suite("Gesture Settings Tests")
struct GestureSettingsTests {

    // MARK: - TapZoneLayout Tests

    @Suite("TapZoneLayout")
    struct TapZoneLayoutTests {

        @Test("Zone count matches layout")
        func zoneCountMatchesLayout() {
            #expect(TapZoneLayout.single.zoneCount == 1)
            #expect(TapZoneLayout.horizontalSplit.zoneCount == 2)
            #expect(TapZoneLayout.verticalSplit.zoneCount == 2)
            #expect(TapZoneLayout.threeColumns.zoneCount == 3)
            #expect(TapZoneLayout.quadrants.zoneCount == 4)
        }

        @Test("Positions match zone count")
        func positionsMatchZoneCount() {
            for layout in TapZoneLayout.allCases {
                #expect(layout.positions.count == layout.zoneCount)
            }
        }

        @Test("Layout is codable")
        func layoutIsCodable() throws {
            let original = TapZoneLayout.quadrants
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(TapZoneLayout.self, from: encoded)
            #expect(decoded == original)
        }
    }

    // MARK: - TapGestureAction Tests

    @Suite("TapGestureAction")
    struct TapGestureActionTests {

        @Test("Seek action has correct seconds")
        func seekActionHasCorrectSeconds() {
            let forward = TapGestureAction.seekForward(seconds: 15)
            let backward = TapGestureAction.seekBackward(seconds: 30)

            #expect(forward.seekSeconds == 15)
            #expect(backward.seekSeconds == 30)
            #expect(TapGestureAction.togglePlayPause.seekSeconds == nil)
        }

        @Test("Action type conversion preserves seconds")
        func actionTypeConversionPreservesSeconds() {
            let actionType = TapGestureActionType.seekForward
            let action = actionType.toAction(seconds: 25)

            if case .seekForward(let seconds) = action {
                #expect(seconds == 25)
            } else {
                Issue.record("Expected seekForward action")
            }
        }

        @Test("All action types have display names")
        func allActionTypesHaveDisplayNames() {
            for actionType in TapGestureActionType.allCases {
                #expect(!actionType.displayName.isEmpty)
                #expect(!actionType.systemImage.isEmpty)
            }
        }

        @Test("Action is codable with associated values")
        func actionIsCodableWithAssociatedValues() throws {
            let actions: [TapGestureAction] = [
                .togglePlayPause,
                .seekForward(seconds: 10),
                .seekBackward(seconds: 30),
                .toggleFullscreen
            ]

            for original in actions {
                let encoded = try JSONEncoder().encode(original)
                let decoded = try JSONDecoder().decode(TapGestureAction.self, from: encoded)
                #expect(decoded == original)
            }
        }
    }

    // MARK: - TapGesturesSettings Tests

    @Suite("TapGesturesSettings")
    struct TapGesturesSettingsTests {

        @Test("Default settings are disabled")
        func defaultSettingsAreDisabled() {
            let settings = TapGesturesSettings.default
            #expect(settings.isEnabled == false)
        }

        @Test("Default layout is horizontal split")
        func defaultLayoutIsHorizontalSplit() {
            let settings = TapGesturesSettings.default
            #expect(settings.layout == .horizontalSplit)
        }

        @Test("Default configurations match layout positions")
        func defaultConfigurationsMatchLayoutPositions() {
            for layout in TapZoneLayout.allCases {
                let configs = TapGesturesSettings.defaultConfigurations(for: layout)
                #expect(configs.count == layout.zoneCount)

                let configPositions = Set(configs.map(\.position))
                let layoutPositions = Set(layout.positions)
                #expect(configPositions == layoutPositions)
            }
        }

        @Test("Double tap interval has valid range")
        func doubleTapIntervalHasValidRange() {
            let range = TapGesturesSettings.doubleTapIntervalRange
            #expect(range.lowerBound == 150)
            #expect(range.upperBound == 600)
        }

        @Test("With layout creates new configurations")
        func withLayoutCreatesNewConfigurations() {
            var settings = TapGesturesSettings(layout: .single)
            #expect(settings.zoneConfigurations.count == 1)

            settings = settings.withLayout(.quadrants)
            #expect(settings.layout == .quadrants)
            #expect(settings.zoneConfigurations.count == 4)
        }
    }

    // MARK: - GesturesSettings Tests

    @Suite("GesturesSettings")
    struct GesturesSettingsTests {

        @Test("Default settings have panscan gesture enabled")
        func defaultSettingsHavePanscanEnabled() {
            let settings = GesturesSettings.default
            // Panscan is enabled by default
            #expect(settings.hasActiveGestures == true)
            #expect(settings.isPanscanGestureActive == true)
            #expect(settings.areTapGesturesActive == false)
            #expect(settings.isSeekGestureActive == false)
        }

        @Test("Has active gestures when tap gestures enabled")
        func hasActiveGesturesWhenTapEnabled() {
            // All gestures disabled
            let disabled = GesturesSettings(
                tapGestures: TapGesturesSettings(isEnabled: false),
                seekGesture: SeekGestureSettings(isEnabled: false),
                panscanGesture: PanscanGestureSettings(isEnabled: false)
            )
            #expect(disabled.hasActiveGestures == false)
            #expect(disabled.areTapGesturesActive == false)

            // Tap enabled
            let enabled = GesturesSettings(
                tapGestures: TapGesturesSettings(isEnabled: true),
                seekGesture: SeekGestureSettings(isEnabled: false),
                panscanGesture: PanscanGestureSettings(isEnabled: false)
            )
            #expect(enabled.hasActiveGestures == true)
            #expect(enabled.areTapGesturesActive == true)
        }
    }

    // MARK: - Serialization Tests

    @Suite("Serialization")
    struct SerializationTests {

        @Test("GesturesSettings round-trips through JSON")
        func gesturesSettingsRoundTrips() throws {
            let original = GesturesSettings(
                tapGestures: TapGesturesSettings(
                    isEnabled: true,
                    layout: .quadrants,
                    doubleTapInterval: 250
                )
            )

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(GesturesSettings.self, from: encoded)

            #expect(decoded.tapGestures.isEnabled == original.tapGestures.isEnabled)
            #expect(decoded.tapGestures.layout == original.tapGestures.layout)
            #expect(decoded.tapGestures.doubleTapInterval == original.tapGestures.doubleTapInterval)
        }
    }
}
