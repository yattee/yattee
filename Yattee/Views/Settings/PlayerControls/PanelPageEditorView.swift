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
    @State private var region: PanelRegion = .primary
    @State private var showDescription: Bool = true
    @State private var showStatsRow: Bool = true
    @State private var showChannelRow: Bool = true
    @State private var showAvatars: Bool = true
    @State private var commentsPillMode: CommentsPillMode = .pill
    @State private var showRelatedThumbnails: Bool = true
    @State private var showChapterThumbnails: Bool = true
    @State private var showHistory: Bool = true

    private var configuration: PanelPageConfiguration? {
        viewModel.panelSettings.configuration(for: pageType)
    }

    /// Whether this is the only enabled page; the last one cannot be disabled.
    private var isLastEnabledPage: Bool {
        isEnabled && viewModel.enabledPanelPageCount <= 1
    }

    /// iPhone configures inline sections rather than pages.
    private var usesSections: Bool { PanelSettings.isSectionsOnlyDevice }

    var body: some View {
        Form {
            enabledSection

            if PanelSettingsView.supportsCornerLayout, viewModel.panelLayoutMode == .corner {
                regionSection
            }

            switch pageType {
            case .info:
                infoElementsSection
            case .comments:
                commentsElementsSection
            case .related:
                relatedElementsSection
            case .chapters:
                chaptersElementsSection
            case .queue:
                queueElementsSection
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
                usesSections
                    ? String(localized: "panel.settings.section.enabled")
                    : String(localized: "panel.settings.page.enabled"),
                isOn: $isEnabled
            )
            .disabled(!viewModel.canEditActivePreset || isLastEnabledPage)
            .onChange(of: isEnabled) { _, newValue in
                guard newValue != configuration?.isEnabled else { return }
                viewModel.setPanelPageEnabled(pageType, isEnabled: newValue)
            }
        } footer: {
            if isLastEnabledPage {
                Text(usesSections
                    ? String(localized: "panel.settings.section.lastEnabled.footer")
                    : String(localized: "panel.settings.page.lastEnabled.footer"))
            } else if !viewModel.canEditActivePreset {
                Text(String(localized: "settings.playerControls.duplicateToEdit"))
            }
        }
    }

    // MARK: - Region Section (corner layout)

    private var regionSection: some View {
        Section {
            Picker(
                String(localized: "panel.settings.page.region"),
                selection: $region
            ) {
                ForEach(PanelRegion.allCases, id: \.self) { region in
                    Text(region.displayName).tag(region)
                }
            }
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: region) { _, newValue in
                guard newValue != configuration?.region else { return }
                viewModel.setPanelPageRegion(newValue, for: pageType)
            }
        } footer: {
            Text(String(localized: "panel.settings.page.region.footer"))
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

    // MARK: - Comments Elements Section

    private var commentsElementsSection: some View {
        Section {
            Toggle(
                String(localized: "panel.settings.comments.showAvatars"),
                isOn: $showAvatars
            )
            .onChange(of: showAvatars) { _, newValue in
                guard newValue != commentsSettings.effectiveShowAvatars else { return }
                viewModel.updatePanelCommentsSettingsSync { $0.showAvatars = newValue }
            }

            Picker(
                String(localized: "commentsPill.mode.title"),
                selection: $commentsPillMode
            ) {
                ForEach(CommentsPillMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .onChange(of: commentsPillMode) { _, newValue in
                guard newValue != commentsSettings.effectivePillMode else { return }
                viewModel.updatePanelCommentsSettingsSync { $0.pillMode = newValue }
            }
        } header: {
            Text(String(localized: "panel.settings.elements.header"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    // MARK: - Related Elements Section

    private var relatedElementsSection: some View {
        Section {
            Toggle(
                String(localized: "panel.settings.showThumbnails"),
                isOn: $showRelatedThumbnails
            )
            .onChange(of: showRelatedThumbnails) { _, newValue in
                guard newValue != relatedSettings.effectiveShowThumbnails else { return }
                viewModel.updatePanelRelatedSettingsSync { $0.showThumbnails = newValue }
            }
        } header: {
            Text(String(localized: "panel.settings.elements.header"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    // MARK: - Chapters Elements Section

    private var chaptersElementsSection: some View {
        Section {
            Toggle(
                String(localized: "panel.settings.showThumbnails"),
                isOn: $showChapterThumbnails
            )
            .onChange(of: showChapterThumbnails) { _, newValue in
                guard newValue != chaptersSettings.effectiveShowThumbnails else { return }
                viewModel.updatePanelChaptersSettingsSync { $0.showThumbnails = newValue }
            }
        } header: {
            Text(String(localized: "panel.settings.elements.header"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    // MARK: - Queue Elements Section

    private var queueElementsSection: some View {
        Section {
            Toggle(
                String(localized: "panel.settings.queue.showHistory"),
                isOn: $showHistory
            )
            .onChange(of: showHistory) { _, newValue in
                guard newValue != queueSettings.effectiveShowHistory else { return }
                viewModel.updatePanelQueueSettingsSync { $0.showHistory = newValue }
            }
        } header: {
            Text(String(localized: "panel.settings.elements.header"))
        } footer: {
            Text(String(localized: "panel.settings.queue.showHistory.footer"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    // MARK: - Helpers

    private var infoSettings: InfoPageSettings {
        configuration?.infoSettings ?? InfoPageSettings()
    }

    private var commentsSettings: CommentsPageSettings {
        configuration?.commentsSettings ?? CommentsPageSettings()
    }

    private var relatedSettings: RelatedPageSettings {
        configuration?.relatedSettings ?? RelatedPageSettings()
    }

    private var chaptersSettings: ChaptersPageSettings {
        configuration?.chaptersSettings ?? ChaptersPageSettings()
    }

    private var queueSettings: QueuePageSettings {
        configuration?.queueSettings ?? QueuePageSettings()
    }

    private func syncLocalState() {
        isEnabled = configuration?.isEnabled ?? true
        region = configuration?.region ?? .primary
        let info = infoSettings
        showDescription = info.effectiveShowDescription
        showStatsRow = info.effectiveShowStatsRow
        showChannelRow = info.effectiveShowChannelRow
        showAvatars = commentsSettings.effectiveShowAvatars
        commentsPillMode = commentsSettings.effectivePillMode
        showRelatedThumbnails = relatedSettings.effectiveShowThumbnails
        showChapterThumbnails = chaptersSettings.effectiveShowThumbnails
        showHistory = queueSettings.effectiveShowHistory
    }
}

#endif
