//
//  YouTubeEnhancementsSettingsView.swift
//  Yattee
//
//  Settings view for YouTube-specific enhancements.
//

import SwiftUI

struct YouTubeEnhancementsSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        SettingsFormContainer {
            if let settings = appEnvironment?.settingsManager {
                SponsorBlockSection(settings: settings)
                ReturnYouTubeDislikeSection(settings: settings)
                DeArrowSection(settings: settings)
                #if !os(tvOS)
                // tvOS has no in-description link tapping or system browser,
                // so short-link resolution would have nothing to act on.
                ResolveShortLinksSection(settings: settings)
                #endif
            }
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "settings.youtubeEnhancements.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - SponsorBlock Section

private struct SponsorBlockSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection(footer: "settings.youtubeEnhancements.sponsorBlock.footer") {
            SettingsNavigationRow(
                "settings.sponsorBlock.sectionTitle",
                systemImage: "forward",
                trailing: {
                    Text(settings.sponsorBlockEnabled
                         ? String(localized: "common.enabled")
                         : String(localized: "common.disabled"))
                }
            ) {
                SponsorBlockSettingsView()
            }
        }
    }
}

// MARK: - Return YouTube Dislike Section

private struct ReturnYouTubeDislikeSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection(footer: "settings.youtubeEnhancements.returnYouTubeDislike.footer") {
            SettingsNavigationRow(
                "settings.returnYouTubeDislike.sectionTitle",
                systemImage: "hand.thumbsdown",
                trailing: {
                    Text(settings.returnYouTubeDislikeEnabled
                         ? String(localized: "common.enabled")
                         : String(localized: "common.disabled"))
                }
            ) {
                ReturnYouTubeDislikeSettingsView()
            }
        }
    }
}

// MARK: - DeArrow Section

private struct DeArrowSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection(footer: "settings.youtubeEnhancements.deArrow.footer") {
            SettingsNavigationRow(
                "settings.deArrow.sectionTitle",
                systemImage: "textformat",
                trailing: {
                    Text(settings.deArrowEnabled
                         ? String(localized: "common.enabled")
                         : String(localized: "common.disabled"))
                }
            ) {
                DeArrowSettingsView()
            }
        }
    }
}

// MARK: - Resolve Short Links Section

private struct ResolveShortLinksSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        SettingsFormSection(footer: "settings.youtubeEnhancements.resolveShortLinks.footer") {
            Toggle(
                String(localized: "settings.resolveShortLinks.title"),
                isOn: $settings.resolveShortLinksEnabled
            )
        }
    }
}

#Preview {
    NavigationStack {
        YouTubeEnhancementsSettingsView()
    }
    .appEnvironment(.preview)
}
