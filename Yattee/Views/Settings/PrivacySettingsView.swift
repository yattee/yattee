//
//  PrivacySettingsView.swift
//  Yattee
//
//  Privacy settings including incognito mode and history retention.
//

import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    private let historyRetentionOptions: [Int] = [0, 30, 60, 90, 180, 365]
    private let searchHistoryLimitOptions: [Int] = [10, 15, 25, 50, 100]

    var body: some View {
        List {
            incognitoSection
            historySection
            searchSection
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "settings.privacy.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var incognitoSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            Section {
                Toggle(isOn: Bindable(settingsManager).incognitoModeEnabled) {
                    Label(
                        String(localized: "settings.behavior.incognitoMode"),
                        image: "incognito"
                    )
                }
            } footer: {
                Text(String(localized: "settings.privacy.incognito.footer"))
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            Section {
                Toggle(
                    String(localized: "settings.privacy.saveWatchHistory"),
                    isOn: Bindable(settingsManager).saveWatchHistory
                )

                Picker(
                    String(localized: "settings.behavior.historyRetention"),
                    selection: Binding(
                        get: { settingsManager.historyRetentionDays },
                        set: { settingsManager.historyRetentionDays = $0 }
                    )
                ) {
                    ForEach(historyRetentionOptions, id: \.self) { days in
                        Text(labelForHistoryRetentionDays(days))
                            .tag(days)
                    }
                }
            } header: {
                Text(String(localized: "settings.behavior.historyRetention.header"))
            } footer: {
                Text(String(localized: "settings.behavior.historyRetention.footer"))
            }
        }
    }

    private func labelForHistoryRetentionDays(_ days: Int) -> String {
        switch days {
        case 0:
            return String(localized: "settings.behavior.historyRetention.never")
        case 365:
            return String(localized: "settings.behavior.historyRetention.year")
        default:
            return String(localized: "settings.behavior.historyRetention.days \(days)")
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            Section {
                Toggle(
                    String(localized: "settings.privacy.saveRecentSearches"),
                    isOn: Bindable(settingsManager).saveRecentSearches
                )

                Toggle(
                    String(localized: "settings.privacy.saveRecentChannels"),
                    isOn: Bindable(settingsManager).saveRecentChannels
                )

                Toggle(
                    String(localized: "settings.privacy.saveRecentPlaylists"),
                    isOn: Bindable(settingsManager).saveRecentPlaylists
                )

                Picker(
                    String(localized: "settings.behavior.searchHistoryLimit"),
                    selection: Binding(
                        get: { settingsManager.searchHistoryLimit },
                        set: { settingsManager.searchHistoryLimit = $0 }
                    )
                ) {
                    ForEach(searchHistoryLimitOptions, id: \.self) { limit in
                        Text(String(localized: "settings.behavior.searchHistoryLimit.queries \(limit)"))
                            .tag(limit)
                    }
                }
            } header: {
                Text(String(localized: "settings.behavior.searchHistoryLimit.header"))
            } footer: {
                Text(String(localized: "settings.behavior.searchHistoryLimit.footer"))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PrivacySettingsView()
    }
    .appEnvironment(.preview)
}
