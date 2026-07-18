//
//  SeekGestureSettingsView.swift
//  Yattee
//
//  Settings view for configuring horizontal seek gesture.
//

#if os(iOS)
import SwiftUI

/// Settings view for configuring horizontal seek gesture on the player.
struct SeekGestureSettingsView: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var isEnabled: Bool = false
    @State private var sensitivity: SeekGestureSensitivity = .medium

    var body: some View {
        List {
            enableSection
            if isEnabled {
                sensitivitySection
            }
        }
        .navigationTitle(String(localized: "gestures.seek.title", defaultValue: "Seek Gesture"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncFromViewModel()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            syncFromViewModel()
        }
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            Toggle(
                String(localized: "gestures.seek.enable", defaultValue: "Enable Seek Gesture"),
                isOn: $isEnabled
            )
            .onChange(of: isEnabled) { _, newValue in
                viewModel.updateSeekGestureSettingsSync { $0.isEnabled = newValue }
            }
            .disabled(!viewModel.canEditActivePreset)
        } footer: {
            Text(String(localized: "gestures.seek.enableFooter", defaultValue: "Drag left or right to seek backward or forward when controls are hidden."))
        }
    }

    private var sensitivitySection: some View {
        Section {
            Picker(
                String(localized: "gestures.seek.sensitivity", defaultValue: "Sensitivity"),
                selection: $sensitivity
            ) {
                ForEach(SeekGestureSensitivity.allCases, id: \.self) { level in
                    VStack(alignment: .leading) {
                        Text(level.displayName)
                    }
                    .tag(level)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .onChange(of: sensitivity) { _, newValue in
                viewModel.updateSeekGestureSettingsSync { $0.sensitivity = newValue }
            }
            .disabled(!viewModel.canEditActivePreset)
        } header: {
            Text(String(localized: "gestures.seek.sensitivity", defaultValue: "Sensitivity"))
        } footer: {
            Text(sensitivityFooterText)
        }
    }

    // MARK: - Helpers

    private var sensitivityFooterText: String {
        switch sensitivity {
        case .low:
            String(localized: "gestures.seek.sensitivity.low.footer", defaultValue: "Precise control for short videos or fine-tuning.")
        case .medium:
            String(localized: "gestures.seek.sensitivity.medium.footer", defaultValue: "Balanced for most video lengths.")
        case .high:
            String(localized: "gestures.seek.sensitivity.high.footer", defaultValue: "Fast navigation for long videos or podcasts.")
        }
    }

    private func syncFromViewModel() {
        let settings = viewModel.seekGestureSettings
        isEnabled = settings.isEnabled
        sensitivity = settings.sensitivity
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SeekGestureSettingsView(
            viewModel: PlayerControlsSettingsViewModel(
                layoutService: PlayerControlsLayoutService(),
                settingsManager: SettingsManager()
            )
        )
    }
}
#endif
