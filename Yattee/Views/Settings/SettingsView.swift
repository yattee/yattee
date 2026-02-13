//
//  SettingsView.swift
//  Yattee
//
//  Main settings view.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    var showCloseButton: Bool = true

    #if os(macOS)
    @State private var selectedSection: SettingsSection? = .sources
    #endif

    var body: some View {
        #if os(macOS)
        macOSSettings
            .frame(minWidth: 600, minHeight: 400)
        #else
        iOSSettings
        #endif
    }

    // MARK: - macOS Settings

    #if os(macOS)
    private var macOSSettings: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if appEnvironment != nil {
                Group {
                    switch selectedSection {
                    case .sources:
                        SourcesListView()
                    case .appearance:
                        AppearanceSettingsView()
                    case .layoutNavigation:
                        LayoutNavigationSettingsView()
                    case .playback:
                        PlaybackSettingsView()
                    case .notifications:
                        NotificationSettingsView()
                    case .downloads:
                        DownloadSettingsView()
                    case .privacy:
                        PrivacySettingsView()
                    case .youtubeEnhancements:
                        YouTubeEnhancementsSettingsView()
                    case .advanced:
                        AdvancedSettingsView()
                    case .about:
                        AboutView()
                    case .none:
                        Text(String(localized: "settings.placeholder.selectSection"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .toolbar {
            if showCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label(String(localized: "common.close"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
    #endif

    // MARK: - iOS/tvOS Settings

    #if os(iOS) || os(tvOS)
    private var iOSSettings: some View {
        NavigationStack {
            List {
                if let appEnvironment {
                    Section {
                    NavigationLink {
                        SourcesListView()
                    } label: {
                        HStack {
                            Label(String(localized: "sources.title"), systemImage: "server.rack")
                            Spacer()
                            if appEnvironment.mediaSourcesManager.hasSourcesNeedingPassword {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.row.sources")
                    }

                    Section {
                        NavigationLink {
                            iCloudSettingsView()
                        } label: {
                            HStack {
                                Label(String(localized: "settings.icloud.title"), systemImage: "icloud")
                                #if DEBUG
                                Spacer()
                                Text(String(localized: "settings.icloud.dev.badge"))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange, in: Capsule())
                                #endif
                            }
                        }

                        NavigationLink {
                            AppearanceSettingsView()
                        } label: {
                            Label(String(localized: "settings.appearance.sectionTitle"), systemImage: "paintbrush")
                        }

                        NavigationLink {
                            LayoutNavigationSettingsView()
                        } label: {
                            Label(String(localized: "settings.layoutNavigation.title"), systemImage: "hand.tap")
                        }

                        NavigationLink {
                            PlaybackSettingsView()
                        } label: {
                            Label(String(localized: "settings.playback.sectionTitle"), systemImage: "play.circle")
                        }

                        #if os(iOS)
                        NavigationLink {
                            PlayerControlsSettingsView()
                        } label: {
                            Label(String(localized: "settings.playerControls.title"), systemImage: "slider.horizontal.below.rectangle")
                        }

                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            Label(String(localized: "settings.notifications.title"), systemImage: "bell.badge")
                        }

                        NavigationLink {
                            DownloadSettingsView()
                        } label: {
                            Label(String(localized: "settings.downloads.title"), systemImage: "arrow.down.circle")
                        }
                        #endif

                        NavigationLink {
                            PrivacySettingsView()
                        } label: {
                            Label(String(localized: "settings.privacy.title"), systemImage: "hand.raised")
                        }

                        NavigationLink {
                            AdvancedSettingsView()
                        } label: {
                            Label(String(localized: "settings.advanced.title"), systemImage: "gearshape.2")
                        }
                    }

                    if appEnvironment.instancesManager.enabledInstances.contains(where: \.isYouTubeInstance) {
                        Section {
                            NavigationLink {
                                YouTubeEnhancementsSettingsView()
                            } label: {
                                Label(String(localized: "settings.youtubeEnhancements.title"), systemImage: "play.rectangle")
                            }
                        }
                    }

                    Section {
                        NavigationLink {
                            AboutView()
                        } label: {
                            Label(String(localized: "settings.about.title"), systemImage: "info.circle")
                        }
                    }

                    Section {
                        VStack(spacing: 4) {
                            Text(verbatim: "Yattee")
                                .font(.headline)
                            Text("\(appVersion) (\(buildNumber))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showCloseButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .cancel) {
                            dismiss()
                        } label: {
                            Label(String(localized: "common.close"), systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("settings.doneButton")
                    }
                }
            }
            .accessibilityIdentifier("settings.view")
        }
    }
    #endif

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}

// MARK: - Settings Sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case sources
    case appearance
    case layoutNavigation
    case playback
    case notifications
    case downloads
    case privacy
    case youtubeEnhancements
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sources: return String(localized: "sources.title")
        case .appearance: return String(localized: "settings.appearance.sectionTitle")
        case .layoutNavigation: return String(localized: "settings.layoutNavigation.title")
        case .playback: return String(localized: "settings.playback.sectionTitle")
        case .notifications: return String(localized: "settings.notifications.title")
        case .downloads: return String(localized: "settings.downloads.title")
        case .privacy: return String(localized: "settings.privacy.title")
        case .youtubeEnhancements: return String(localized: "settings.youtubeEnhancements.title")
        case .advanced: return String(localized: "settings.advanced.title")
        case .about: return String(localized: "settings.about.title")
        }
    }

    var icon: String {
        switch self {
        case .sources: return "server.rack"
        case .appearance: return "paintbrush"
        case .layoutNavigation: return "hand.tap"
        case .playback: return "play.circle"
        case .notifications: return "bell.badge"
        case .downloads: return "arrow.down.circle"
        case .privacy: return "hand.raised"
        case .youtubeEnhancements: return "play.rectangle"
        case .advanced: return "gearshape.2"
        case .about: return "info.circle"
        }
    }
}

#Preview {
    SettingsView()
        .appEnvironment(.preview)
}
