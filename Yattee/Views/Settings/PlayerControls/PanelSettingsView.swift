//
//  PanelSettingsView.swift
//  Yattee
//
//  Settings editor for the player details panel pages.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct PanelSettingsView: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    // Local state for immediate UI updates
    @State private var defaultVisibility: PanelDefaultVisibility = .hidden
    @State private var layoutMode: PanelLayoutMode = .stacked

    /// Corner layout exists on iPad and macOS only.
    static var supportsCornerLayout: Bool {
        #if os(macOS)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        List {
            if Self.supportsCornerLayout {
                layoutSection
            }
            visibilitySection
            pagesSection
        }
        .navigationTitle(String(localized: "settings.playerControls.detailsPanel"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #elseif os(macOS)
        .formStyle(.grouped)
        #endif
        .opaqueSettingsFormBackground()
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif
        }
        .onAppear {
            syncLocalState()
        }
        .onChange(of: viewModel.activePreset?.id) { _, _ in
            syncLocalState()
        }
    }

    // MARK: - Layout Section

    private var layoutSection: some View {
        Section {
            Picker(
                String(localized: "panel.settings.layoutMode"),
                selection: $layoutMode
            ) {
                ForEach(PanelLayoutMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: layoutMode) { _, newValue in
                guard newValue != viewModel.panelLayoutMode else { return }
                viewModel.syncPanelLayoutMode(newValue)
            }
        } footer: {
            Text(String(localized: "panel.settings.layoutMode.footer"))
        }
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        Section {
            Picker(
                String(localized: "panel.settings.defaultVisibility"),
                selection: $defaultVisibility
            ) {
                ForEach(PanelDefaultVisibility.allCases, id: \.self) { visibility in
                    Text(visibility.displayName).tag(visibility)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: defaultVisibility) { _, newValue in
                guard newValue != viewModel.panelDefaultVisibility else { return }
                viewModel.syncPanelDefaultVisibility(newValue)
            }
        } footer: {
            Text(String(localized: "panel.settings.defaultVisibility.footer"))
        }
    }

    // MARK: - Pages Section

    private var pagesSection: some View {
        Section {
            ForEach(viewModel.panelPages) { page in
                pageRow(for: page)
            }
            .onMove { source, destination in
                viewModel.movePanelPages(fromOffsets: source, toOffset: destination)
            }
        } header: {
            Text(String(localized: "panel.settings.pages.header"))
        } footer: {
            if viewModel.canEditActivePreset {
                Text(String(localized: "panel.settings.pages.footer"))
            } else {
                Text(String(localized: "settings.playerControls.duplicateToEdit"))
            }
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    @ViewBuilder
    private func pageRow(for page: PanelPageConfiguration) -> some View {
        NavigationLink {
            PanelPageEditorView(pageType: page.pageType, viewModel: viewModel)
        } label: {
            HStack {
                Label(page.pageType.displayName, systemImage: page.pageType.systemImage)
                Spacer()
                if page.isEnabled, layoutMode == .corner, Self.supportsCornerLayout {
                    Text(page.region.displayName)
                        .foregroundStyle(.secondary)
                } else {
                    Text(page.isEnabled
                        ? String(localized: "common.on")
                        : String(localized: "common.off"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func syncLocalState() {
        defaultVisibility = viewModel.panelDefaultVisibility
        layoutMode = viewModel.panelLayoutMode
    }
}

#endif
