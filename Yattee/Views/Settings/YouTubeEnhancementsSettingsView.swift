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
        Form {
            if let settings = appEnvironment?.settingsManager {
                SponsorBlockSection(settings: settings)
                ReturnYouTubeDislikeSection(settings: settings)
                DeArrowSection(settings: settings)
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
        Section {
            NavigationLink {
                SponsorBlockSettingsView()
            } label: {
                HStack {
                    Label(String(localized: "settings.sponsorBlock.sectionTitle"), systemImage: "forward")
                    Spacer()
                    Text(settings.sponsorBlockEnabled
                         ? String(localized: "common.enabled")
                         : String(localized: "common.disabled"))
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(String(localized: "settings.youtubeEnhancements.sponsorBlock.footer"))
        }
    }
}

// MARK: - Return YouTube Dislike Section

private struct ReturnYouTubeDislikeSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            NavigationLink {
                ReturnYouTubeDislikeSettingsView()
            } label: {
                HStack {
                    Label(String(localized: "settings.returnYouTubeDislike.sectionTitle"), systemImage: "hand.thumbsdown")
                    Spacer()
                    Text(settings.returnYouTubeDislikeEnabled
                         ? String(localized: "common.enabled")
                         : String(localized: "common.disabled"))
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(String(localized: "settings.youtubeEnhancements.returnYouTubeDislike.footer"))
        }
    }
}

// MARK: - DeArrow Section

private struct DeArrowSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            NavigationLink {
                DeArrowSettingsView()
            } label: {
                HStack {
                    Label(String(localized: "settings.deArrow.sectionTitle"), systemImage: "textformat")
                    Spacer()
                    Text(settings.deArrowEnabled
                         ? String(localized: "common.enabled")
                         : String(localized: "common.disabled"))
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(String(localized: "settings.youtubeEnhancements.deArrow.footer"))
        }
    }
}

#Preview {
    NavigationStack {
        YouTubeEnhancementsSettingsView()
    }
    .appEnvironment(.preview)
}
