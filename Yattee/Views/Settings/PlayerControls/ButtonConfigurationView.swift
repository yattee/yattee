//
//  ButtonConfigurationView.swift
//  Yattee
//
//  View for configuring individual button settings.
//

import SwiftUI

/// View for configuring a single button's settings.
struct ButtonConfigurationView: View {
    let buttonID: UUID
    let sectionType: LayoutSectionType
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var visibilityMode: VisibilityMode = .both
    @State private var spacerIsFlexible: Bool = true
    @State private var spacerWidth: Double = 20
    @State private var sliderBehavior: SliderBehavior = .expandOnTap
    @State private var seekSeconds: Double = 10
    @State private var seekDirection: SeekDirection = .forward
    @State private var timeDisplayFormat: TimeDisplayFormat = .currentAndTotal
    @State private var titleAuthorShowSourceImage: Bool = true
    @State private var titleAuthorShowTitle: Bool = true
    @State private var titleAuthorShowSourceName: Bool = true

    /// Look up the current configuration from the view model's layout.
    private var configuration: ControlButtonConfiguration? {
        let section = sectionType == .top
            ? viewModel.currentLayout.topSection
            : viewModel.currentLayout.bottomSection
        return section.buttons.first { $0.id == buttonID }
    }

    var body: some View {
        if let config = configuration {
            Form {
                // Visibility mode (all buttons)
                Section {
                    Picker(
                        String(localized: "settings.playerControls.visibility"),
                        selection: $visibilityMode
                    ) {
                        ForEach(VisibilityMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: visibilityMode) { _, newValue in
                        updateVisibility(newValue)
                    }
                } header: {
                    Text(String(localized: "settings.playerControls.visibilityHeader"))
                } footer: {
                    Text(String(localized: "settings.playerControls.visibilityFooter"))
                }

                // Type-specific settings
                if config.buttonType.hasSettings {
                    typeSpecificSettings(for: config)
                }
            }
            .navigationTitle(config.buttonType.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                syncFromConfiguration(config)
            }
        } else {
            ContentUnavailableView(
                String(localized: "settings.playerControls.buttonNotFound"),
                systemImage: "exclamationmark.triangle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sync from Configuration

    private func syncFromConfiguration(_ config: ControlButtonConfiguration) {
        visibilityMode = config.visibilityMode

        switch config.settings {
        case .spacer(let settings):
            spacerIsFlexible = settings.isFlexible
            spacerWidth = Double(settings.fixedWidth)
        case .slider(let settings):
            sliderBehavior = settings.sliderBehavior
        case .seek(let settings):
            seekSeconds = Double(settings.seconds)
            seekDirection = settings.direction
        case .timeDisplay(let settings):
            timeDisplayFormat = settings.format
        case .titleAuthor(let settings):
            titleAuthorShowSourceImage = settings.showSourceImage
            titleAuthorShowTitle = settings.showTitle
            titleAuthorShowSourceName = settings.showSourceName
        case .none:
            break
        }
    }

    // MARK: - Type-Specific Settings

    @ViewBuilder
    private func typeSpecificSettings(for config: ControlButtonConfiguration) -> some View {
        switch config.buttonType {
        case .spacer:
            spacerSettings
        case .brightness, .volume:
            sliderSettings
        case .seekBackward, .seekForward:
            seekSettings
        case .seek:
            seekSettingsForHorizontal
        case .timeDisplay:
            timeDisplaySettings
        case .titleAuthor:
            titleAuthorSettings
        default:
            EmptyView()
        }
    }

    // MARK: - Spacer Settings

    @ViewBuilder
    private var spacerSettings: some View {
        Section {
            Toggle(
                String(localized: "settings.playerControls.spacer.flexible"),
                isOn: $spacerIsFlexible
            )
            .onChange(of: spacerIsFlexible) { _, newValue in
                updateSpacerSettings(isFlexible: newValue, width: Int(spacerWidth))
            }

            #if !os(tvOS)
            if !spacerIsFlexible {
                HStack {
                    Text(String(localized: "settings.playerControls.spacer.width"))
                    Spacer()
                    Text("\(Int(spacerWidth))pt")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $spacerWidth,
                    in: 4...100,
                    step: 2
                )
                .onChange(of: spacerWidth) { _, newValue in
                    updateSpacerSettings(isFlexible: spacerIsFlexible, width: Int(newValue))
                }
            }
            #endif
        } header: {
            Text(String(localized: "settings.playerControls.spacer.header"))
        } footer: {
            Text(String(localized: "settings.playerControls.spacer.footer"))
        }
    }

    // MARK: - Slider Settings (Brightness/Volume)

    @ViewBuilder
    private var sliderSettings: some View {
        Section {
            Picker(
                String(localized: "settings.playerControls.slider.behavior"),
                selection: $sliderBehavior
            ) {
                ForEach(SliderBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }
            .onChange(of: sliderBehavior) { _, newValue in
                updateSliderSettings(behavior: newValue)
            }
        } header: {
            Text(String(localized: "settings.playerControls.slider.header"))
        } footer: {
            Text(String(localized: "settings.playerControls.slider.footer"))
        }
    }

    private func updateSliderSettings(behavior: SliderBehavior) {
        let settings = SliderSettings(sliderBehavior: behavior)
        updateSettings(.slider(settings))
    }

    // MARK: - Seek Settings

    @ViewBuilder
    private var seekSettings: some View {
        Section {
            #if !os(tvOS)
            HStack {
                Text(String(localized: "settings.playerControls.seek.seconds"))
                Spacer()
                Text("\(Int(seekSeconds))s")
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $seekSeconds,
                in: 1...60,
                step: 1
            )
            .onChange(of: seekSeconds) { _, newValue in
                updateSettings(.seek(SeekSettings(seconds: Int(newValue), direction: seekDirection)))
            }
            #endif

            // Quick presets
            HStack {
                ForEach([5, 10, 15, 30], id: \.self) { preset in
                    Button("\(preset)s") {
                        seekSeconds = Double(preset)
                    }
                    .buttonStyle(.bordered)
                    .tint(Int(seekSeconds) == preset ? .accentColor : .secondary)
                }
            }
        } header: {
            Text(String(localized: "settings.playerControls.seek.header"))
        }
    }

    // MARK: - Seek Settings for Horizontal Sections

    @ViewBuilder
    private var seekSettingsForHorizontal: some View {
        Section {
            // Direction picker
            Picker(
                String(localized: "settings.playerControls.seek.direction"),
                selection: $seekDirection
            ) {
                ForEach(SeekDirection.allCases, id: \.self) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }
            .onChange(of: seekDirection) { _, newValue in
                updateSettings(.seek(SeekSettings(seconds: Int(seekSeconds), direction: newValue)))
            }

            #if !os(tvOS)
            HStack {
                Text(String(localized: "settings.playerControls.seek.seconds"))
                Spacer()
                Text("\(Int(seekSeconds))s")
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $seekSeconds,
                in: 1...60,
                step: 1
            )
            .onChange(of: seekSeconds) { _, newValue in
                updateSettings(.seek(SeekSettings(seconds: Int(newValue), direction: seekDirection)))
            }
            #endif

            // Quick presets
            HStack {
                ForEach([5, 10, 15, 30], id: \.self) { preset in
                    Button("\(preset)s") {
                        seekSeconds = Double(preset)
                        updateSettings(.seek(SeekSettings(seconds: preset, direction: seekDirection)))
                    }
                    .buttonStyle(.bordered)
                    .tint(Int(seekSeconds) == preset ? .accentColor : .secondary)
                }
            }
        } header: {
            Text(String(localized: "settings.playerControls.seek.header"))
        }
    }

    // MARK: - Time Display Settings

    @ViewBuilder
    private var timeDisplaySettings: some View {
        Section {
            Picker(
                String(localized: "settings.playerControls.timeDisplay.format"),
                selection: $timeDisplayFormat
            ) {
                ForEach(TimeDisplayFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .onChange(of: timeDisplayFormat) { _, newValue in
                updateSettings(.timeDisplay(TimeDisplaySettings(format: newValue)))
            }
        } header: {
            Text(String(localized: "settings.playerControls.timeDisplay.header"))
        } footer: {
            Text(String(localized: "settings.playerControls.timeDisplay.footer"))
        }
    }

    // MARK: - Title/Author Settings

    @ViewBuilder
    private var titleAuthorSettings: some View {
        Section {
            Toggle(
                String(localized: "settings.playerControls.titleAuthor.showSourceImage"),
                isOn: $titleAuthorShowSourceImage
            )
            .onChange(of: titleAuthorShowSourceImage) { _, _ in
                updateTitleAuthorSettings()
            }

            Toggle(
                String(localized: "settings.playerControls.titleAuthor.showTitle"),
                isOn: $titleAuthorShowTitle
            )
            .onChange(of: titleAuthorShowTitle) { _, _ in
                updateTitleAuthorSettings()
            }

            Toggle(
                String(localized: "settings.playerControls.titleAuthor.showSourceName"),
                isOn: $titleAuthorShowSourceName
            )
            .onChange(of: titleAuthorShowSourceName) { _, _ in
                updateTitleAuthorSettings()
            }
        } header: {
            Text(String(localized: "settings.playerControls.titleAuthor.header"))
        } footer: {
            Text(String(localized: "settings.playerControls.titleAuthor.footer"))
        }
    }

    private func updateTitleAuthorSettings() {
        let settings = TitleAuthorSettings(
            showSourceImage: titleAuthorShowSourceImage,
            showTitle: titleAuthorShowTitle,
            showSourceName: titleAuthorShowSourceName
        )
        updateSettings(.titleAuthor(settings))
    }

    // MARK: - Update Helpers

    private func updateVisibility(_ mode: VisibilityMode) {
        guard var updated = configuration else { return }
        updated.visibilityMode = mode
        viewModel.updateButtonConfigurationSync(updated, in: sectionType)
    }

    private func updateSpacerSettings(isFlexible: Bool, width: Int) {
        let settings = SpacerSettings(isFlexible: isFlexible, fixedWidth: width)
        updateSettings(.spacer(settings))
    }

    private func updateSettings(_ settings: ButtonSettings) {
        guard var updated = configuration else { return }
        updated.settings = settings
        viewModel.updateButtonConfigurationSync(updated, in: sectionType)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ButtonConfigurationView(
            buttonID: UUID(),
            sectionType: .top,
            viewModel: PlayerControlsSettingsViewModel(
                layoutService: PlayerControlsLayoutService(),
                settingsManager: SettingsManager()
            )
        )
    }
}
