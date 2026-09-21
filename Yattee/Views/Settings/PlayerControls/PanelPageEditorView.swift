//
//  PanelPageEditorView.swift
//  Yattee
//
//  Settings editor for a single details panel page.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct PanelPageEditorView: View {
    let pageType: PanelPageType
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var isEnabled: Bool = true
    @State private var showDescription: Bool = true
    @State private var showStatsRow: Bool = true
    @State private var showChannelRow: Bool = true

    private var configuration: PanelPageConfiguration? {
        viewModel.panelSettings.configuration(for: pageType)
    }

    /// Whether this is the only enabled page; the last one cannot be disabled.
    private var isLastEnabledPage: Bool {
        isEnabled && viewModel.enabledPanelPageCount <= 1
    }

    var body: some View {
        Form {
            enabledSection

            if pageType == .info {
                infoElementsSection
            }
        }
        .navigationTitle(pageType.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #elseif os(macOS)
        .formStyle(.grouped)
        #endif
        .opaqueSettingsFormBackground()
        .onAppear {
            syncLocalState()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            syncLocalState()
        }
    }

    // MARK: - Enabled Section

    private var enabledSection: some View {
        Section {
            Toggle(
                String(localized: "panel.settings.page.enabled"),
                isOn: $isEnabled
            )
            .disabled(!viewModel.canEditActivePreset || isLastEnabledPage)
            .onChange(of: isEnabled) { _, newValue in
                guard newValue != configuration?.isEnabled else { return }
                viewModel.setPanelPageEnabled(pageType, isEnabled: newValue)
            }
        } footer: {
            if isLastEnabledPage {
                Text(String(localized: "panel.settings.page.lastEnabled.footer"))
            } else if !viewModel.canEditActivePreset {
                Text(String(localized: "settings.playerControls.duplicateToEdit"))
            }
        }
    }

    // MARK: - Info Elements Section

    private var infoElementsSection: some View {
        Section {
            Toggle(
                String(localized: "panel.settings.info.showStatsRow"),
                isOn: $showStatsRow
            )
            .onChange(of: showStatsRow) { _, newValue in
                guard newValue != infoSettings.effectiveShowStatsRow else { return }
                viewModel.updatePanelInfoSettingsSync { $0.showStatsRow = newValue }
            }

            Toggle(
                String(localized: "panel.settings.info.showChannelRow"),
                isOn: $showChannelRow
            )
            .onChange(of: showChannelRow) { _, newValue in
                guard newValue != infoSettings.effectiveShowChannelRow else { return }
                viewModel.updatePanelInfoSettingsSync { $0.showChannelRow = newValue }
            }

            Toggle(
                String(localized: "panel.settings.info.showDescription"),
                isOn: $showDescription
            )
            .onChange(of: showDescription) { _, newValue in
                guard newValue != infoSettings.effectiveShowDescription else { return }
                viewModel.updatePanelInfoSettingsSync { $0.showDescription = newValue }
            }
        } header: {
            Text(String(localized: "panel.settings.elements.header"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    // MARK: - Helpers

    private var infoSettings: InfoPageSettings {
        configuration?.infoSettings ?? InfoPageSettings()
    }

    private func syncLocalState() {
        isEnabled = configuration?.isEnabled ?? true
        let info = infoSettings
        showDescription = info.effectiveShowDescription
        showStatsRow = info.effectiveShowStatsRow
        showChannelRow = info.effectiveShowChannelRow
    }
}

#endif
