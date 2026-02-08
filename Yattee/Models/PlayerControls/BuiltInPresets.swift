//
//  BuiltInPresets.swift
//  Yattee
//
//  Factory methods for built-in layout presets.
//

import Foundation

extension LayoutPreset {
    /// Bump this version whenever any built-in preset definition changes.
    /// On launch, the app compares this against the last-applied version
    /// and replaces stale built-in presets with fresh copies from code.
    static let builtInPresetsVersion = 3

    // MARK: - Built-in Preset IDs

    /// Stable UUIDs for built-in presets to ensure consistency across devices.
    private enum BuiltInID {
        static let defaultPreset = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        static let minimalPreset = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    }

    // MARK: - Built-in Presets

    /// Default preset with balanced controls for general use.
    static func defaultPreset(for deviceClass: DeviceClass = .current) -> LayoutPreset {
        // Top buttons: titleAuthor (wideOnly), spacer, orientationLock, close
        let topButtons: [ControlButtonConfiguration] = [
            ControlButtonConfiguration(
                buttonType: .titleAuthor,
                visibilityMode: .wideOnly
            ),
            .flexibleSpacer(),
            .defaultConfiguration(for: .orientationLock),
            .defaultConfiguration(for: .close)
        ]

        // Bottom buttons: time, queue (wideOnly), playNext (wideOnly), spacer, contextMenu (wideOnly), settings, PiP, fullscreen
        let bottomButtons: [ControlButtonConfiguration] = [
            ControlButtonConfiguration(
                buttonType: .timeDisplay,
                settings: .timeDisplay(TimeDisplaySettings(format: .currentAndTotal))
            ),
            ControlButtonConfiguration(
                buttonType: .queue,
                visibilityMode: .wideOnly
            ),
            ControlButtonConfiguration(
                buttonType: .playNext,
                visibilityMode: .wideOnly
            ),
            .flexibleSpacer(),
            ControlButtonConfiguration(
                buttonType: .contextMenu,
                visibilityMode: .wideOnly
            ),
            .defaultConfiguration(for: .settings),
            .defaultConfiguration(for: .pictureInPicture),
            .defaultConfiguration(for: .fullscreen)
        ]

        // Center: all enabled, 10s seek, left=volume, right=brightness
        let centerSettings = CenterSectionSettings(
            showPlayPause: true,
            showSeekBackward: true,
            showSeekForward: true,
            seekBackwardSeconds: 10,
            seekForwardSeconds: 10,
            leftSlider: .volume,
            rightSlider: .brightness
        )

        // Global: plain style, medium buttons, system font
        let globalSettings = GlobalLayoutSettings(
            style: .plain,
            buttonSize: .medium,
            fontStyle: .system,
            systemControlsMode: .seek,
            systemControlsSeekDuration: .tenSeconds,
            volumeMode: .mpv
        )

        // Gestures: tap 2x1 with seek, seek enabled, panscan with snap
        let gesturesSettings = GesturesSettings(
            tapGestures: TapGesturesSettings(
                isEnabled: true,
                layout: .horizontalSplit,
                zoneConfigurations: [
                    TapZoneConfiguration(position: .left, action: .seekBackward(seconds: 10)),
                    TapZoneConfiguration(position: .right, action: .seekForward(seconds: 10))
                ]
            ),
            seekGesture: SeekGestureSettings(isEnabled: false),
            panscanGesture: PanscanGestureSettings(isEnabled: true, snapToEnds: true)
        )

        // Player pill: queue, previous, play/pause, next, close
        let playerPillSettings = PlayerPillSettings(
            visibility: .portraitOnly,
            buttons: [
                ControlButtonConfiguration(buttonType: .queue),
                ControlButtonConfiguration(buttonType: .playPrevious),
                ControlButtonConfiguration(buttonType: .playPause),
                ControlButtonConfiguration(buttonType: .playNext),
                ControlButtonConfiguration(buttonType: .close)
            ]
        )

        // Mini player: show video, tap for PiP
        let miniPlayerSettings = MiniPlayerSettings()

        let layout = PlayerControlsLayout(
            topSection: LayoutSection(buttons: topButtons),
            centerSettings: centerSettings,
            bottomSection: LayoutSection(buttons: bottomButtons),
            globalSettings: globalSettings,
            progressBarSettings: ProgressBarSettings(),
            gesturesSettings: gesturesSettings,
            playerPillSettings: playerPillSettings,
            miniPlayerSettings: miniPlayerSettings
        )

        return LayoutPreset(
            id: BuiltInID.defaultPreset,
            name: String(localized: "controls.preset.default"),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            isBuiltIn: true,
            deviceClass: deviceClass,
            layout: layout
        )
    }

    /// Minimal preset with stripped-down controls for distraction-free playback.
    static func minimalPreset(for deviceClass: DeviceClass = .current) -> LayoutPreset {
        let topButtons: [ControlButtonConfiguration] = [
            .flexibleSpacer(),
            .defaultConfiguration(for: .close)
        ]

        let bottomButtons: [ControlButtonConfiguration] = [
            ControlButtonConfiguration(
                buttonType: .timeDisplay,
                settings: .timeDisplay(TimeDisplaySettings(format: .currentAndTotal))
            ),
            .flexibleSpacer(),
            .defaultConfiguration(for: .settings),
            .defaultConfiguration(for: .pictureInPicture),
            .defaultConfiguration(for: .fullscreen)
        ]

        let centerSettings = CenterSectionSettings(
            showPlayPause: true,
            showSeekBackward: true,
            showSeekForward: true,
            seekBackwardSeconds: 10,
            seekForwardSeconds: 10,
            leftSlider: .disabled,
            rightSlider: .disabled
        )

        let globalSettings = GlobalLayoutSettings(
            style: .plain,
            buttonSize: .medium,
            fontStyle: .system,
            systemControlsMode: .seek,
            systemControlsSeekDuration: .tenSeconds,
            volumeMode: .mpv
        )

        let gesturesSettings = GesturesSettings(
            tapGestures: TapGesturesSettings(
                isEnabled: true,
                layout: .horizontalSplit,
                zoneConfigurations: [
                    TapZoneConfiguration(position: .left, action: .seekBackward(seconds: 10)),
                    TapZoneConfiguration(position: .right, action: .seekForward(seconds: 10))
                ]
            ),
            seekGesture: SeekGestureSettings(isEnabled: false),
            panscanGesture: PanscanGestureSettings(isEnabled: true, snapToEnds: true)
        )

        let playerPillSettings = PlayerPillSettings(
            visibility: .never,
            buttons: [
                ControlButtonConfiguration(buttonType: .queue),
                ControlButtonConfiguration(buttonType: .playPrevious),
                ControlButtonConfiguration(buttonType: .playPause),
                ControlButtonConfiguration(buttonType: .playNext),
                ControlButtonConfiguration(buttonType: .close)
            ]
        )

        let miniPlayerSettings = MiniPlayerSettings()

        let progressBarSettings = ProgressBarSettings(
            showChapters: false,
            sponsorBlockSettings: SponsorBlockSegmentSettings(showSegments: false)
        )

        let layout = PlayerControlsLayout(
            topSection: LayoutSection(buttons: topButtons),
            centerSettings: centerSettings,
            bottomSection: LayoutSection(buttons: bottomButtons),
            globalSettings: globalSettings,
            progressBarSettings: progressBarSettings,
            gesturesSettings: gesturesSettings,
            playerPillSettings: playerPillSettings,
            miniPlayerSettings: miniPlayerSettings
        )

        return LayoutPreset(
            id: BuiltInID.minimalPreset,
            name: String(localized: "controls.preset.minimal"),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            isBuiltIn: true,
            deviceClass: deviceClass,
            layout: layout
        )
    }

    /// All built-in presets for the given device class.
    static func allBuiltIn(for deviceClass: DeviceClass = .current) -> [LayoutPreset] {
        [defaultPreset(for: deviceClass), minimalPreset(for: deviceClass)]
    }
}
