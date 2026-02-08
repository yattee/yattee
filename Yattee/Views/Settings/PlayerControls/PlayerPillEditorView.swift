//
//  PlayerPillEditorView.swift
//  Yattee
//
//  Settings editor for player pill visibility, collapse mode, and buttons.
//

import SwiftUI

struct PlayerPillEditorView: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var visibility: PillVisibility = .portraitOnly

    var body: some View {
        List {
            if !viewModel.pillButtons.isEmpty {
                PillPreviewView(buttons: viewModel.pillButtons)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            visibilitySection
            buttonsSection
            addButtonSection
        }
        .navigationTitle(String(localized: "settings.playerControls.playerPill"))
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

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        Section {
            Picker(
                String(localized: "pill.visibility.title"),
                selection: $visibility
            ) {
                ForEach(PillVisibility.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: visibility) { _, newValue in
                guard newValue != viewModel.pillVisibility else { return }
                viewModel.syncPillVisibility(newValue)
            }
        } header: {
            Text(String(localized: "pill.visibility.header"))
        } footer: {
            Text(String(localized: "pill.visibility.footer"))
        }
    }

    // MARK: - Buttons Section

    private var buttonsSection: some View {
        Section {
            if viewModel.pillButtons.isEmpty {
                Text(String(localized: "pill.buttons.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.pillButtons.enumerated()), id: \.element.id) { index, config in
                    buttonRow(for: config)
                }
                .onMove { source, destination in
                    viewModel.movePillButtons(fromOffsets: source, toOffset: destination)
                }
                .onDelete { indexSet in
                    indexSet.forEach { viewModel.removePillButton(at: $0) }
                }
            }
        } header: {
            Text(String(localized: "pill.buttons.header"))
        } footer: {
            Text(String(localized: "pill.buttons.footer"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    @ViewBuilder
    private func buttonRow(for config: ControlButtonConfiguration) -> some View {
        if config.buttonType.hasSettings {
            NavigationLink {
                PillButtonConfigurationView(
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
                    viewModel.addPillButton(buttonType)
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
            Text(String(localized: "pill.addButton.header"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    // MARK: - Helpers

    /// Button types available to add (not already in the pill).
    /// Seek buttons can be added multiple times (like spacers), others are unique.
    private var availableButtons: [ControlButtonType] {
        let usedTypes = Set(viewModel.pillButtons.map(\.buttonType))
        return ControlButtonType.availableForPill.filter { buttonType in
            // Seek can be added multiple times (e.g., backward + forward)
            buttonType == .seek || !usedTypes.contains(buttonType)
        }
    }

    private func syncLocalState() {
        visibility = viewModel.pillVisibility
    }
}

// MARK: - Pill Preview

private struct PillPreviewView: View {
    let buttons: [ControlButtonConfiguration]

    private let buttonSize: CGFloat = 24
    private let buttonSpacing: CGFloat = 8

    var body: some View {
        HStack(spacing: buttonSpacing) {
            ForEach(buttons) { config in
                CompactPreviewButtonView(configuration: config, size: buttonSize)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Image("PlayerControlsPreviewBackground")
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.5))
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// Preview requires AppEnvironment - use app to test
