//
//  PanscanGestureSettingsView.swift
//  Yattee
//
//  Settings view for configuring pinch-to-panscan gesture.
//

#if os(iOS)
import SwiftUI

/// Settings view for configuring pinch-to-panscan gesture on the player.
struct PanscanGestureSettingsView: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var isEnabled: Bool = true
    @State private var snapToEnds: Bool = true

    var body: some View {
        List {
            enableSection
            if isEnabled {
                snapModeSection
            }
        }
        .navigationTitle(String(localized: "gestures.panscan.title", defaultValue: "Panscan Gesture"))
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
                String(localized: "gestures.panscan.enable", defaultValue: "Enable Panscan Gesture"),
                isOn: $isEnabled
            )
            .onChange(of: isEnabled) { _, newValue in
                viewModel.updatePanscanGestureSettingsSync { $0.isEnabled = newValue }
            }
            .disabled(!viewModel.canEditActivePreset)
        } footer: {
            Text(String(localized: "gestures.panscan.enableFooter", defaultValue: "Pinch to zoom between fit and fill modes while in fullscreen."))
        }
    }

    private var snapModeSection: some View {
        Section {
            Toggle(
                String(localized: "gestures.panscan.snapToEnds", defaultValue: "Snap to Fit/Fill"),
                isOn: $snapToEnds
            )
            .onChange(of: snapToEnds) { _, newValue in
                viewModel.updatePanscanGestureSettingsSync { $0.snapToEnds = newValue }
            }
            .disabled(!viewModel.canEditActivePreset)
        } footer: {
            Text(snapModeFooterText)
        }
    }

    // MARK: - Helpers

    private var snapModeFooterText: String {
        if snapToEnds {
            String(localized: "gestures.panscan.snapToEnds.on.footer", defaultValue: "When released, the zoom will snap to either fit (show full video) or fill (fill the screen).")
        } else {
            String(localized: "gestures.panscan.snapToEnds.off.footer", defaultValue: "The zoom level stays exactly where you release, allowing any value between fit and fill.")
        }
    }

    private func syncFromViewModel() {
        let settings = viewModel.panscanGestureSettings
        isEnabled = settings.isEnabled
        snapToEnds = settings.snapToEnds
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PanscanGestureSettingsView(
            viewModel: PlayerControlsSettingsViewModel(
                layoutService: PlayerControlsLayoutService(),
                settingsManager: SettingsManager()
            )
        )
    }
}
#endif
