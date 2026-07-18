//
//  DeveloperSettingsView.swift
//  Yattee
//
//  Developer-focused settings for logging, debugging, and testing.
//

import SwiftUI

struct DeveloperSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Bindable private var loggingService = LoggingService.shared
    @State private var loggingEnabled = LoggingService.shared.isEnabled

    // Data management state
    @State private var showingDeduplicateConfirmation = false
    @State private var deduplicationResult: DataManager.DeduplicationResult?
    @State private var showingDeduplicationResult = false
    @State private var showingResetiCloudConfirmation = false
    @State private var showingResetiCloudComplete = false

    var body: some View {
        SettingsFormContainer {
            loggingSection
            if loggingEnabled {
                verboseLoggingSection
            }
            debugSection
            testingSection
            dataSection
        }
        .navigationTitle(String(localized: "settings.developer.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            String(localized: "settings.advanced.data.removeDuplicates.title"),
            isPresented: $showingDeduplicateConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.advanced.data.removeDuplicates.action"), role: .destructive) {
                deduplicateData()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.advanced.data.removeDuplicates.message"))
        }
        .presentationCompactAdaptation(.sheet)
        .alert(
            String(localized: "settings.advanced.data.deduplicationComplete"),
            isPresented: $showingDeduplicationResult
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            if let result = deduplicationResult {
                if result.totalRemoved > 0 {
                    Text(result.summary)
                } else {
                    Text(String(localized: "settings.advanced.data.noDuplicates"))
                }
            }
        }
        .confirmationDialog(
            String(localized: "settings.advanced.data.resetICloud.title"),
            isPresented: $showingResetiCloudConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.advanced.data.resetICloud.action"), role: .destructive) {
                resetiCloudData()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.advanced.data.resetICloud.message"))
        }
        .presentationCompactAdaptation(.sheet)
        .alert(
            String(localized: "settings.advanced.data.iCloudReset"),
            isPresented: $showingResetiCloudComplete
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.advanced.data.iCloudResetMessage"))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var loggingSection: some View {
        SettingsFormSection("settings.advanced.logging.sectionTitle", footer: "settings.advanced.logging.footer") {
            Toggle(isOn: $loggingEnabled) {
                Label(String(localized: "settings.advanced.logging.enable"), systemImage: "doc.text")
            }
            .onChange(of: loggingEnabled) { _, newValue in
                loggingService.isEnabled = newValue
            }

            if loggingEnabled {
                #if os(tvOS)
                NavigationLink {
                    LogViewerView()
                } label: {
                    HStack {
                        Label(String(localized: "settings.advanced.logging.viewLogs"), systemImage: "list.bullet.rectangle")
                        Spacer()
                        Text("\(loggingService.entries.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                #else
                SettingsNavigationRow(
                    "settings.advanced.logging.viewLogs",
                    systemImage: "list.bullet.rectangle",
                    trailing: { Text("\(loggingService.entries.count)") }
                ) {
                    LogViewerView()
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private var verboseLoggingSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            SettingsFormSection("settings.advanced.verboseLogging.sectionTitle") {
                Toggle(isOn: Binding(
                    get: { settingsManager.verboseMPVLogging },
                    set: { settingsManager.verboseMPVLogging = $0 }
                )) {
                    Label(String(localized: "settings.advanced.debug.verboseMPV"), systemImage: "doc.text.magnifyingglass")
                }

                Toggle(isOn: Binding(
                    get: { settingsManager.verboseRemoteControlLogging },
                    set: { settingsManager.verboseRemoteControlLogging = $0 }
                )) {
                    Label(String(localized: "settings.advanced.debug.verboseRemote"), systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
    }

    @ViewBuilder
    private var debugSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            SettingsFormSection("settings.advanced.debug.sectionTitle") {
                Toggle(isOn: Binding(
                    get: { settingsManager.showPlayerAreaDebug },
                    set: { settingsManager.showPlayerAreaDebug = $0 }
                )) {
                    Label(String(localized: "settings.advanced.debug.playerAreaDebug"), systemImage: "rectangle.dashed")
                }

                #if os(iOS)
                Toggle(isOn: Binding(
                    get: { settingsManager.zoomTransitionsEnabled },
                    set: { settingsManager.zoomTransitionsEnabled = $0 }
                )) {
                    Label(String(localized: "settings.advanced.debug.zoomTransitions"), systemImage: "arrow.up.left.and.arrow.down.right")
                }
                #endif

                #if os(tvOS)
                Toggle(isOn: Binding(
                    get: { settingsManager.showTVDebugButton },
                    set: { settingsManager.showTVDebugButton = $0 }
                )) {
                    Label(String(localized: "settings.advanced.debug.showTVDebugButton"), systemImage: "ant.circle")
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private var testingSection: some View {
        #if !os(tvOS)
        notificationTestingSection
        #endif
    }

    @ViewBuilder
    private var dataSection: some View {
        SettingsFormSection("settings.advanced.data.sectionTitle", footer: "settings.advanced.data.footer") {
            HStack {
                Button {
                    showingDeduplicateConfirmation = true
                } label: {
                    Label(String(localized: "settings.advanced.data.removeDuplicates"), systemImage: "doc.on.doc")
                }
                Spacer()
            }

            HStack {
                Button(role: .destructive) {
                    showingResetiCloudConfirmation = true
                } label: {
                    Label(String(localized: "settings.advanced.data.resetICloud"), systemImage: "icloud.slash")
                }
                Spacer()
            }
        }
    }

    // MARK: - Data Actions

    private func deduplicateData() {
        guard let dataManager = appEnvironment?.dataManager else { return }
        deduplicationResult = dataManager.deduplicateAllData()
        showingDeduplicationResult = true
    }

    private func resetiCloudData() {
        guard let cloudKitSync = appEnvironment?.cloudKitSync else { return }
        Task {
            do {
                try await cloudKitSync.resetSync()
                showingResetiCloudComplete = true
            } catch {
                LoggingService.shared.logCloudKitError("Failed to reset iCloud data", error: error)
            }
        }
    }

    #if !os(tvOS)
    @ViewBuilder
    private var notificationTestingSection: some View {
        SettingsFormSection("settings.advanced.testing.notifications.sectionTitle", footer: "settings.advanced.testing.notifications.footer") {
            HStack {
                Button {
                    sendTestNotification()
                } label: {
                    Label(String(localized: "settings.advanced.testing.sendTestNotification"), systemImage: "bell.badge")
                }
                Spacer()
            }

            HStack {
                Button {
                    triggerBackgroundRefresh()
                } label: {
                    Label(String(localized: "settings.advanced.testing.triggerBackgroundRefresh"), systemImage: "arrow.clockwise")
                }
                Spacer()
            }
        }
    }

    private func sendTestNotification() {
        Task {
            await appEnvironment?.notificationManager.sendTestNotification()
        }
    }

    private func triggerBackgroundRefresh() {
        guard let appEnvironment else { return }
        Task {
            await appEnvironment.notificationManager.triggerBackgroundRefresh(using: appEnvironment)
        }
    }
    #endif

}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeveloperSettingsView()
    }
}
