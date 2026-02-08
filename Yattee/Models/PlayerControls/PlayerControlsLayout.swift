//
//  PlayerControlsLayout.swift
//  Yattee
//
//  Complete layout configuration for player controls.
//

import Foundation

/// Complete layout configuration for player controls, including all sections.
struct PlayerControlsLayout: Codable, Hashable, Sendable {
    /// Configuration for the top row of buttons.
    var topSection: LayoutSection

    /// Configuration for the center section (play/pause, seek).
    var centerSettings: CenterSectionSettings

    /// Configuration for the bottom row of buttons.
    var bottomSection: LayoutSection

    /// Global settings applied to all buttons.
    var globalSettings: GlobalLayoutSettings

    /// Progress bar appearance settings.
    var progressBarSettings: ProgressBarSettings

    /// Gesture settings (iOS only). Optional for backward compatibility.
    var gesturesSettings: GesturesSettings?

    /// Player pill settings. Optional for backward compatibility.
    var playerPillSettings: PlayerPillSettings?

    /// Mini player settings. Optional for backward compatibility.
    var miniPlayerSettings: MiniPlayerSettings?

    /// Wide layout panel alignment. Optional for backward compatibility.
    /// When nil, uses the global setting from SettingsManager.
    var wideLayoutPanelAlignment: FloatingPanelSide?


    // MARK: - Initialization

    /// Creates a complete player controls layout.
    /// - Parameters:
    ///   - topSection: Top section configuration.
    ///   - centerSettings: Center section settings.
    ///   - bottomSection: Bottom section configuration.
    ///   - globalSettings: Global settings.
    ///   - progressBarSettings: Progress bar appearance settings.
    ///   - gesturesSettings: Gesture settings (iOS only).
    ///   - playerPillSettings: Player pill settings.
    ///   - miniPlayerSettings: Mini player settings.
    init(
        topSection: LayoutSection = LayoutSection(),
        centerSettings: CenterSectionSettings = .default,
        bottomSection: LayoutSection = LayoutSection(),
        globalSettings: GlobalLayoutSettings = .default,
        progressBarSettings: ProgressBarSettings = .default,
        gesturesSettings: GesturesSettings? = nil,
        playerPillSettings: PlayerPillSettings? = nil,
        miniPlayerSettings: MiniPlayerSettings? = nil
    ) {
        self.topSection = topSection
        self.centerSettings = centerSettings
        self.bottomSection = bottomSection
        self.globalSettings = globalSettings
        self.progressBarSettings = progressBarSettings
        self.gesturesSettings = gesturesSettings
        self.playerPillSettings = playerPillSettings
        self.miniPlayerSettings = miniPlayerSettings
    }

    // MARK: - Gesture Settings

    /// Returns the effective gestures settings, using defaults if not set.
    var effectiveGesturesSettings: GesturesSettings {
        gesturesSettings ?? .default
    }

    // MARK: - Player Pill Settings

    /// Returns the effective player pill settings, using defaults if not set.
    var effectivePlayerPillSettings: PlayerPillSettings {
        playerPillSettings ?? .default
    }

    // MARK: - Mini Player Settings

    /// Returns the effective mini player settings, using defaults if not set.
    var effectiveMiniPlayerSettings: MiniPlayerSettings {
        miniPlayerSettings ?? .default
    }

    // MARK: - Wide Layout Panel Settings

    /// Returns the effective wide layout panel alignment, using right as default if not set.
    var effectiveWideLayoutPanelAlignment: FloatingPanelSide {
        wideLayoutPanelAlignment ?? .left
    }

    // MARK: - Defaults

    /// Default layout matching the current hardcoded player controls.
    static let `default`: PlayerControlsLayout = {
        // Top section: spacer, brightness (widescreen), volume, airplay, debug, close
        let topButtons: [ControlButtonConfiguration] = [
            .flexibleSpacer(),
            ControlButtonConfiguration(
                buttonType: .brightness,
                visibilityMode: .wideOnly,
                settings: .slider(SliderSettings(sliderBehavior: .alwaysVisible))
            ),
            ControlButtonConfiguration(
                buttonType: .volume,
                settings: .slider(SliderSettings(sliderBehavior: .alwaysVisible))
            ),
            .defaultConfiguration(for: .airplay),
            .defaultConfiguration(for: .mpvDebug),
            .defaultConfiguration(for: .close)
        ]

        // Bottom section: time, queue (widescreen), playNext, spacer, orientationLock (widescreen), contextMenu (widescreen), settings, pip, panelToggle (widescreen), fullscreen
        let bottomButtons: [ControlButtonConfiguration] = [
            ControlButtonConfiguration(
                buttonType: .timeDisplay,
                settings: .timeDisplay(TimeDisplaySettings(format: .currentAndTotal))
            ),
            ControlButtonConfiguration(
                buttonType: .queue,
                visibilityMode: .wideOnly
            ),
            .defaultConfiguration(for: .playNext),
            .flexibleSpacer(),
            ControlButtonConfiguration(
                buttonType: .orientationLock,
                visibilityMode: .wideOnly
            ),
            ControlButtonConfiguration(
                buttonType: .contextMenu,
                visibilityMode: .wideOnly
            ),
            .defaultConfiguration(for: .settings),
            .defaultConfiguration(for: .pictureInPicture),
            ControlButtonConfiguration(
                buttonType: .panelToggle,
                visibilityMode: .wideOnly
            ),
            .defaultConfiguration(for: .fullscreen)
        ]

        return PlayerControlsLayout(
            topSection: LayoutSection(buttons: topButtons),
            centerSettings: CenterSectionSettings(),
            bottomSection: LayoutSection(buttons: bottomButtons),
            globalSettings: GlobalLayoutSettings(),
            progressBarSettings: ProgressBarSettings()
        )
    }()

    // MARK: - Helpers

    /// Returns all button types currently used in top and bottom sections.
    var usedButtonTypes: Set<ControlButtonType> {
        let topTypes = topSection.buttons.map(\.buttonType)
        let bottomTypes = bottomSection.buttons.map(\.buttonType)
        return Set(topTypes + bottomTypes)
    }

    /// Returns button types available to add (not already used, excluding spacer which can be duplicated).
    var availableButtonTypes: [ControlButtonType] {
        let used = usedButtonTypes
        return ControlButtonType.availableForHorizontalSections.filter { type in
            type == .spacer || !used.contains(type)
        }
    }
}
