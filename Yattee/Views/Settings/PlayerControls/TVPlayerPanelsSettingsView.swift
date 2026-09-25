//
//  TVPlayerPanelsSettingsView.swift
//  Yattee
//
//  Minimal tvOS settings for the player details panel pages. Edits the
//  active tvOS preset via the shared layout service; CloudKit preset sync is
//  device-class filtered, so tvOS panels cannot be configured from iOS/macOS.
//

#if os(tvOS)
import SwiftUI

struct TVPlayerPanelsSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var viewModel: PlayerControlsSettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TVPlayerPanelsContent(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil, let appEnvironment {
                let vm = PlayerControlsSettingsViewModel(
                    layoutService: appEnvironment.playerControlsLayoutService,
                    settingsManager: appEnvironment.settingsManager
                )
                viewModel = vm
                await vm.loadPresets()
            }
        }
    }
}

// MARK: - Content

private struct TVPlayerPanelsContent: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    /// Pages offered on tvOS.
    private var tvOSPages: [PanelPageConfiguration] {
        viewModel.panelPages
    }

    var body: some View {
        List {
            presetSection
            pagesSection
        }
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        Section {
            LabeledContent(
                String(localized: "settings.playerControls.activePreset"),
                value: viewModel.activePreset?.name ?? ""
            )

            if !viewModel.canEditActivePreset {
                Button {
                    Task { await duplicateActivePreset() }
                } label: {
                    Label(
                        String(localized: "panel.settings.duplicatePreset"),
                        systemImage: "doc.on.doc"
                    )
                }
            }
        } footer: {
            if !viewModel.canEditActivePreset {
                Text(String(localized: "settings.playerControls.duplicateToEdit"))
            }
        }
    }

    private func duplicateActivePreset() async {
        guard let activePreset = viewModel.activePreset else { return }

        // Pick a unique name for the copy.
        let existingNames = Set(viewModel.presets.map(\.name))
        let base = "\(activePreset.name) Copy"
        var name = base
        var counter = 2
        while existingNames.contains(name) {
            name = "\(base) \(counter)"
            counter += 1
        }

        await viewModel.createPreset(name: name, basedOn: activePreset)
    }

    // MARK: - Pages Section

    private var pagesSection: some View {
        Section {
            ForEach(tvOSPages) { page in
                NavigationLink {
                    TVPanelPageEditorView(pageType: page.pageType, viewModel: viewModel)
                } label: {
                    HStack {
                        Label(page.pageType.displayName, systemImage: page.pageType.systemImage)
                        Spacer()
                        Text(page.isEnabled
                            ? String(localized: "common.on")
                            : String(localized: "common.off"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(String(localized: "panel.settings.pages.header"))
        } footer: {
            Text(String(localized: "panel.settings.pages.footer"))
        }
    }
}

// MARK: - Page Editor

private struct TVPanelPageEditorView: View {
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

    /// Pages as displayed in the tvOS list.
    private var displayedPages: [PanelPageConfiguration] {
        viewModel.panelPages
    }

    private var displayedIndex: Int? {
        displayedPages.firstIndex { $0.pageType == pageType }
    }

    var body: some View {
        List {
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

                Button {
                    move(up: true)
                } label: {
                    Label(String(localized: "panel.settings.moveUp"), systemImage: "arrow.up")
                }
                .disabled(!viewModel.canEditActivePreset || displayedIndex == 0)

                Button {
                    move(up: false)
                } label: {
                    Label(String(localized: "panel.settings.moveDown"), systemImage: "arrow.down")
                }
                .disabled(!viewModel.canEditActivePreset || displayedIndex == displayedPages.count - 1)
            } footer: {
                if isLastEnabledPage {
                    Text(String(localized: "panel.settings.page.lastEnabled.footer"))
                } else if !viewModel.canEditActivePreset {
                    Text(String(localized: "settings.playerControls.duplicateToEdit"))
                }
            }

            if pageType == .info {
                infoElementsSection
            }
        }
        .navigationTitle(pageType.displayName)
        .onAppear {
            syncLocalState()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            syncLocalState()
        }
    }

    // MARK: - Reordering

    /// Moves this page past its displayed neighbor. Indices are mapped back
    /// to the full pages list, which may contain pages the tvOS UI hides.
    private func move(up: Bool) {
        let displayed = displayedPages
        guard let index = displayed.firstIndex(where: { $0.pageType == pageType }) else { return }
        let neighborIndex = up ? index - 1 : index + 1
        guard displayed.indices.contains(neighborIndex) else { return }

        let allPages = viewModel.panelPages
        guard let source = allPages.firstIndex(where: { $0.pageType == pageType }),
              let target = allPages.firstIndex(where: { $0.pageType == displayed[neighborIndex].pageType })
        else { return }

        viewModel.movePanelPages(
            fromOffsets: IndexSet(integer: source),
            toOffset: up ? target : target + 1
        )
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
