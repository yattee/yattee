//
//  TapGesturesSettingsView.swift
//  Yattee
//
//  Settings view for configuring tap gestures.
//

#if os(iOS)
import SwiftUI

/// Settings view for configuring tap gestures on the player.
struct TapGesturesSettingsView: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var isEnabled: Bool = false
    @State private var layout: TapZoneLayout = .horizontalSplit
    @State private var doubleTapInterval: Int = 300
    @State private var zoneConfigurations: [TapZoneConfiguration] = []

    // Navigation state
    @State private var selectedZonePosition: TapZonePosition?

    var body: some View {
        List {
            enableSection
            if isEnabled {
                layoutSection
                previewSection
                zonesSection
                timingSection
            }
        }
        .navigationTitle(String(localized: "gestures.tap.title", defaultValue: "Tap Gestures"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            syncFromViewModel()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            syncFromViewModel()
        }
        .sheet(item: $selectedZonePosition) { position in
            NavigationStack {
                zoneActionPicker(for: position)
            }
        }
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            Toggle(
                String(localized: "gestures.tap.enable", defaultValue: "Enable Tap Gestures"),
                isOn: $isEnabled
            )
            .onChange(of: isEnabled) { _, newValue in
                viewModel.updateTapGesturesSettingsSync { $0.isEnabled = newValue }
            }
            .disabled(!viewModel.canEditActivePreset)
        } footer: {
            Text(String(localized: "gestures.tap.enableFooter", defaultValue: "Double-tap zones on the player to trigger actions when controls are hidden."))
        }
    }

    private var layoutSection: some View {
        Section {
            TapZoneLayoutPicker(selectedLayout: $layout)
                .onChange(of: layout) { _, newLayout in
                    // Update configurations for new layout
                    zoneConfigurations = TapGesturesSettings.defaultConfigurations(for: newLayout)
                    viewModel.updateTapGesturesSettingsSync { settings in
                        settings = settings.withLayout(newLayout)
                    }
                }
                .disabled(!viewModel.canEditActivePreset)
        } header: {
            Text(String(localized: "gestures.tap.layout", defaultValue: "Zone Layout"))
        } footer: {
            Text(String(localized: "gestures.tap.layoutFooter", defaultValue: "Choose how the screen is divided into tap zones."))
        }
    }

    private var previewSection: some View {
        Section {
            TapZonePreview(
                layout: layout,
                configurations: zoneConfigurations,
                onZoneTapped: { position in
                    if viewModel.canEditActivePreset {
                        selectedZonePosition = position
                    }
                }
            )
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text(String(localized: "gestures.tap.preview", defaultValue: "Preview"))
        } footer: {
            Text(String(localized: "gestures.tap.previewFooter", defaultValue: "Tap a zone to configure its action."))
        }
    }

    private var zonesSection: some View {
        Section {
            ForEach(layout.positions, id: \.self) { position in
                Button {
                    if viewModel.canEditActivePreset {
                        selectedZonePosition = position
                    }
                } label: {
                    HStack {
                        Text(position.displayName)
                            .foregroundStyle(.primary)

                        Spacer()

                        if let config = zoneConfigurations.first(where: { $0.position == position }) {
                            Label {
                                Text(actionSummary(for: config.action))
                            } icon: {
                                Image(systemName: config.action.systemImage)
                            }
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .disabled(!viewModel.canEditActivePreset)
            }
        } header: {
            Text(String(localized: "gestures.tap.zones", defaultValue: "Zone Actions"))
        }
    }

    private var timingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "gestures.tap.doubleTapWindow", defaultValue: "Double-Tap Window"))
                    Spacer()
                    Text("\(doubleTapInterval)ms")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(doubleTapInterval) },
                        set: {
                            doubleTapInterval = Int($0)
                            viewModel.updateTapGesturesSettingsSync { $0.doubleTapInterval = doubleTapInterval }
                        }
                    ),
                    in: Double(TapGesturesSettings.doubleTapIntervalRange.lowerBound)...Double(TapGesturesSettings.doubleTapIntervalRange.upperBound),
                    step: 25
                )
                .disabled(!viewModel.canEditActivePreset)
            }
        } header: {
            Text(String(localized: "gestures.tap.timing", defaultValue: "Timing"))
        } footer: {
            Text(String(localized: "gestures.tap.timingFooter", defaultValue: "Time window to detect a double-tap. Lower values are faster but may conflict with single-tap."))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func zoneActionPicker(for position: TapZonePosition) -> some View {
        let binding = Binding<TapGestureAction>(
            get: {
                zoneConfigurations.first { $0.position == position }?.action ?? .togglePlayPause
            },
            set: { newAction in
                if let index = zoneConfigurations.firstIndex(where: { $0.position == position }) {
                    zoneConfigurations[index] = zoneConfigurations[index].withAction(newAction)
                    viewModel.updateTapZoneConfigurationSync(zoneConfigurations[index])
                }
            }
        )

        TapZoneActionPicker(position: position, action: binding)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        selectedZonePosition = nil
                    } label: {
                        Label(String(localized: "common.close"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
    }

    private func syncFromViewModel() {
        let settings = viewModel.gesturesSettings.tapGestures
        isEnabled = settings.isEnabled
        layout = settings.layout
        doubleTapInterval = settings.doubleTapInterval
        zoneConfigurations = settings.zoneConfigurations
    }

    private func actionSummary(for action: TapGestureAction) -> String {
        switch action {
        case .seekForward(let seconds):
            "+\(seconds)s"
        case .seekBackward(let seconds):
            "-\(seconds)s"
        case .togglePlayPause:
            String(localized: "gestures.action.playPause.short", defaultValue: "Play/Pause")
        case .toggleFullscreen:
            String(localized: "gestures.action.fullscreen.short", defaultValue: "Fullscreen")
        case .togglePiP:
            String(localized: "gestures.action.pip.short", defaultValue: "PiP")
        case .playNext:
            String(localized: "gestures.action.next.short", defaultValue: "Next")
        case .playPrevious:
            String(localized: "gestures.action.previous.short", defaultValue: "Previous")
        case .cyclePlaybackSpeed:
            String(localized: "gestures.action.speed.short", defaultValue: "Speed")
        case .toggleMute:
            String(localized: "gestures.action.mute.short", defaultValue: "Mute")
        }
    }
}

#Preview {
    NavigationStack {
        TapGesturesSettingsView(
            viewModel: PlayerControlsSettingsViewModel(
                layoutService: PlayerControlsLayoutService(),
                settingsManager: SettingsManager()
            )
        )
    }
}
#endif
