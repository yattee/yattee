//
//  PlayerControlsSettingsViewModel.swift
//  Yattee
//
//  ViewModel for the player controls customization settings UI.
//

import Foundation
import SwiftUI

/// ViewModel for the player controls settings view.
/// Manages preset selection, layout editing, and auto-save.
@MainActor
@Observable
final class PlayerControlsSettingsViewModel {
    // MARK: - Dependencies

    private let layoutService: PlayerControlsLayoutService
    let settingsManager: SettingsManager

    /// Observer for preset changes from CloudKit sync.
    @ObservationIgnored private var presetsChangedObserver: NSObjectProtocol?

    // MARK: - State

    /// All available presets for the current device.
    private(set) var presets: [LayoutPreset] = []

    /// The currently active/selected preset.
    private(set) var activePreset: LayoutPreset?

    /// Whether currently loading presets.
    private(set) var isLoading = false

    /// Error message to display, if any.
    private(set) var error: String?

    /// Whether the preview is showing landscape mode.
    var isPreviewingLandscape = false

    /// The section currently selected for editing.
    var selectedSection: LayoutSectionType?

    /// Whether a save operation is in progress.
    private(set) var isSaving = false

    /// Debounced save task for coalescing rapid updates.
    private var saveTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// ID of the active preset.
    var activePresetID: UUID? {
        activePreset?.id
    }

    /// Whether the active preset can be deleted (not built-in and not active).
    var canDeleteActivePreset: Bool {
        guard let activePreset else { return false }
        return !activePreset.isBuiltIn
    }

    /// Whether the active preset can be edited (not built-in).
    var canEditActivePreset: Bool {
        guard let activePreset else { return false }
        return !activePreset.isBuiltIn
    }

    /// Current layout from active preset, or default.
    var currentLayout: PlayerControlsLayout {
        activePreset?.layout ?? .default
    }

    /// Current center section settings for observation.
    var centerSettings: CenterSectionSettings {
        activePreset?.layout.centerSettings ?? .default
    }

    /// Seek backward seconds - exposed for direct observation.
    var seekBackwardSeconds: Int {
        activePreset?.layout.centerSettings.seekBackwardSeconds ?? 10
    }

    /// Seek forward seconds - exposed for direct observation.
    var seekForwardSeconds: Int {
        activePreset?.layout.centerSettings.seekForwardSeconds ?? 10
    }

    /// Current progress bar settings.
    var progressBarSettings: ProgressBarSettings {
        activePreset?.layout.progressBarSettings ?? .default
    }

    /// Built-in presets sorted by name.
    var builtInPresets: [LayoutPreset] {
        presets.filter(\.isBuiltIn).sorted { $0.name < $1.name }
    }

    /// Custom (user-created) presets sorted by name.
    var customPresets: [LayoutPreset] {
        presets.filter { !$0.isBuiltIn }.sorted { $0.name < $1.name }
    }

    /// Button types that are new since last seen.
    var newButtonTypes: [ControlButtonType] {
        Task.detached { [layoutService] in
            await layoutService.newButtonTypes()
        }
        // Return empty for now; actual implementation will load async
        return []
    }

    // MARK: - Initialization

    init(
        layoutService: PlayerControlsLayoutService,
        settingsManager: SettingsManager
    ) {
        self.layoutService = layoutService
        self.settingsManager = settingsManager

        // Observe preset changes from CloudKit sync
        presetsChangedObserver = NotificationCenter.default.addObserver(
            forName: .playerControlsPresetsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handlePresetsChanged()
            }
        }
    }

    /// Handles preset changes from CloudKit sync.
    private func handlePresetsChanged() async {
        do {
            let loadedPresets = try await layoutService.loadPresets()
            presets = loadedPresets.filter { $0.deviceClass == .current }

            // Refresh active preset if it was updated
            // Use in-memory activePreset?.id to avoid race condition with setActivePresetID
            if let activeID = activePreset?.id,
               let updatedPreset = presets.first(where: { $0.id == activeID }) {
                activePreset = updatedPreset
            }

            LoggingService.shared.debug("Reloaded presets after CloudKit sync", category: .general)
        } catch {
            LoggingService.shared.error("Failed to reload presets after CloudKit sync: \(error.localizedDescription)")
        }
    }

    deinit {
        if let observer = presetsChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Loading

    /// Loads all presets and sets the active preset.
    func loadPresets() async {
        isLoading = true
        error = nil

        do {
            let loadedPresets = try await layoutService.loadPresets()
            presets = loadedPresets.filter { $0.deviceClass == .current }
            activePreset = await layoutService.activePreset()
            LoggingService.shared.info("Loaded \(presets.count) presets, active: \(activePreset?.name ?? "none")")
        } catch {
            self.error = error.localizedDescription
            LoggingService.shared.error("Failed to load presets: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Refreshes presets from storage.
    func refreshPresets() async {
        do {
            let loadedPresets = try await layoutService.loadPresets()
            presets = loadedPresets.filter { $0.deviceClass == .current }
            
            // Update active preset if it changed
            if let activeID = activePresetID,
               let updatedPreset = presets.first(where: { $0.id == activeID }) {
                activePreset = updatedPreset
            }
        } catch {
            LoggingService.shared.error("Failed to refresh presets: \(error.localizedDescription)")
        }
    }

    // MARK: - Preset Selection

    /// Selects a preset as the active preset.
    /// - Parameter preset: The preset to activate.
    func selectPreset(_ preset: LayoutPreset) {
        activePreset = preset
        Task {
            await layoutService.setActivePresetID(preset.id)
        }
        LoggingService.shared.info("Selected preset: \(preset.name)")
    }

    /// Selects a preset by ID.
    /// - Parameter id: The ID of the preset to activate.
    func selectPreset(id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        selectPreset(preset)
    }

    // MARK: - Preset Management

    /// Creates a new custom preset with the given name.
    /// - Parameters:
    ///   - name: Name for the new preset.
    ///   - basePreset: Optional preset to copy layout from. Uses default layout if nil.
    func createPreset(name: String, basedOn basePreset: LayoutPreset? = nil) async {
        let layout = basePreset?.layout ?? .default
        let newPreset = LayoutPreset(
            name: name,
            isBuiltIn: false,
            deviceClass: .current,
            layout: layout
        )

        do {
            try await layoutService.savePreset(newPreset)
            await refreshPresets()
            // Select the newly created preset from the refreshed list for consistency
            if let savedPreset = presets.first(where: { $0.id == newPreset.id }) {
                selectPreset(savedPreset)
            } else {
                selectPreset(newPreset)
            }
            LoggingService.shared.info("Created preset: \(name) based on: \(basePreset?.name ?? "default")")
        } catch {
            self.error = error.localizedDescription
            LoggingService.shared.error("Failed to create preset: \(error.localizedDescription)")
        }
    }

    /// Deletes a preset.
    /// - Parameter preset: The preset to delete.
    func deletePreset(_ preset: LayoutPreset) async {
        guard !preset.isBuiltIn else {
            error = "Cannot delete built-in presets"
            return
        }

        // If deleting active preset, switch to default first
        let wasActive = preset.id == activePresetID
        if wasActive {
            if let defaultPreset = builtInPresets.first(where: { $0.name == "Default" }) ?? builtInPresets.first {
                selectPreset(defaultPreset)
            }
        }

        do {
            try await layoutService.deletePreset(id: preset.id)
            await refreshPresets()
            LoggingService.shared.info("Deleted preset: \(preset.name)")
        } catch {
            self.error = error.localizedDescription
            LoggingService.shared.error("Failed to delete preset: \(error.localizedDescription)")
        }
    }

    /// Renames a preset.
    /// - Parameters:
    ///   - preset: The preset to rename.
    ///   - newName: The new name.
    func renamePreset(_ preset: LayoutPreset, to newName: String) async {
        guard !preset.isBuiltIn else {
            error = "Cannot rename built-in presets"
            return
        }

        do {
            try await layoutService.renamePreset(preset.id, to: newName)
            await refreshPresets()
            LoggingService.shared.info("Renamed preset to: \(newName)")
        } catch {
            self.error = error.localizedDescription
            LoggingService.shared.error("Failed to rename preset: \(error.localizedDescription)")
        }
    }

    // MARK: - Layout Editing

    /// Updates the top section of the current layout.
    /// - Parameter section: The new top section configuration.
    func updateTopSection(_ section: LayoutSection) async {
        await updateLayout { layout in
            layout.topSection = section
        }
    }

    /// Updates the bottom section of the current layout.
    /// - Parameter section: The new bottom section configuration.
    func updateBottomSection(_ section: LayoutSection) async {
        await updateLayout { layout in
            layout.bottomSection = section
        }
    }

    /// Updates the center settings of the current layout.
    /// - Parameter settings: The new center section settings.
    func updateCenterSettings(_ settings: CenterSectionSettings) async {
        await updateLayout { layout in
            layout.centerSettings = settings
        }
    }

    /// Synchronously updates center settings with immediate UI feedback.
    /// Saves are debounced to avoid rapid disk writes.
    /// - Parameter mutation: A closure that mutates the center settings.
    func updateCenterSettingsSync(_ mutation: (inout CenterSectionSettings) -> Void) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        let oldSettings = layout.centerSettings
        mutation(&layout.centerSettings)
        let newSettings = layout.centerSettings
        LoggingService.shared.debug(
            "updateCenterSettingsSync: seekBackward \(oldSettings.seekBackwardSeconds) -> \(newSettings.seekBackwardSeconds), seekForward \(oldSettings.seekForwardSeconds) -> \(newSettings.seekForwardSeconds)",
            category: .general
        )
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        // Queue debounced save
        queueDebouncedSave(preset: preset)
    }

    /// Updates the global settings of the current layout.
    /// - Parameter settings: The new global settings.
    func updateGlobalSettings(_ settings: GlobalLayoutSettings) async {
        await updateLayout { layout in
            layout.globalSettings = settings
        }
    }

    /// Synchronously updates global settings with immediate UI feedback.
    /// Saves are debounced to avoid rapid disk writes.
    /// - Parameter mutation: A closure that mutates the global settings.
    func updateGlobalSettingsSync(_ mutation: (inout GlobalLayoutSettings) -> Void) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        mutation(&layout.globalSettings)
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        // Queue debounced save
        queueDebouncedSave(preset: preset)
    }

    /// Synchronously updates progress bar settings with immediate UI feedback.
    /// Saves are debounced to avoid rapid disk writes.
    /// - Parameter mutation: A closure that mutates the progress bar settings.
    func updateProgressBarSettingsSync(_ mutation: (inout ProgressBarSettings) -> Void) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        mutation(&layout.progressBarSettings)
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        // Queue debounced save
        queueDebouncedSave(preset: preset)
    }

    /// Updates a button configuration in the specified section.
    /// - Parameters:
    ///   - config: The updated button configuration.
    ///   - section: The section containing the button.
    func updateButtonConfiguration(_ config: ControlButtonConfiguration, in section: LayoutSectionType) async {
        await updateLayout { layout in
            switch section {
            case .top:
                layout.topSection.update(button: config)
            case .bottom:
                layout.bottomSection.update(button: config)
            }
        }
    }

    /// Synchronously updates a button configuration with immediate UI feedback.
    /// Saves are debounced to avoid rapid disk writes.
    /// - Parameters:
    ///   - config: The updated button configuration.
    ///   - section: The section containing the button.
    func updateButtonConfigurationSync(_ config: ControlButtonConfiguration, in section: LayoutSectionType) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        switch section {
        case .top:
            layout.topSection.update(button: config)
        case .bottom:
            layout.bottomSection.update(button: config)
        }
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        // Queue debounced save
        queueDebouncedSave(preset: preset)
    }

    /// Adds a button to the specified section.
    /// - Parameters:
    ///   - buttonType: The type of button to add.
    ///   - section: The section to add the button to.
    func addButton(_ buttonType: ControlButtonType, to section: LayoutSectionType) async {
        await updateLayout { layout in
            let config = ControlButtonConfiguration.defaultConfiguration(for: buttonType)
            switch section {
            case .top:
                layout.topSection.add(button: config)
            case .bottom:
                layout.bottomSection.add(button: config)
            }
        }
    }

    /// Synchronously adds a button with immediate UI feedback.
    /// - Parameters:
    ///   - buttonType: The type of button to add.
    ///   - section: The section to add the button to.
    func addButtonSync(_ buttonType: ControlButtonType, to section: LayoutSectionType) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        let config = ControlButtonConfiguration.defaultConfiguration(for: buttonType)
        switch section {
        case .top:
            layout.topSection.add(button: config)
        case .bottom:
            layout.bottomSection.add(button: config)
        }
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        queueDebouncedSave(preset: preset)
    }

    /// Removes a button from the specified section.
    /// - Parameters:
    ///   - buttonID: The ID of the button to remove.
    ///   - section: The section containing the button.
    func removeButton(_ buttonID: UUID, from section: LayoutSectionType) async {
        await updateLayout { layout in
            switch section {
            case .top:
                layout.topSection.remove(id: buttonID)
            case .bottom:
                layout.bottomSection.remove(id: buttonID)
            }
        }
    }

    /// Synchronously removes a button with immediate UI feedback.
    /// - Parameters:
    ///   - buttonID: The ID of the button to remove.
    ///   - section: The section containing the button.
    func removeButtonSync(_ buttonID: UUID, from section: LayoutSectionType) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        switch section {
        case .top:
            layout.topSection.remove(id: buttonID)
        case .bottom:
            layout.bottomSection.remove(id: buttonID)
        }
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        queueDebouncedSave(preset: preset)
    }

    /// Moves a button within a section.
    /// - Parameters:
    ///   - source: Source indices.
    ///   - destination: Destination index.
    ///   - section: The section containing the buttons.
    func moveButton(fromOffsets source: IndexSet, toOffset destination: Int, in section: LayoutSectionType) async {
        await updateLayout { layout in
            switch section {
            case .top:
                layout.topSection.move(fromOffsets: source, toOffset: destination)
            case .bottom:
                layout.bottomSection.move(fromOffsets: source, toOffset: destination)
            }
        }
    }

    /// Synchronously moves a button with immediate UI feedback.
    /// - Parameters:
    ///   - source: Source indices.
    ///   - destination: Destination index.
    ///   - section: The section containing the buttons.
    func moveButtonSync(fromOffsets source: IndexSet, toOffset destination: Int, in section: LayoutSectionType) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        switch section {
        case .top:
            layout.topSection.move(fromOffsets: source, toOffset: destination)
        case .bottom:
            layout.bottomSection.move(fromOffsets: source, toOffset: destination)
        }
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        queueDebouncedSave(preset: preset)
    }

    // MARK: - Gesture Settings

    /// Current gestures settings from active preset, or default.
    var gesturesSettings: GesturesSettings {
        activePreset?.layout.effectiveGesturesSettings ?? .default
    }

    /// Synchronously updates gestures settings with immediate UI feedback.
    /// Saves are debounced to avoid rapid disk writes.
    /// - Parameter mutation: A closure that mutates the gestures settings.
    func updateGesturesSettingsSync(_ mutation: (inout GesturesSettings) -> Void) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        var settings = layout.effectiveGesturesSettings
        mutation(&settings)
        layout.gesturesSettings = settings
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        queueDebouncedSave(preset: preset)
    }

    /// Synchronously updates tap gestures settings with immediate UI feedback.
    /// - Parameter mutation: A closure that mutates the tap gestures settings.
    func updateTapGesturesSettingsSync(_ mutation: (inout TapGesturesSettings) -> Void) {
        updateGesturesSettingsSync { settings in
            mutation(&settings.tapGestures)
        }
    }

    /// Updates a tap zone configuration.
    /// - Parameter config: The updated configuration.
    func updateTapZoneConfigurationSync(_ config: TapZoneConfiguration) {
        updateTapGesturesSettingsSync { settings in
            settings = settings.withUpdatedConfiguration(config)
        }
    }

    /// Current seek gesture settings from active preset, or default.
    var seekGestureSettings: SeekGestureSettings {
        activePreset?.layout.effectiveGesturesSettings.seekGesture ?? .default
    }

    /// Synchronously updates seek gesture settings with immediate UI feedback.
    /// - Parameter mutation: A closure that mutates the seek gesture settings.
    func updateSeekGestureSettingsSync(_ mutation: (inout SeekGestureSettings) -> Void) {
        updateGesturesSettingsSync { settings in
            mutation(&settings.seekGesture)
        }
    }

    /// Current panscan gesture settings from active preset, or default.
    var panscanGestureSettings: PanscanGestureSettings {
        activePreset?.layout.effectiveGesturesSettings.panscanGesture ?? .default
    }

    /// Synchronously updates panscan gesture settings with immediate UI feedback.
    /// - Parameter mutation: A closure that mutates the panscan gesture settings.
    func updatePanscanGestureSettingsSync(_ mutation: (inout PanscanGestureSettings) -> Void) {
        updateGesturesSettingsSync { settings in
            mutation(&settings.panscanGesture)
        }
    }

    // MARK: - Player Pill Settings

    /// Current player pill settings from active preset, or default.
    var playerPillSettings: PlayerPillSettings {
        activePreset?.layout.effectivePlayerPillSettings ?? .default
    }

    /// Current pill visibility mode.
    var pillVisibility: PillVisibility {
        playerPillSettings.visibility
    }

    /// Current pill buttons configuration.
    var pillButtons: [ControlButtonConfiguration] {
        playerPillSettings.buttons
    }

    /// Current comments pill mode.
    var commentsPillMode: CommentsPillMode {
        playerPillSettings.effectiveCommentsPillMode
    }

    /// Synchronously updates the comments pill mode with immediate UI feedback.
    /// - Parameter mode: The new comments pill mode.
    func syncCommentsPillMode(_ mode: CommentsPillMode) {
        updatePlayerPillSettingsSync { settings in
            settings.commentsPillMode = mode
        }
    }

    // MARK: - Wide Layout Panel Settings

    /// Current wide layout panel alignment from active preset, or default.
    var wideLayoutPanelAlignment: FloatingPanelSide {
        activePreset?.layout.effectiveWideLayoutPanelAlignment ?? .right
    }

    /// Synchronously updates the wide layout panel alignment with immediate UI feedback.
    /// - Parameter alignment: The new panel alignment.
    func syncWideLayoutPanelAlignment(_ alignment: FloatingPanelSide) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        layout.wideLayoutPanelAlignment = alignment
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        queueDebouncedSave(preset: preset)
    }

    /// Synchronously updates the pill visibility with immediate UI feedback.
    /// - Parameter visibility: The new visibility mode.
    func syncPillVisibility(_ visibility: PillVisibility) {
        updatePlayerPillSettingsSync { settings in
            settings.visibility = visibility
        }
    }

    /// Adds a button to the pill.
    /// - Parameter buttonType: The type of button to add.
    func addPillButton(_ buttonType: ControlButtonType) {
        updatePlayerPillSettingsSync { settings in
            settings.add(buttonType: buttonType)
        }
    }

    /// Removes a button from the pill at the given index.
    /// - Parameter index: The index of the button to remove.
    func removePillButton(at index: Int) {
        updatePlayerPillSettingsSync { settings in
            settings.remove(at: index)
        }
    }

    /// Moves buttons within the pill.
    /// - Parameters:
    ///   - source: Source indices to move from.
    ///   - destination: Destination index to move to.
    func movePillButtons(fromOffsets source: IndexSet, toOffset destination: Int) {
        updatePlayerPillSettingsSync { settings in
            settings.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// Updates a specific button configuration in the pill.
    /// - Parameter configuration: The updated button configuration with matching ID.
    func updatePillButtonConfiguration(_ configuration: ControlButtonConfiguration) {
        updatePlayerPillSettingsSync { settings in
            settings.update(configuration)
        }
    }

    /// Synchronously updates player pill settings with immediate UI feedback.
    /// Saves are debounced to avoid rapid disk writes.
    /// - Parameter mutation: A closure that mutates the pill settings.
    func updatePlayerPillSettingsSync(_ mutation: (inout PlayerPillSettings) -> Void) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        var settings = layout.effectivePlayerPillSettings
        mutation(&settings)
        layout.playerPillSettings = settings
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        queueDebouncedSave(preset: preset)
    }

    // MARK: - Mini Player Settings

    /// Current mini player settings from active preset, or default.
    var miniPlayerSettings: MiniPlayerSettings {
        activePreset?.layout.effectiveMiniPlayerSettings ?? .default
    }

    /// Whether to show video in mini player.
    var miniPlayerShowVideo: Bool {
        miniPlayerSettings.showVideo
    }

    /// Action when tapping video in mini player.
    var miniPlayerVideoTapAction: MiniPlayerVideoTapAction {
        miniPlayerSettings.videoTapAction
    }

    /// Current mini player buttons configuration.
    var miniPlayerButtons: [ControlButtonConfiguration] {
        miniPlayerSettings.buttons
    }

    /// Synchronously updates the mini player show video setting.
    /// - Parameter showVideo: Whether to show video in mini player.
    func syncMiniPlayerShowVideo(_ showVideo: Bool) {
        updateMiniPlayerSettingsSync { settings in
            settings.showVideo = showVideo
        }
    }

    /// Synchronously updates the mini player video tap action.
    /// - Parameter action: The new tap action.
    func syncMiniPlayerVideoTapAction(_ action: MiniPlayerVideoTapAction) {
        updateMiniPlayerSettingsSync { settings in
            settings.videoTapAction = action
        }
    }

    /// Adds a button to the mini player.
    /// - Parameter buttonType: The type of button to add.
    func addMiniPlayerButton(_ buttonType: ControlButtonType) {
        updateMiniPlayerSettingsSync { settings in
            settings.add(buttonType: buttonType)
        }
    }

    /// Removes a button from the mini player at the given index.
    /// - Parameter index: The index of the button to remove.
    func removeMiniPlayerButton(at index: Int) {
        updateMiniPlayerSettingsSync { settings in
            settings.remove(at: index)
        }
    }

    /// Moves buttons within the mini player.
    /// - Parameters:
    ///   - source: Source indices to move from.
    ///   - destination: Destination index to move to.
    func moveMiniPlayerButtons(fromOffsets source: IndexSet, toOffset destination: Int) {
        updateMiniPlayerSettingsSync { settings in
            settings.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// Updates a specific button configuration in the mini player.
    /// - Parameter configuration: The updated button configuration with matching ID.
    func updateMiniPlayerButtonConfiguration(_ configuration: ControlButtonConfiguration) {
        updateMiniPlayerSettingsSync { settings in
            settings.update(configuration)
        }
    }

    /// Synchronously updates mini player settings with immediate UI feedback.
    /// Saves are debounced to avoid rapid disk writes.
    /// - Parameter mutation: A closure that mutates the mini player settings.
    func updateMiniPlayerSettingsSync(_ mutation: (inout MiniPlayerSettings) -> Void) {
        guard var preset = activePreset, !preset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = preset.layout
        var settings = layout.effectiveMiniPlayerSettings
        mutation(&settings)
        layout.miniPlayerSettings = settings
        preset = preset.withUpdatedLayout(layout)
        self.activePreset = preset

        queueDebouncedSave(preset: preset)
    }

    // MARK: - System Controls & Volume

    /// Current system controls mode from active preset, or default.
    var systemControlsMode: SystemControlsMode {
        activePreset?.layout.globalSettings.systemControlsMode ?? .seek
    }

    /// Current system controls seek duration from active preset, or default.
    var systemControlsSeekDuration: SystemControlsSeekDuration {
        activePreset?.layout.globalSettings.systemControlsSeekDuration ?? .tenSeconds
    }

    /// Current volume mode from active preset, or default.
    var volumeMode: VolumeMode {
        activePreset?.layout.globalSettings.volumeMode ?? .mpv
    }

    /// Synchronously updates the system controls mode with immediate UI feedback.
    func updateSystemControlsModeSync(_ mode: SystemControlsMode) {
        updateGlobalSettingsSync { settings in
            settings.systemControlsMode = mode
        }
    }

    /// Synchronously updates the system controls seek duration with immediate UI feedback.
    func updateSystemControlsSeekDurationSync(_ duration: SystemControlsSeekDuration) {
        updateGlobalSettingsSync { settings in
            settings.systemControlsSeekDuration = duration
        }
    }

    /// Synchronously updates the volume mode with immediate UI feedback.
    func updateVolumeModeSync(_ mode: VolumeMode) {
        updateGlobalSettingsSync { settings in
            settings.volumeMode = mode
        }
    }

    // MARK: - Private Helpers

    /// Updates the layout and saves to storage.
    /// - Parameter mutation: A closure that mutates the layout.
    private func updateLayout(_ mutation: (inout PlayerControlsLayout) -> Void) async {
        guard let activePreset, !activePreset.isBuiltIn else {
            error = "Cannot edit built-in presets. Duplicate it first."
            return
        }

        var layout = activePreset.layout
        mutation(&layout)

        // Update local state immediately for responsive UI
        self.activePreset = activePreset.withUpdatedLayout(layout)

        // Save to storage
        isSaving = true
        do {
            try await layoutService.updatePresetLayout(activePreset.id, layout: layout)
            await refreshPresets()
        } catch {
            self.error = error.localizedDescription
            LoggingService.shared.error("Failed to save layout: \(error.localizedDescription)")
        }
        isSaving = false
    }

    /// Queues a debounced save operation.
    /// Cancels any pending save and waits before persisting to avoid rapid disk writes.
    /// - Parameter preset: The preset to save.
    private func queueDebouncedSave(preset: LayoutPreset) {
        saveTask?.cancel()
        saveTask = Task {
            // Wait for 300ms to coalesce rapid changes (e.g., slider dragging)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isSaving = true
            do {
                try await layoutService.updatePresetLayout(preset.id, layout: preset.layout)
                // Don't call refreshPresets() here - we already have the updated state locally
            } catch {
                self.error = error.localizedDescription
                LoggingService.shared.error("Failed to save layout: \(error.localizedDescription)")
            }
            isSaving = false
        }
    }

    // MARK: - NEW Badge Support

    /// Marks all button types as seen, hiding NEW badges.
    func markAllButtonsAsSeen() async {
        await layoutService.markAllButtonsAsSeen()
    }

    /// Returns whether a button type should show the NEW badge.
    /// - Parameter type: The button type to check.
    /// - Returns: True if the button was added after the last seen version.
    func isNewButton(_ type: ControlButtonType) async -> Bool {
        let newTypes = await layoutService.newButtonTypes()
        return newTypes.contains(type)
    }

    // MARK: - Error Handling

    /// Clears the current error.
    func clearError() {
        error = nil
    }

    // MARK: - Export/Import

    /// Exports a preset to a temporary JSON file.
    /// - Parameter preset: The preset to export.
    /// - Returns: URL of the temporary file, or nil if export failed.
    func exportPreset(_ preset: LayoutPreset) -> URL? {
        guard !preset.isBuiltIn else {
            error = "Cannot export built-in presets"
            return nil
        }

        guard let data = PlayerControlsPresetExportImport.exportToJSON(preset) else {
            error = "Failed to export preset"
            return nil
        }

        let filename = PlayerControlsPresetExportImport.generateExportFilename(for: preset)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL)
            LoggingService.shared.info("Exported preset '\(preset.name)' to \(tempURL.path)")
            return tempURL
        } catch {
            self.error = "Failed to write export file: \(error.localizedDescription)"
            LoggingService.shared.error("Failed to write export file: \(error.localizedDescription)")
            return nil
        }
    }

    /// Imports a preset from a file URL.
    /// - Parameter url: URL of the JSON file to import.
    /// - Returns: The imported preset name on success.
    /// - Throws: `LayoutPresetImportError` if import fails.
    @discardableResult
    func importPreset(from url: URL) async throws -> String {
        // Read file data with security-scoped resource access
        let data: Data
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            data = try Data(contentsOf: url)
        } catch {
            LoggingService.shared.error("Failed to read import file: \(error.localizedDescription)")
            throw LayoutPresetImportError.invalidData
        }

        // Parse and validate the preset
        let importedPreset = try PlayerControlsPresetExportImport.importFromJSON(data)

        // Save the preset
        do {
            try await layoutService.savePreset(importedPreset)
            await refreshPresets()
            LoggingService.shared.info("Imported preset: \(importedPreset.name)")
            return importedPreset.name
        } catch {
            self.error = error.localizedDescription
            LoggingService.shared.error("Failed to save imported preset: \(error.localizedDescription)")
            throw LayoutPresetImportError.invalidData
        }
    }
}
