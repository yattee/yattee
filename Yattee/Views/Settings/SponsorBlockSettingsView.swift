//
//  SponsorBlockSettingsView.swift
//  Yattee
//
//  SponsorBlock settings with category selection.
//

import SwiftUI

struct SponsorBlockSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Form {
            if let settings = appEnvironment?.settingsManager {
                // Enable/Disable toggle
                EnableSection(settings: settings)

                // Categories section
                if settings.sponsorBlockEnabled {
                    CategoriesSection(settings: settings)
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
        .navigationTitle(String(localized: "settings.sponsorBlock.title"))
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
                String(localized: "settings.sponsorBlock.enabled"),
                isOn: $settings.sponsorBlockEnabled
            )
        } footer: {
            Text(String(localized: "settings.sponsorBlock.footer"))
        }
    }
}

// MARK: - Categories Section

private struct CategoriesSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            ForEach(SponsorBlockCategory.allCases, id: \.self) { category in
                CategoryToggleRow(
                    category: category,
                    isEnabled: settings.sponsorBlockCategories.contains(category),
                    onToggle: { enabled in
                        var categories = settings.sponsorBlockCategories
                        if enabled {
                            categories.insert(category)
                        } else {
                            categories.remove(category)
                        }
                        settings.sponsorBlockCategories = categories
                    }
                )
            }
        } header: {
            Text(String(localized: "settings.sponsorBlock.categories.header"))
        } footer: {
            Text(String(localized: "settings.sponsorBlock.categories.footer"))
        }
    }
}

// MARK: - Advanced Section

private struct AdvancedSection: View {
    @Bindable var settings: SettingsManager
    @State private var apiURLText: String = ""

    var body: some View {
        Section {
            TextField(
                String(localized: "settings.sponsorBlock.apiURL"),
                text: $apiURLText,
                prompt: Text(SettingsManager.defaultSponsorBlockAPIURL)
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .autocorrectionDisabled()
            .onChange(of: apiURLText) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    settings.sponsorBlockAPIURL = SettingsManager.defaultSponsorBlockAPIURL
                } else {
                    settings.sponsorBlockAPIURL = trimmed
                }
            }

            if settings.sponsorBlockAPIURL != SettingsManager.defaultSponsorBlockAPIURL {
                Button(String(localized: "settings.sponsorBlock.apiURL.reset")) {
                    apiURLText = ""
                    settings.sponsorBlockAPIURL = SettingsManager.defaultSponsorBlockAPIURL
                }
            }
        } header: {
            Text(String(localized: "settings.sponsorBlock.advanced.header"))
        } footer: {
            Text(String(localized: "settings.sponsorBlock.apiURL.footer"))
        }
        .onAppear {
            let currentURL = settings.sponsorBlockAPIURL
            if currentURL != SettingsManager.defaultSponsorBlockAPIURL {
                apiURLText = currentURL
            }
        }
    }
}

// MARK: - About Section

private struct AboutSection: View {
    var body: some View {
        Section(String(localized: "settings.sponsorBlock.about.header")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.sponsorBlock.about.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://sponsor.ajay.app")!) {
                    HStack {
                        Text(String(localized: "settings.sponsorBlock.about.learnMore"))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

// MARK: - Category Toggle Row

private struct CategoryToggleRow: View {
    let category: SponsorBlockCategory
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.body)

                    Text(category.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SponsorBlockSettingsView()
    }
    .appEnvironment(.preview)
}
