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
        SettingsFormContainer {
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
            SettingsFormSection(footer: "settings.privacy.incognito.footer") {
                Toggle(isOn: Bindable(settingsManager).incognitoModeEnabled) {
                    Label {
                        Text(String(localized: "settings.behavior.incognitoMode"))
                    } icon: {
                        #if os(macOS)
                        Image("incognito")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        #else
                        Image("incognito")
                        #endif
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            SettingsFormSection(
                "settings.behavior.historyRetention.header",
                content: {
                    Toggle(
                        String(localized: "settings.privacy.saveWatchHistory"),
                        isOn: Bindable(settingsManager).saveWatchHistory
                    )

                    PlatformMenuPicker(
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
                },
                footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "settings.behavior.historyRetention.footer"))

                        // Only while an account that has a server-side history
                        // is the selected source: that is exactly when watching
                        // something writes to two places, and the two settings
                        // above are what stop both.
                        if let name = serverHistoryAccountName {
                            Text(String(localized: "settings.privacy.history.account.footer \(name)"))
                        }
                    }
                }
            )
        }
    }

    /// The account watched videos are being mirrored to, if any.
    ///
    /// Resolved the same way the history screen decides whose history it is
    /// showing, so the note and the screen can never disagree about it.
    private var serverHistoryAccountName: String? {
        guard let appEnvironment else { return nil }

        let context = appEnvironment.dataContextValidator.effectiveContext
        let account = context.accountID.flatMap { appEnvironment.accountsManager.account(id: $0) }

        let mode = HistoryDisplayMode.resolve(
            effectiveContext: context,
            account: account,
            capabilities: account.flatMap { appEnvironment.accountsManager.capabilities(for: $0) }
        )

        guard let mirrored = mode.account else { return nil }
        return appEnvironment.dataContextValidator.displayName(for: mirrored)
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
            SettingsFormSection("settings.behavior.searchHistoryLimit.header", footer: "settings.behavior.searchHistoryLimit.footer") {
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

                PlatformMenuPicker(
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
