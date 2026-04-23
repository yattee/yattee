//
//  ProgressBarSettingsView.swift
//  Yattee
//
//  View for configuring progress bar appearance settings.
//

import SwiftUI

/// View for configuring progress bar settings.
struct ProgressBarSettingsView: View {
    @Bindable var viewModel: PlayerControlsSettingsViewModel

    @State private var playedColor: Color = .red
    @State private var showChapters: Bool = true
    @State private var showSponsorSegments: Bool = true
    @State private var categorySettings: [String: SponsorBlockCategorySettings] = [:]

    var body: some View {
        Form {
            appearanceSection
            chaptersSection
            sponsorSegmentsSection

            if showSponsorSegments {
                segmentColorsSection
            }
        }
        .navigationTitle(String(localized: "settings.playerControls.progressBar"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadSettings()
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            #if !os(tvOS)
            ColorPicker(
                String(localized: "settings.playerControls.progressBar.playedColor"),
                selection: $playedColor,
                supportsOpacity: false
            )
            .onChange(of: playedColor) { _, newValue in
                viewModel.updateProgressBarSettingsSync { $0.playedColor = CodableColor(newValue) }
            }
            .disabled(!viewModel.canEditActivePreset)
            #else
            HStack {
                Text(String(localized: "settings.playerControls.progressBar.playedColor"))
                Spacer()
                Circle()
                    .fill(playedColor)
                    .frame(width: 24, height: 24)
            }
            #endif
        } header: {
            Text(String(localized: "settings.playerControls.progressBar.appearance"))
        }
    }

    // MARK: - Chapters Section

    private var chaptersSection: some View {
        Section {
            Toggle(
                String(localized: "settings.playerControls.progressBar.showChapters"),
                isOn: $showChapters
            )
            .onChange(of: showChapters) { _, newValue in
                viewModel.updateProgressBarSettingsSync { $0.showChapters = newValue }
            }
            .disabled(!viewModel.canEditActivePreset)
        } header: {
            Text(String(localized: "settings.playerControls.progressBar.chapters"))
        } footer: {
            Text(String(localized: "settings.playerControls.progressBar.chaptersFooter"))
        }
    }

    // MARK: - Sponsor Segments Section

    private var sponsorSegmentsSection: some View {
        Section {
            Toggle(
                String(localized: "settings.playerControls.progressBar.showSponsorSegments"),
                isOn: $showSponsorSegments
            )
            .onChange(of: showSponsorSegments) { _, newValue in
                viewModel.updateProgressBarSettingsSync {
                    $0.sponsorBlockSettings.showSegments = newValue
                }
            }
            .disabled(!viewModel.canEditActivePreset)
        } header: {
            Text(String(localized: "settings.playerControls.progressBar.sponsorSegments"))
        }
    }

    // MARK: - Segment Colors Section

    private var segmentColorsSection: some View {
        Section {
            ForEach(SponsorBlockCategory.allCases, id: \.rawValue) { category in
                categoryRow(for: category)
            }
        } header: {
            Text(String(localized: "settings.playerControls.progressBar.segmentColors"))
        }
    }

    @ViewBuilder
    private func categoryRow(for category: SponsorBlockCategory) -> some View {
        let settings = categorySettings[category.rawValue]
            ?? SponsorBlockSegmentSettings.defaultCategorySettings[category.rawValue]
            ?? SponsorBlockCategorySettings()

        let isVisible = Binding<Bool>(
            get: { settings.isVisible },
            set: { newValue in
                updateCategorySettings(for: category) { $0.isVisible = newValue }
            }
        )

        let color = Binding<Color>(
            get: { settings.color.color },
            set: { newValue in
                updateCategorySettings(for: category) { $0.color = CodableColor(newValue) }
            }
        )

        HStack {
            Toggle(category.displayName, isOn: isVisible)
                .disabled(!viewModel.canEditActivePreset)

            Spacer()

            #if !os(tvOS)
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
                .disabled(!viewModel.canEditActivePreset || !settings.isVisible)
            #else
            Circle()
                .fill(color.wrappedValue)
                .frame(width: 24, height: 24)
                .opacity(settings.isVisible ? 1 : 0.4)
            #endif
        }
    }

    // MARK: - Helpers

    private func loadSettings() {
        let progressBarSettings = viewModel.progressBarSettings
        playedColor = progressBarSettings.playedColor.color
        showChapters = progressBarSettings.showChapters
        showSponsorSegments = progressBarSettings.sponsorBlockSettings.showSegments
        categorySettings = progressBarSettings.sponsorBlockSettings.categorySettings
    }

    private func updateCategorySettings(
        for category: SponsorBlockCategory,
        mutation: (inout SponsorBlockCategorySettings) -> Void
    ) {
        var settings = categorySettings[category.rawValue]
            ?? SponsorBlockSegmentSettings.defaultCategorySettings[category.rawValue]
            ?? SponsorBlockCategorySettings()

        mutation(&settings)
        categorySettings[category.rawValue] = settings

        viewModel.updateProgressBarSettingsSync {
            $0.sponsorBlockSettings = $0.sponsorBlockSettings.withUpdatedSettings(
                forKey: category.rawValue,
                settings
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProgressBarSettingsView(
            viewModel: PlayerControlsSettingsViewModel(
                layoutService: PlayerControlsLayoutService(),
                settingsManager: SettingsManager()
            )
        )
    }
}
