//
//  AdvancedSettingsView.swift
//  Yattee
//
//  Advanced settings including debugging and logging options.
//

import SwiftUI
import Nuke

struct AdvancedSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var showingClearDataConfirmation = false
    @State private var userAgentText: String = ""

    // Orphaned files state
    @State private var orphanedFilesCount: Int = 0
    @State private var orphanedFilesSize: Int64 = 0
    @State private var isScanning = false
    @State private var showingOrphanCleanupConfirmation = false
    @State private var showingOrphanCleanupResult = false
    @State private var orphanCleanupResult: (deleted: Int, freed: Int64)?

    // Storage diagnostics state
    @State private var storageDiagnostics: StorageDiagnostics?
    @State private var isScanningStorage = false

    var body: some View {
        SettingsFormContainer {
            #if SPARKLE && os(macOS)
            updatesSection
            #endif
            streamDetailsSection
            mpvSection
            #if os(tvOS)
            avSyncSection
            #endif
            settingsSection
            #if !os(tvOS)
            downloadsStorageSection
            #endif
            developerSection
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "settings.advanced.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            String(localized: "settings.advanced.data.clearCache.confirmation"),
            isPresented: $showingClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.advanced.data.clearCache"), role: .destructive) {
                clearCache()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .presentationCompactAdaptation(.sheet)
        .onAppear {
            userAgentText = settingsManager.customUserAgent
            #if !os(tvOS)
            scanForOrphanedFiles()
            #endif
        }
        #if !os(tvOS)
        .confirmationDialog(
            String(localized: "settings.advanced.storage.deleteOrphaned.title"),
            isPresented: $showingOrphanCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.advanced.storage.deleteOrphaned.action \(orphanedFilesCount)"), role: .destructive) {
                deleteOrphanedFiles()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.advanced.storage.deleteOrphaned.message \(orphanedFilesCount) \(formatBytes(orphanedFilesSize))"))
        }
        .presentationCompactAdaptation(.sheet)
        .alert(
            String(localized: "settings.advanced.storage.cleanupComplete"),
            isPresented: $showingOrphanCleanupResult
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            if let result = orphanCleanupResult {
                Text(String(localized: "settings.advanced.storage.cleanupResult \(result.deleted) \(formatBytes(result.freed))"))
            }
        }
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var settingsSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            userAgentSection(settingsManager: settingsManager)
            deviceNameSection
            feedSection(settingsManager: settingsManager)
        }
    }

    @ViewBuilder
    private func feedSection(settingsManager: SettingsManager) -> some View {
        SettingsFormSection("settings.advanced.feed.sectionTitle") {
            PlatformMenuPicker(selection: Binding(
                get: { settingsManager.feedCacheValidityMinutes },
                set: { settingsManager.feedCacheValidityMinutes = $0 }
            )) {
                ForEach(Self.feedCacheValidityOptions, id: \.minutes) { option in
                    Text(option.label).tag(option.minutes)
                }
            } label: {
                Label(String(localized: "settings.advanced.feed.cacheValidity"), systemImage: "clock")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.advanced.feed.footer"))
                if let lastCheck = settingsManager.lastBackgroundCheck {
                    Text(String(localized: "settings.advanced.feed.lastBackgroundRefresh \(lastCheck.formatted(date: .abbreviated, time: .shortened))"))
                } else {
                    Text(String(localized: "settings.advanced.feed.lastBackgroundRefresh.never"))
                }
            }
        }
    }

    @ViewBuilder
    private func userAgentSection(settingsManager: SettingsManager) -> some View {
        SettingsFormSection("settings.advanced.userAgent.sectionTitle", footer: "settings.advanced.userAgent.footer") {
            Toggle(isOn: Binding(
                get: { settingsManager.randomizeUserAgentPerRequest },
                set: {
                    settingsManager.randomizeUserAgentPerRequest = $0
                    appEnvironment?.updateUserAgent()
                }
            )) {
                Label(String(localized: "settings.advanced.userAgent.randomizePerRequest"), systemImage: "shuffle")
            }

            if !settingsManager.randomizeUserAgentPerRequest {
                TextField(
                    String(localized: "settings.advanced.userAgent.placeholder"),
                    text: $userAgentText,
                    axis: .vertical
                )
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .lineLimit(3...6)
                .onChange(of: userAgentText) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        settingsManager.customUserAgent = trimmed
                        appEnvironment?.updateUserAgent()
                    }
                }

                Button {
                    settingsManager.randomizeUserAgent()
                    userAgentText = settingsManager.customUserAgent
                    appEnvironment?.updateUserAgent()
                } label: {
                    Label(String(localized: "settings.advanced.userAgent.randomize"), systemImage: "arrow.trianglehead.2.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private var streamDetailsSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            SettingsFormSection(footer: "settings.advanced.stream.showDetails.footer") {
                Toggle(isOn: Binding(
                    get: { settingsManager.showAdvancedStreamDetails },
                    set: { settingsManager.showAdvancedStreamDetails = $0 }
                )) {
                    Label(String(localized: "settings.advanced.stream.showDetails"), systemImage: "list.bullet.rectangle")
                }
            }
        }
    }

    @ViewBuilder
    private var mpvSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            SettingsFormSection("settings.advanced.mpv.title") {
                PlatformMenuPicker(selection: Binding(
                    get: { settingsManager.mpvBufferSeconds },
                    set: { settingsManager.mpvBufferSeconds = $0 }
                )) {
                    ForEach(Self.mpvBufferOptions, id: \.self) { seconds in
                        Text(formatBufferOption(seconds)).tag(seconds)
                    }
                } label: {
                    Label(String(localized: "settings.advanced.mpv.buffer"), systemImage: "hourglass")
                }

                Toggle(isOn: Binding(
                    get: { settingsManager.mpvUseEDLStreams },
                    set: { settingsManager.mpvUseEDLStreams = $0 }
                )) {
                    Label(String(localized: "settings.advanced.mpv.edl"), systemImage: "arrow.trianglehead.merge")
                }

                Toggle(isOn: Binding(
                    get: { settingsManager.dashEnabled },
                    set: { settingsManager.dashEnabled = $0 }
                )) {
                    Label(String(localized: "settings.playback.dash"), systemImage: "bolt.horizontal")
                }

                #if os(tvOS)
                NavigationLink {
                    TVSidebarDetailContainer(
                        systemImage: "slider.horizontal.3",
                        title: String(localized: "settings.advanced.mpv.options")
                    ) {
                        MPVOptionsSettingsView()
                    }
                } label: {
                    Label(String(localized: "settings.advanced.mpv.options"), systemImage: "slider.horizontal.3")
                }
                #else
                SettingsNavigationRow("settings.advanced.mpv.options", systemImage: "slider.horizontal.3") {
                    MPVOptionsSettingsView()
                }
                #endif
            }
        }
    }

    #if os(tvOS)
    @ViewBuilder
    private var avSyncSection: some View {
        if let settings = appEnvironment?.settingsManager {
            SettingsFormSection {
                NavigationLink {
                    TVSidebarDetailContainer(
                        systemImage: "wave.3.right",
                        title: String(localized: "settings.playback.tvSyncDiagnostics.header")
                    ) {
                        AVSyncDiagnosticsView(settings: settings)
                    }
                } label: {
                    Label(String(localized: "settings.playback.tvSyncDiagnostics.row"), systemImage: "wave.3.right")
                }
            }
        }
    }
    #endif

    private static let mpvBufferOptions: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]

    private func formatBufferOption(_ seconds: Double) -> String {
        if seconds == 1.0 {
            return String(localized: "settings.advanced.mpv.bufferSecond")
        } else {
            return String(localized: "settings.advanced.mpv.bufferSeconds \(Int(seconds))")
        }
    }

    #if !os(tvOS)
    @ViewBuilder
    private var downloadsStorageSection: some View {
        SettingsFormSection("settings.advanced.storage.title") {
            // Storage diagnostic button
            HStack {
                Button {
                    runStorageDiagnostics()
                } label: {
                    Label(String(localized: "settings.advanced.storage.scan"), systemImage: "internaldrive")
                }
                .disabled(isScanningStorage)

                if isScanningStorage {
                    ProgressView()
                        .controlSize(.small)
                } else if let diagnostics = storageDiagnostics {
                    Text(diagnostics.formattedTotal)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Show storage breakdown if scanned
            if let diagnostics = storageDiagnostics {
                ForEach(diagnostics.items.sorted(by: { $0.size > $1.size }).prefix(10)) { item in
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text(formatBytes(item.size))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Clear cache button
            HStack {
                Button(role: .destructive) {
                    showingClearDataConfirmation = true
                } label: {
                    Label(String(localized: "settings.advanced.data.clearCache"), systemImage: "trash")
                }
                Spacer()
            }

            // Delete orphaned files button
            HStack {
                Button(role: .destructive) {
                    showingOrphanCleanupConfirmation = true
                } label: {
                    Label(String(localized: "settings.advanced.storage.deleteOrphaned"), systemImage: "trash")
                }
                .disabled(orphanedFilesCount == 0 || isScanning)

                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }
        } footer: {
            if isScanning {
                Text(String(localized: "settings.advanced.storage.scanning"))
            } else if orphanedFilesCount > 0 {
                Text(String(localized: "settings.advanced.storage.foundOrphaned \(orphanedFilesCount) \(formatBytes(orphanedFilesSize))"))
            } else if storageDiagnostics != nil {
                Text(String(localized: "settings.advanced.storage.noOrphaned"))
            } else {
                Text(String(localized: "settings.advanced.storage.tapToScan"))
            }
        }
    }
    #endif

    @ViewBuilder
    private var deviceNameSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            SettingsFormSection("settings.advanced.remoteControl.sectionTitle") {
                TextField(
                    LocalNetworkService.systemDeviceName,
                    text: Binding(
                        get: { settingsManager.remoteControlCustomDeviceName },
                        set: { newValue in
                            settingsManager.remoteControlCustomDeviceName = newValue
                            appEnvironment?.localNetworkService.updateDeviceName()
                        }
                    )
                )
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .autocorrectionDisabled()

                #if os(iOS) || os(tvOS)
                Toggle(isOn: Binding(
                    get: { settingsManager.remoteControlHideWhenBackgrounded },
                    set: { settingsManager.remoteControlHideWhenBackgrounded = $0 }
                )) {
                    Label(String(localized: "remoteControl.hideWhenBackgrounded"), systemImage: "moon.fill")
                }
                #endif
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.advanced.remoteControl.footer"))
                    #if os(iOS) || os(tvOS)
                    Text(String(localized: "settings.advanced.remoteControl.hideWhenBackgrounded.footer"))
                    #endif
                }
            }
        }
    }



    #if SPARKLE && os(macOS)
    @ViewBuilder
    private var updatesSection: some View {
        SettingsFormSection("settings.updates.title", footer: "settings.updates.footer") {
            Toggle(isOn: Binding(
                get: { AppUpdater.shared.wantsBetaChannel },
                set: { AppUpdater.shared.wantsBetaChannel = $0 }
            )) {
                Label(String(localized: "settings.updates.receiveBeta"), systemImage: "testtube.2")
            }
            Button {
                AppUpdater.shared.checkForUpdates()
            } label: {
                Label(String(localized: "menu.app.checkForUpdates"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!AppUpdater.shared.canCheckForUpdates)
        }
    }
    #endif

    @ViewBuilder
    private var developerSection: some View {
        SettingsFormSection(footer: "settings.developer.footer") {
            #if os(tvOS)
            NavigationLink {
                DeveloperSettingsView()
            } label: {
                Label(String(localized: "settings.developer.title"), systemImage: "hammer")
            }
            #else
            SettingsNavigationRow("settings.developer.title", systemImage: "hammer") {
                DeveloperSettingsView()
            }
            #endif

            if appEnvironment?.legacyMigrationService.hasLegacyAccountsToImport() == true {
                #if os(tvOS)
                NavigationLink {
                    LegacyDataImportView()
                } label: {
                    Label(String(localized: "migration.accounts.title"), systemImage: "person.badge.key")
                }
                #else
                SettingsNavigationRow("migration.accounts.title", systemImage: "person.badge.key") {
                    LegacyDataImportView()
                }
                #endif
            }
        }
    }

    // MARK: - Computed Properties

    private var settingsManager: SettingsManager {
        appEnvironment?.settingsManager ?? SettingsManager()
    }

    // MARK: - Feed Cache Options

    private static let feedCacheValidityOptions: [(minutes: Int, label: String)] = [
        (5, String(localized: "settings.advanced.feed.cacheValidity.5min")),
        (15, String(localized: "settings.advanced.feed.cacheValidity.15min")),
        (30, String(localized: "settings.advanced.feed.cacheValidity.30min")),
        (60, String(localized: "settings.advanced.feed.cacheValidity.1hour")),
        (120, String(localized: "settings.advanced.feed.cacheValidity.2hours")),
        (360, String(localized: "settings.advanced.feed.cacheValidity.6hours")),
        (720, String(localized: "settings.advanced.feed.cacheValidity.12hours")),
        (1440, String(localized: "settings.advanced.feed.cacheValidity.24hours")),
    ]

    // MARK: - Actions

    private func clearCache() {
        Task {
            // Clear Nuke image cache
            ImageLoadingService.shared.clearCache()

            // Clear feed cache
            await FeedCache.shared.clear()
            await MainActor.run {
                SubscriptionFeedCache.shared.clear()
            }

            // Clear DeArrow cache
            await appEnvironment?.deArrowBrandingProvider.clearCache()

            // Clear URL cache
            URLCache.shared.removeAllCachedResponses()

            // Clear temp directory (can contain large leftover files from downloads/playback)
            let tempURL = FileManager.default.temporaryDirectory
            if let contents = try? FileManager.default.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil, options: []) {
                for item in contents {
                    try? FileManager.default.removeItem(at: item)
                }
                LoggingService.shared.info("Cleared \(contents.count) temp files", category: .general)
            }

            // Clear system cache directories
            if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let systemCacheDirs = [
                    "com.apple.nsurlsessiond",
                    "com.apple.nsurlcache",
                    "fsCachedData"
                ]
                for dirName in systemCacheDirs {
                    let dirURL = cachesURL.appendingPathComponent(dirName)
                    if FileManager.default.fileExists(atPath: dirURL.path) {
                        try? FileManager.default.removeItem(at: dirURL)
                    }
                }
            }

            // Log the action
            LoggingService.shared.info("All caches and temp files cleared by user", category: .general)
        }
    }

    #if !os(tvOS)
    private func scanForOrphanedFiles() {
        guard let downloadManager = appEnvironment?.downloadManager else { return }
        isScanning = true
        let info = downloadManager.findOrphanedFiles()
        orphanedFilesCount = info.orphanedFiles.count
        orphanedFilesSize = info.totalOrphanedSize
        isScanning = false
    }

    private func deleteOrphanedFiles() {
        guard let downloadManager = appEnvironment?.downloadManager else { return }
        Task {
            let result = await downloadManager.deleteOrphanedFiles()
            orphanCleanupResult = (result.deletedCount, result.bytesFreed)
            showingOrphanCleanupResult = true
            // Rescan after cleanup
            scanForOrphanedFiles()
            // Also refresh storage diagnostics
            runStorageDiagnostics()
        }
    }

    private func runStorageDiagnostics() {
        isScanningStorage = true
        let diagnostics = scanAppStorage()
        diagnostics.logDiagnostics()
        storageDiagnostics = diagnostics
        isScanningStorage = false
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    #endif
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AdvancedSettingsView()
    }
}
