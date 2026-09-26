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
    @State private var wideLayoutSide: FloatingPanelSide = .right
    @State private var showPageBarLabels: Bool = true

    /// Corner layout exists on iPad and macOS only.
    static var supportsCornerLayout: Bool {
        #if os(macOS)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    /// iPhone has no page bar: the list configures inline sections instead.
    private var usesSections: Bool { PanelSettings.isSectionsOnlyDevice }

    var body: some View {
        List {
            if Self.supportsCornerLayout {
                layoutSection
            }
            visibilitySection
            if !usesSections {
                pageBarSection
            }
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
            PanelLayoutSchematic(mode: layoutMode, side: wideLayoutSide)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)

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

            if layoutMode == .stacked {
                Picker(
                    String(localized: "panel.settings.side"),
                    selection: $wideLayoutSide
                ) {
                    ForEach(FloatingPanelSide.allCases, id: \.self) { side in
                        Text(side.displayName).tag(side)
                    }
                }
                .disabled(!viewModel.canEditActivePreset)
                .onChange(of: wideLayoutSide) { _, newValue in
                    guard newValue != viewModel.panelWideLayoutSide else { return }
                    viewModel.syncPanelWideLayoutSide(newValue)
                }
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

    // MARK: - Page Bar Section

    private var pageBarSection: some View {
        Section {
            Toggle(
                String(localized: "panel.settings.pageBarLabels"),
                isOn: $showPageBarLabels
            )
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: showPageBarLabels) { _, newValue in
                guard newValue != viewModel.panelShowPageBarLabels else { return }
                viewModel.syncPanelShowPageBarLabels(newValue)
            }
        } footer: {
            Text(String(localized: "panel.settings.pageBarLabels.footer"))
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
            Text(usesSections
                ? String(localized: "panel.settings.sections.header")
                : String(localized: "panel.settings.pages.header"))
        } footer: {
            if viewModel.canEditActivePreset {
                Text(usesSections
                    ? String(localized: "panel.settings.sections.footer")
                    : String(localized: "panel.settings.pages.footer"))
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
                if page.pageType.isRecentlyAdded {
                    Text(String(localized: "common.badge.new"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.tint))
                }
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
        wideLayoutSide = viewModel.panelWideLayoutSide
        showPageBarLabels = viewModel.panelShowPageBarLabels
    }
}

// MARK: - Layout Schematic

/// Small diagram of the player window for the layout mode picker: the video
/// area plus where the details panel regions sit in each mode.
private struct PanelLayoutSchematic: View {
    let mode: PanelLayoutMode
    /// Panel side in the standard layout; the corner column is always right.
    let side: FloatingPanelSide

    private let cornerRadius: CGFloat = 4

    var body: some View {
        HStack(spacing: 3) {
            if mode == .stacked && side == .left {
                panelBlock
                    .frame(width: 44)
            }

            if mode == .corner {
                VStack(spacing: 3) {
                    videoBlock
                    panelBlock
                        .frame(height: 26)
                }
            } else {
                videoBlock
            }

            if mode == .corner || side == .right {
                panelBlock
                    .frame(width: 44)
            }
        }
        .padding(6)
        .frame(width: 180, height: 110)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.4))
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.25), value: side)
    }

    private var videoBlock: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.secondary)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.background)
            }
    }

    private var panelBlock: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .overlay {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(.secondary.opacity(0.5))
                            .frame(height: 3)
                    }
                }
                .padding(6)
            }
    }
}

#endif
