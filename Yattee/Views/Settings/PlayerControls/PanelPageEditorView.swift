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
    /// Whether the panel list configures inline sections (iPhone, or a
    /// foldable iPhone outside the corner layout) rather than pages.
    let usesSections: Bool

    // Local state for immediate UI updates
    @State private var isEnabled: Bool = true
    @State private var showDescription: Bool = true
    @State private var descriptionExpandedByDefault: Bool = false
    @State private var descriptionCollapsedLines: Int = InfoPageSettings.defaultDescriptionCollapsedLines
    @State private var showStatsRow: Bool = true
    @State private var showChannelRow: Bool = true
    @State private var showAvatars: Bool = true
    @State private var commentsPillMode: CommentsPillMode = .pill
    @State private var showRelatedThumbnails: Bool = true
    @State private var relatedExpandedByDefault: Bool = true
    @State private var showChapterThumbnails: Bool = true
    @State private var chaptersExpandedByDefault: Bool = true
    @State private var showHistory: Bool = true
    @State private var showNowPlaying: Bool = false

    private var configuration: PanelPageConfiguration? {
        viewModel.panelSettings.configuration(for: pageType)
    }

    /// The pinned page (info) is always first and enabled: no toggle.
    private var isPinnedPage: Bool {
        pageType == PanelSettings.pinnedPageType
    }

    /// Comments on an inline-sections host only show as the pill, whose
    /// mode includes off: no separate toggle.
    private var hasEnabledToggle: Bool {
        !isPinnedPage && !(usesSections && pageType == .comments)
    }

    var body: some View {
        Form {
            if hasEnabledToggle {
                enabledSection
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
            .disabled(!viewModel.canEditActivePreset)
            .onChange(of: isEnabled) { _, newValue in
                guard newValue != configuration?.isEnabled else { return }
                viewModel.setPanelPageEnabled(pageType, isEnabled: newValue)
            }
        } footer: {
            if !viewModel.canEditActivePreset {
                Text(String(localized: "settings.playerControls.duplicateToEdit"))
            }
        }
    }

    // MARK: - Info Elements Section

    @ViewBuilder
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

        if Self.hasInlineSections, showDescription {
            descriptionSection
        }
    }

    /// Collapse behavior of the description on inline-sections hosts (iPhone,
    /// iPad portrait), where sections below it clamp it to a few lines.
    private var descriptionSection: some View {
        Section {
            Toggle(
                String(localized: "panel.settings.section.expandedByDefault"),
                isOn: $descriptionExpandedByDefault
            )
            .onChange(of: descriptionExpandedByDefault) { _, newValue in
                guard newValue != infoSettings.effectiveDescriptionExpandedByDefault else { return }
                viewModel.updatePanelInfoSettingsSync { $0.descriptionExpandedByDefault = newValue }
            }

            Stepper(
                value: $descriptionCollapsedLines,
                in: InfoPageSettings.descriptionCollapsedLinesRange
            ) {
                HStack {
                    Text(String(localized: "panel.settings.info.descriptionCollapsedLines"))
                    Spacer()
                    Text("\(descriptionCollapsedLines)")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: descriptionCollapsedLines) { _, newValue in
                guard newValue != infoSettings.effectiveDescriptionCollapsedLines else { return }
                viewModel.updatePanelInfoSettingsSync { $0.descriptionCollapsedLines = newValue }
            }
        } header: {
            Text(String(localized: "panel.settings.info.description.header"))
        } footer: {
            Text(String(localized: "panel.settings.info.description.footer"))
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    // MARK: - Comments Elements Section

    @ViewBuilder
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
        } header: {
            Text(String(localized: "panel.settings.elements.header"))
        } footer: {
            if !hasEnabledToggle, !viewModel.canEditActivePreset {
                Text(String(localized: "settings.playerControls.duplicateToEdit"))
            }
        }
        .disabled(!viewModel.canEditActivePreset)

        Section {
            Picker(
                String(localized: "panel.settings.comments.pillMode"),
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
        } footer: {
            Text(String(localized: "panel.settings.comments.pillMode.footer"))
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

            if Self.hasInlineSections {
                Toggle(
                    String(localized: "panel.settings.section.expandedByDefault"),
                    isOn: $relatedExpandedByDefault
                )
                .onChange(of: relatedExpandedByDefault) { _, newValue in
                    guard newValue != relatedSettings.effectiveExpandedByDefault else { return }
                    viewModel.updatePanelRelatedSettingsSync { $0.expandedByDefault = newValue }
                }
            }
        } header: {
            Text(String(localized: "panel.settings.elements.header"))
        } footer: {
            if Self.hasInlineSections {
                Text(String(localized: "panel.settings.section.expandedByDefault.footer"))
            }
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

            if Self.hasInlineSections {
                Toggle(
                    String(localized: "panel.settings.section.expandedByDefault"),
                    isOn: $chaptersExpandedByDefault
                )
                .onChange(of: chaptersExpandedByDefault) { _, newValue in
                    guard newValue != chaptersSettings.effectiveExpandedByDefault else { return }
                    viewModel.updatePanelChaptersSettingsSync { $0.expandedByDefault = newValue }
                }
            }
        } header: {
            Text(String(localized: "panel.settings.elements.header"))
        } footer: {
            if Self.hasInlineSections {
                Text(String(localized: "panel.settings.section.expandedByDefault.footer"))
            }
        }
        .disabled(!viewModel.canEditActivePreset)
    }

    /// Chapters and related render as collapsible inline sections on iOS
    /// (iPhone everywhere, iPad portrait); macOS always uses pages.
    private static var hasInlineSections: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
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

            Toggle(
                String(localized: "panel.settings.queue.showNowPlaying"),
                isOn: $showNowPlaying
            )
            .onChange(of: showNowPlaying) { _, newValue in
                guard newValue != queueSettings.effectiveShowNowPlaying else { return }
                viewModel.updatePanelQueueSettingsSync { $0.showNowPlaying = newValue }
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
        let info = infoSettings
        showDescription = info.effectiveShowDescription
        descriptionExpandedByDefault = info.effectiveDescriptionExpandedByDefault
        descriptionCollapsedLines = info.effectiveDescriptionCollapsedLines
        showStatsRow = info.effectiveShowStatsRow
        showChannelRow = info.effectiveShowChannelRow
        showAvatars = commentsSettings.effectiveShowAvatars
        commentsPillMode = commentsSettings.effectivePillMode
        showRelatedThumbnails = relatedSettings.effectiveShowThumbnails
        relatedExpandedByDefault = relatedSettings.effectiveExpandedByDefault
        showChapterThumbnails = chaptersSettings.effectiveShowThumbnails
        chaptersExpandedByDefault = chaptersSettings.effectiveExpandedByDefault
        showHistory = queueSettings.effectiveShowHistory
        showNowPlaying = queueSettings.effectiveShowNowPlaying
    }
}

#endif
