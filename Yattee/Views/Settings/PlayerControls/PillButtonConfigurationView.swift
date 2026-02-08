//
//  PillButtonConfigurationView.swift
//  Yattee
//
//  View for configuring individual button settings in the player pill.
//

import SwiftUI

/// View for configuring a single pill button's settings.
struct PillButtonConfigurationView: View {
    let buttonID: UUID
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var seekSeconds: Double = 10
    @State private var seekDirection: SeekDirection = .forward

    /// Look up the current configuration from the view model's pill settings.
    private var configuration: ControlButtonConfiguration? {
        viewModel.pillButtons.first { $0.id == buttonID }
    }

    var body: some View {
        if let config = configuration {
            Form {
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
        }
    }

    // MARK: - Sync from Configuration

    private func syncFromConfiguration(_ config: ControlButtonConfiguration) {
        switch config.settings {
        case .seek(let settings):
            seekSeconds = Double(settings.seconds)
            seekDirection = settings.direction
        default:
            break
        }
    }

    // MARK: - Type-Specific Settings

    @ViewBuilder
    private func typeSpecificSettings(for config: ControlButtonConfiguration) -> some View {
        switch config.buttonType {
        case .seek:
            seekSettingsSection
        default:
            EmptyView()
        }
    }

    // MARK: - Seek Settings

    @ViewBuilder
    private var seekSettingsSection: some View {
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

    // MARK: - Update Helpers

    private func updateSettings(_ settings: ButtonSettings) {
        guard var updated = configuration else { return }
        updated.settings = settings
        viewModel.updatePillButtonConfiguration(updated)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PillButtonConfigurationView(
            buttonID: UUID(),
            viewModel: PlayerControlsSettingsViewModel(
                layoutService: PlayerControlsLayoutService(),
                settingsManager: SettingsManager()
            )
        )
    }
}
