//
//  PlayerControlsSettingsView.swift
//  Yattee
//
//  Main settings view for player controls customization.
//

import SwiftUI

/// Settings view for customizing player controls layout and presets.
struct PlayerControlsSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var viewModel: PlayerControlsSettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                PlayerControlsSettingsContent(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(String(localized: "settings.playerControls.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if viewModel == nil, let appEnv = appEnvironment {
                let vm = PlayerControlsSettingsViewModel(
                    layoutService: appEnv.playerControlsLayoutService,
                    settingsManager: appEnv.settingsManager
                )
                viewModel = vm
                await vm.loadPresets()
            }
        }
    }
}

// MARK: - Content View

private struct PlayerControlsSettingsContent: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var style: ControlsStyle = .glass
    @State private var buttonSize: ButtonSize = .medium
    @State private var fontStyle: ControlsFontStyle = .system

    // Refresh trigger to force view update on navigation back
    @State private var refreshID = UUID()

    // Track active preset locally to ensure view updates
    @State private var trackedActivePresetName: String = "Default"

    // Create preset sheet state (kept at parent level for stability across refreshes)
    @State private var showCreatePresetSheet = false
    @State private var pendingPresetCreation: PendingPresetCreation?

    private struct PendingPresetCreation: Equatable {
        let name: String
        let basePresetID: UUID?
    }

    /// Layout with local settings override for immediate preview updates
    private var previewLayout: PlayerControlsLayout {
        var layout = viewModel.currentLayout
        layout.globalSettings.style = style
        layout.globalSettings.buttonSize = buttonSize
        layout.globalSettings.fontStyle = fontStyle
        return layout
    }

    var body: some View {
        Form {
            PreviewSection(viewModel: viewModel, layout: previewLayout)
            PresetSection(
                viewModel: viewModel,
                trackedPresetName: $trackedActivePresetName,
                showCreateSheet: $showCreatePresetSheet
            )
            AppearanceSection(
                viewModel: viewModel,
                style: $style,
                buttonSize: $buttonSize,
                fontStyle: $fontStyle
            )
            LayoutSectionsSection(viewModel: viewModel)
            CommentsPillSection(viewModel: viewModel)
            #if os(iOS)
            GesturesSectionsSection(viewModel: viewModel)
            #endif
            SystemControlsSection(viewModel: viewModel)
            VolumeSection(viewModel: viewModel)
        }
        .id(refreshID)
        .alert(
            String(localized: "settings.playerControls.error"),
            isPresented: .constant(viewModel.error != nil)
        ) {
            Button(String(localized: "settings.playerControls.ok")) {
                viewModel.clearError()
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .sheet(isPresented: $showCreatePresetSheet) {
            PresetEditorView(
                mode: .create(
                    baseLayouts: viewModel.presets,
                    activePreset: viewModel.activePreset
                ),
                onSave: { name, basePresetID in
                    pendingPresetCreation = PendingPresetCreation(name: name, basePresetID: basePresetID)
                }
            )
        }
        .task(id: pendingPresetCreation) {
            guard let creation = pendingPresetCreation else { return }
            let basePreset = creation.basePresetID.flatMap { id in
                viewModel.presets.first { $0.id == id }
            }
            await viewModel.createPreset(name: creation.name, basedOn: basePreset)
            pendingPresetCreation = nil
            trackedActivePresetName = viewModel.activePreset?.name ?? "Default"
            NotificationCenter.default.post(name: .presetSelectionDidChange, object: viewModel.activePreset?.name)
        }
        .onAppear {
            style = viewModel.currentLayout.globalSettings.style
            buttonSize = viewModel.currentLayout.globalSettings.buttonSize
            fontStyle = viewModel.currentLayout.globalSettings.fontStyle
            trackedActivePresetName = viewModel.activePreset?.name ?? "Default"
            // Force refresh on every appear to pick up changes from sub-editors
            refreshID = UUID()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            // Sync when preset changes
            style = viewModel.currentLayout.globalSettings.style
            buttonSize = viewModel.currentLayout.globalSettings.buttonSize
            fontStyle = viewModel.currentLayout.globalSettings.fontStyle
            trackedActivePresetName = viewModel.activePreset?.name ?? "Default"
        }
        .onChange(of: viewModel.activePreset?.name) { _, newName in
            // Also track name changes (for initial load)
            trackedActivePresetName = newName ?? "Default"
        }
        .onReceive(NotificationCenter.default.publisher(for: .presetSelectionDidChange)) { notification in
            if let name = notification.object as? String {
                trackedActivePresetName = name
            }
        }
    }
}

// MARK: - Preview Section

private struct PreviewSection: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel
    let layout: PlayerControlsLayout

    var body: some View {
        Section {
            PlayerControlsPreviewView(
                layout: layout,
                isLandscape: viewModel.isPreviewingLandscape
            )
            .frame(height: 200)
            .listRowInsets(EdgeInsets())

            Picker(
                String(localized: "settings.playerControls.previewOrientation"),
                selection: $viewModel.isPreviewingLandscape
            ) {
                Text(String(localized: "settings.playerControls.portrait"))
                    .tag(false)
                Text(String(localized: "settings.playerControls.landscape"))
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }
}

// MARK: - Preset Section

private struct PresetSection: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel
    @Binding var trackedPresetName: String
    @Binding var showCreateSheet: Bool

    private var isBuiltInPreset: Bool {
        viewModel.activePreset?.isBuiltIn == true
    }

    var body: some View {
        Section {
            NavigationLink {
                PresetSelectorView(viewModel: viewModel, onPresetSelected: { name in
                    trackedPresetName = name
                })
            } label: {
                HStack {
                    Text(String(localized: "settings.playerControls.activePreset"))
                    Spacer()
                    Text(trackedPresetName)
                        .foregroundStyle(.secondary)
                }
            }

            if isBuiltInPreset {
                Button {
                    showCreateSheet = true
                } label: {
                    Text(String(localized: "settings.playerControls.newPreset"))
                }
            }
        } footer: {
            if isBuiltInPreset {
                Text(String(localized: "settings.playerControls.builtInPresetHint"))
            }
        }
    }
}

// MARK: - Appearance Section

private struct AppearanceSection: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel
    @Binding var style: ControlsStyle
    @Binding var buttonSize: ButtonSize
    @Binding var fontStyle: ControlsFontStyle

    var body: some View {
        Section {
            Picker(
                String(localized: "settings.playerControls.style"),
                selection: $style
            ) {
                ForEach(ControlsStyle.allCases, id: \.self) { styleOption in
                    Text(styleOption.displayName).tag(styleOption)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: style) { _, newStyle in
                guard newStyle != viewModel.currentLayout.globalSettings.style else { return }
                viewModel.updateGlobalSettingsSync { $0.style = newStyle }
            }

            Picker(
                String(localized: "settings.playerControls.buttonSize"),
                selection: $buttonSize
            ) {
                ForEach(ButtonSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: buttonSize) { _, newSize in
                guard newSize != viewModel.currentLayout.globalSettings.buttonSize else { return }
                viewModel.updateGlobalSettingsSync { $0.buttonSize = newSize }
            }

            Picker(
                String(localized: "settings.playerControls.fontStyle"),
                selection: $fontStyle
            ) {
                ForEach(ControlsFontStyle.allCases, id: \.self) { fontStyleOption in
                    Text(fontStyleOption.displayName).tag(fontStyleOption)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: fontStyle) { _, newFontStyle in
                guard newFontStyle != viewModel.currentLayout.globalSettings.fontStyle else { return }
                viewModel.updateGlobalSettingsSync { $0.fontStyle = newFontStyle }
            }
        } header: {
            Text(String(localized: "settings.playerControls.appearance"))
        }
    }
}

// MARK: - Layout Sections Section

private struct LayoutSectionsSection: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    var body: some View {
        Section {
            NavigationLink {
                SectionEditorView(
                    sectionType: .top,
                    viewModel: viewModel
                )
            } label: {
                HStack {
                    Label(
                        String(localized: "settings.playerControls.topButtons"),
                        systemImage: "rectangle.topthird.inset.filled"
                    )
                    Spacer()
                    Text("\(viewModel.currentLayout.topSection.buttons.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!viewModel.canEditActivePreset)

            NavigationLink {
                CenterControlsSettingsView(viewModel: viewModel)
            } label: {
                Label(
                    String(localized: "settings.playerControls.centerControls"),
                    systemImage: "play.circle"
                )
            }
            .disabled(!viewModel.canEditActivePreset)

            NavigationLink {
                ProgressBarSettingsView(viewModel: viewModel)
            } label: {
                Label(
                    String(localized: "settings.playerControls.progressBar"),
                    systemImage: "slider.horizontal.below.rectangle"
                )
            }
            .disabled(!viewModel.canEditActivePreset)

            NavigationLink {
                SectionEditorView(
                    sectionType: .bottom,
                    viewModel: viewModel
                )
            } label: {
                HStack {
                    Label(
                        String(localized: "settings.playerControls.bottomButtons"),
                        systemImage: "rectangle.bottomthird.inset.filled"
                    )
                    Spacer()
                    Text("\(viewModel.currentLayout.bottomSection.buttons.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!viewModel.canEditActivePreset)

            NavigationLink {
                PlayerPillEditorView(viewModel: viewModel)
            } label: {
                HStack {
                    Label(
                        String(localized: "settings.playerControls.playerPill"),
                        systemImage: "capsule"
                    )
                    Spacer()
                    Text("\(viewModel.playerPillSettings.buttons.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!viewModel.canEditActivePreset)

            NavigationLink {
                MiniPlayerEditorView(viewModel: viewModel)
            } label: {
                Label(
                    String(localized: "settings.playerControls.miniPlayer"),
                    systemImage: "pip"
                )
            }
            .disabled(!viewModel.canEditActivePreset)
        } header: {
            Text(String(localized: "settings.playerControls.layoutSections"))
        } footer: {
            if !viewModel.canEditActivePreset {
                Text(String(localized: "settings.playerControls.duplicateToEdit"))
            }
        }
    }
}

// MARK: - Comments Pill Section

private struct CommentsPillSection: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var commentsPillMode: CommentsPillMode = .pill

    var body: some View {
        Section {
            Picker(
                String(localized: "commentsPill.mode.title"),
                selection: $commentsPillMode
            ) {
                ForEach(CommentsPillMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: commentsPillMode) { _, newValue in
                guard newValue != viewModel.commentsPillMode else { return }
                viewModel.syncCommentsPillMode(newValue)
            }
        }
        .onAppear {
            commentsPillMode = viewModel.commentsPillMode
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            commentsPillMode = viewModel.commentsPillMode
        }
    }
}

// MARK: - Gestures Sections Section (iOS only)

#if os(iOS)
private struct GesturesSectionsSection: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    var body: some View {
        Section {
            NavigationLink {
                TapGesturesSettingsView(viewModel: viewModel)
            } label: {
                HStack {
                    Label(
                        String(localized: "gestures.tap.title", defaultValue: "Tap Gestures"),
                        systemImage: "hand.tap"
                    )
                    Spacer()
                    if viewModel.gesturesSettings.tapGestures.isEnabled {
                        Text(viewModel.gesturesSettings.tapGestures.layout.layoutDescription)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "common.disabled", defaultValue: "Disabled"))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(!viewModel.canEditActivePreset)

            NavigationLink {
                SeekGestureSettingsView(viewModel: viewModel)
            } label: {
                HStack {
                    Label(
                        String(localized: "gestures.seek.title", defaultValue: "Seek Gesture"),
                        systemImage: "hand.draw"
                    )
                    Spacer()
                    if viewModel.gesturesSettings.seekGesture.isEnabled {
                        Text(viewModel.gesturesSettings.seekGesture.sensitivity.displayName)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "common.disabled", defaultValue: "Disabled"))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(!viewModel.canEditActivePreset)

            NavigationLink {
                PanscanGestureSettingsView(viewModel: viewModel)
            } label: {
                HStack {
                    Label(
                        String(localized: "gestures.panscan.title", defaultValue: "Panscan Gesture"),
                        systemImage: "hand.pinch"
                    )
                    Spacer()
                    if viewModel.gesturesSettings.panscanGesture.isEnabled {
                        if viewModel.gesturesSettings.panscanGesture.snapToEnds {
                            Text(String(localized: "gestures.panscan.snap", defaultValue: "Snap"))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "gestures.panscan.freeZoom", defaultValue: "Free Zoom"))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(String(localized: "common.disabled", defaultValue: "Disabled"))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(!viewModel.canEditActivePreset)
        } header: {
            Text(String(localized: "gestures.section.title", defaultValue: "Gestures"))
        } footer: {
            Text(String(localized: "gestures.section.footer", defaultValue: "Control playback with gestures when player controls are hidden."))
        }
    }
}
#endif

// MARK: - System Controls Section

private struct SystemControlsSection: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var systemControlsMode: SystemControlsMode = .seek
    @State private var systemControlsSeekDuration: SystemControlsSeekDuration = .tenSeconds

    var body: some View {
        Section {
            Picker(
                String(localized: "settings.playback.systemControls.mode"),
                selection: $systemControlsMode
            ) {
                ForEach(SystemControlsMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: systemControlsMode) { _, newMode in
                guard newMode != viewModel.systemControlsMode else { return }
                viewModel.updateSystemControlsModeSync(newMode)
                appEnvironment?.playerService.reconfigureSystemControls(
                    mode: newMode,
                    duration: viewModel.systemControlsSeekDuration
                )
            }

            if systemControlsMode == .seek {
                Picker(
                    String(localized: "settings.playback.systemControls.seekDuration"),
                    selection: $systemControlsSeekDuration
                ) {
                    ForEach(SystemControlsSeekDuration.allCases, id: \.self) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }
                .disabled(!viewModel.canEditActivePreset)
                .onChange(of: systemControlsSeekDuration) { _, newDuration in
                    guard newDuration != viewModel.systemControlsSeekDuration else { return }
                    viewModel.updateSystemControlsSeekDurationSync(newDuration)
                    appEnvironment?.playerService.reconfigureSystemControls(
                        mode: viewModel.systemControlsMode,
                        duration: newDuration
                    )
                }
            }
        } header: {
            Text(String(localized: "settings.playback.systemControls.header"))
        } footer: {
            if systemControlsMode == .seek {
                Text(String(localized: "settings.playback.systemControls.seek.footer"))
            } else {
                Text(String(localized: "settings.playback.systemControls.skipTrack.footer"))
            }
        }
        .onAppear {
            syncLocalState()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            syncLocalState()
        }
    }

    private func syncLocalState() {
        systemControlsMode = viewModel.systemControlsMode
        systemControlsSeekDuration = viewModel.systemControlsSeekDuration
    }
}

// MARK: - Volume Section

private struct VolumeSection: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var volumeMode: VolumeMode = .mpv

    var body: some View {
        Section {
            Picker(
                String(localized: "settings.playback.volume.mode"),
                selection: $volumeMode
            ) {
                ForEach(VolumeMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: volumeMode) { _, newMode in
                guard newMode != viewModel.volumeMode else { return }
                viewModel.updateVolumeModeSync(newMode)
                if newMode == .system {
                    // Set MPV to 100% when switching to system mode
                    appEnvironment?.playerService.currentBackend?.volume = 1.0
                    appEnvironment?.playerService.state.volume = 1.0
                }
                // Broadcast the mode change to remote devices
                appEnvironment?.remoteControlCoordinator.broadcastStateUpdate()
            }
        } header: {
            Text(String(localized: "settings.playback.volume.header"))
        } footer: {
            if volumeMode == .mpv {
                Text(String(localized: "settings.playback.volume.mpv.footer"))
            } else {
                Text(String(localized: "settings.playback.volume.system.footer"))
            }
        }
        .onAppear {
            syncLocalState()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            syncLocalState()
        }
    }

    private func syncLocalState() {
        volumeMode = viewModel.volumeMode
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayerControlsSettingsView()
    }
    .appEnvironment(.preview)
}
