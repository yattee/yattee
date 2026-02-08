//
//  MiniPlayerEditorView.swift
//  Yattee
//
//  Settings editor for mini player behavior.
//

import SwiftUI

struct MiniPlayerEditorView: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var showVideo: Bool = true
    @State private var videoTapAction: MiniPlayerVideoTapAction = .startPiP

    var body: some View {
        List {
            MiniPlayerPreviewView(
                buttons: viewModel.miniPlayerButtons,
                showVideo: showVideo
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            videoSection
            buttonsSection
            addButtonSection
        }
        .navigationTitle(String(localized: "settings.playerControls.miniPlayer"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            syncLocalState()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            syncLocalState()
        }
    }

    // MARK: - Video Section

    private var videoSection: some View {
        Section {
            Toggle(
                String(localized: "settings.behavior.miniPlayer.showVideo"),
                isOn: $showVideo
            )
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: showVideo) { _, newValue in
                guard newValue != viewModel.miniPlayerShowVideo else { return }
                viewModel.syncMiniPlayerShowVideo(newValue)
            }

            if showVideo {
                Picker(
                    String(localized: "settings.behavior.miniPlayer.videoTapAction"),
                    selection: $videoTapAction
                ) {
                    ForEach(MiniPlayerVideoTapAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .disabled(!viewModel.canEditActivePreset)
                .onChange(of: videoTapAction) { _, newValue in
                    guard newValue != viewModel.miniPlayerVideoTapAction else { return }
                    viewModel.syncMiniPlayerVideoTapAction(newValue)
                }
            }
        } header: {
            Text(String(localized: "settings.behavior.miniPlayer.video.header"))
        } footer: {
            Text(String(localized: "settings.behavior.miniPlayer.showVideo.footer"))
        }
    }

    // MARK: - Buttons Section

    private var buttonsSection: some View {
        Section {
            if viewModel.miniPlayerButtons.isEmpty {
                Text(String(localized: "miniPlayer.buttons.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.miniPlayerButtons.enumerated()), id: \.element.id) { _, config in
                    buttonRow(for: config)
                }
                .onMove { source, destination in
                    viewModel.moveMiniPlayerButtons(fromOffsets: source, toOffset: destination)
                }
                .onDelete { indexSet in
                    indexSet.forEach { viewModel.removeMiniPlayerButton(at: $0) }
                }
            }
        } header: {
            Text(String(localized: "miniPlayer.buttons.header"))
        } footer: {
            Text(String(localized: "miniPlayer.buttons.footer"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    @ViewBuilder
    private func buttonRow(for config: ControlButtonConfiguration) -> some View {
        if config.buttonType.hasSettings {
            NavigationLink {
                MiniPlayerButtonConfigurationView(
                    buttonID: config.id,
                    viewModel: viewModel
                )
            } label: {
                buttonRowContent(for: config)
            }
        } else {
            buttonRowContent(for: config)
        }
    }

    @ViewBuilder
    private func buttonRowContent(for config: ControlButtonConfiguration) -> some View {
        HStack {
            Image(systemName: buttonIcon(for: config))
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(config.buttonType.displayName)

            // Show configuration summary for configurable buttons
            if let summary = configurationSummary(for: config) {
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    /// Returns the appropriate icon for a button, using configuration-specific icons when available.
    private func buttonIcon(for config: ControlButtonConfiguration) -> String {
        if config.buttonType == .seek, let seekSettings = config.seekSettings {
            return seekSettings.systemImage
        }
        return config.buttonType.systemImage
    }

    /// Returns a summary string for buttons with configurable settings.
    private func configurationSummary(for config: ControlButtonConfiguration) -> String? {
        if config.buttonType == .seek, let seekSettings = config.seekSettings {
            return "\(seekSettings.seconds)s \(seekSettings.direction.displayName)"
        }
        return nil
    }

    // MARK: - Add Button Section

    private var addButtonSection: some View {
        Section {
            ForEach(availableButtons, id: \.self) { buttonType in
                Button {
                    viewModel.addMiniPlayerButton(buttonType)
                } label: {
                    HStack {
                        Image(systemName: buttonType.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        Text(buttonType.displayName)
                            .foregroundStyle(.primary)
                    }
                }
            }
        } header: {
            Text(String(localized: "miniPlayer.addButton.header"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    // MARK: - Helpers

    /// Button types available to add (not already in the mini player).
    /// Seek buttons can be added multiple times (like spacers), others are unique.
    private var availableButtons: [ControlButtonType] {
        let usedTypes = Set(viewModel.miniPlayerButtons.map(\.buttonType))
        return ControlButtonType.availableForMiniPlayer.filter { buttonType in
            // Seek can be added multiple times (e.g., backward + forward)
            buttonType == .seek || !usedTypes.contains(buttonType)
        }
    }

    private func syncLocalState() {
        showVideo = viewModel.miniPlayerShowVideo
        videoTapAction = viewModel.miniPlayerVideoTapAction
    }
}

// MARK: - Mini Player Preview

private struct MiniPlayerPreviewView: View {
    let buttons: [ControlButtonConfiguration]
    let showVideo: Bool

    private let buttonSize: CGFloat = 28
    private let buttonSpacing: CGFloat = 4

    var body: some View {
        HStack(spacing: 12) {
            // Video thumbnail placeholder (always shown - matches actual mini player behavior)
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 60, height: 34)
                .overlay {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }

            // Title/channel placeholders
            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 100, height: 12)

                RoundedRectangle(cornerRadius: 2)
                    .fill(.tertiary.opacity(0.5))
                    .frame(width: 70, height: 10)
            }

            Spacer()

            // Buttons
            HStack(spacing: buttonSpacing) {
                ForEach(buttons) { config in
                    CompactPreviewButtonView(configuration: config, size: buttonSize)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(
            Image("PlayerControlsPreviewBackground")
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

// MARK: - Mini Player Button Configuration View

/// View for configuring a single mini player button's settings.
struct MiniPlayerButtonConfigurationView: View {
    let buttonID: UUID
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var seekSeconds: Double = 10
    @State private var seekDirection: SeekDirection = .forward

    /// Look up the current configuration from the view model's mini player settings.
    private var configuration: ControlButtonConfiguration? {
        viewModel.miniPlayerButtons.first { $0.id == buttonID }
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
        viewModel.updateMiniPlayerButtonConfiguration(updated)
    }
}
