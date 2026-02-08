//
//  DeArrowSettingsView.swift
//  Yattee
//
//  DeArrow settings.
//

import SwiftUI

struct DeArrowSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Form {
            if let settings = appEnvironment?.settingsManager {
                // Enable/Disable toggle
                EnableSection(settings: settings)

                // Options section (only shown when enabled)
                if settings.deArrowEnabled {
                    OptionsSection(settings: settings)
                }

                // Advanced section
                AdvancedSection(settings: settings)

                // About section
                AboutSection()
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .navigationTitle(String(localized: "settings.deArrow.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Enable Section

private struct EnableSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            Toggle(
                String(localized: "settings.deArrow.enabled"),
                isOn: $settings.deArrowEnabled
            )
        } footer: {
            Text(String(localized: "settings.deArrow.footer"))
        }
    }
}

// MARK: - Options Section

private struct OptionsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section(String(localized: "settings.deArrow.options.header")) {
            Toggle(
                String(localized: "settings.deArrow.replaceTitles"),
                isOn: $settings.deArrowReplaceTitles
            )

            Toggle(
                String(localized: "settings.deArrow.replaceThumbnails"),
                isOn: $settings.deArrowReplaceThumbnails
            )
        }
    }
}

// MARK: - Advanced Section

private struct AdvancedSection: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Bindable var settings: SettingsManager
    @State private var apiURLText: String = ""
    @State private var thumbnailAPIURLText: String = ""

    var body: some View {
        Section {
            TextField(
                String(localized: "settings.deArrow.apiURL"),
                text: $apiURLText,
                prompt: Text(SettingsManager.defaultDeArrowAPIURL)
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .autocorrectionDisabled()
            .onChange(of: apiURLText) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    settings.deArrowAPIURL = SettingsManager.defaultDeArrowAPIURL
                } else {
                    settings.deArrowAPIURL = trimmed
                }
                syncAPIURLs()
            }

            if settings.deArrowAPIURL != SettingsManager.defaultDeArrowAPIURL {
                Button(String(localized: "settings.deArrow.apiURL.reset")) {
                    apiURLText = ""
                    settings.deArrowAPIURL = SettingsManager.defaultDeArrowAPIURL
                    syncAPIURLs()
                }
            }

            TextField(
                String(localized: "settings.deArrow.thumbnailAPIURL"),
                text: $thumbnailAPIURLText,
                prompt: Text(SettingsManager.defaultDeArrowThumbnailAPIURL)
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .autocorrectionDisabled()
            .onChange(of: thumbnailAPIURLText) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    settings.deArrowThumbnailAPIURL = SettingsManager.defaultDeArrowThumbnailAPIURL
                } else {
                    settings.deArrowThumbnailAPIURL = trimmed
                }
                syncAPIURLs()
            }

            if settings.deArrowThumbnailAPIURL != SettingsManager.defaultDeArrowThumbnailAPIURL {
                Button(String(localized: "settings.deArrow.thumbnailAPIURL.reset")) {
                    thumbnailAPIURLText = ""
                    settings.deArrowThumbnailAPIURL = SettingsManager.defaultDeArrowThumbnailAPIURL
                    syncAPIURLs()
                }
            }
        } header: {
            Text(String(localized: "settings.deArrow.advanced.header"))
        } footer: {
            Text(String(localized: "settings.deArrow.apiURL.footer"))
        }
        .onAppear {
            let currentAPIURL = settings.deArrowAPIURL
            if currentAPIURL != SettingsManager.defaultDeArrowAPIURL {
                apiURLText = currentAPIURL
            }

            let currentThumbnailAPIURL = settings.deArrowThumbnailAPIURL
            if currentThumbnailAPIURL != SettingsManager.defaultDeArrowThumbnailAPIURL {
                thumbnailAPIURLText = currentThumbnailAPIURL
            }
        }
    }

    private func syncAPIURLs() {
        Task {
            await appEnvironment?.deArrowBrandingProvider.syncAPIURLs()
        }
    }
}

// MARK: - About Section

private struct AboutSection: View {
    var body: some View {
        Section(String(localized: "settings.deArrow.about.header")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.deArrow.about.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://dearrow.ajay.app")!) {
                    HStack {
                        Text(String(localized: "settings.deArrow.learnMore"))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeArrowSettingsView()
    }
    .appEnvironment(.preview)
}
