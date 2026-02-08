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
        List {
            streamDetailsSection
            mpvSection
            settingsSection
            #if !os(tvOS)
            downloadsStorageSection
            #endif
            developerSection
        }
        .navigationTitle(String(localized: "settings.advanced.title"))
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
        Section {
            Picker(selection: Binding(
                get: { settingsManager.feedCacheValidityMinutes },
                set: { settingsManager.feedCacheValidityMinutes = $0 }
            )) {
                ForEach(Self.feedCacheValidityOptions, id: \.minutes) { option in
                    Text(option.label).tag(option.minutes)
                }
            } label: {
                Label(String(localized: "settings.advanced.feed.cacheValidity"), systemImage: "clock")
            }
        } header: {
            Text(String(localized: "settings.advanced.feed.sectionTitle"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.advanced.feed.footer"))
                if let lastCheck = settingsManager.lastBackgroundCheck {
                    Text(String(localized: "settings.advanced.feed.lastBackgroundRefresh \(lastCheck.formatted(date: .abbreviated, time: .shortened))"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "settings.advanced.feed.lastBackgroundRefresh.never"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func userAgentSection(settingsManager: SettingsManager) -> some View {
        Section {
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
        } header: {
            Text(String(localized: "settings.advanced.userAgent.sectionTitle"))
        } footer: {
            Text(String(localized: "settings.advanced.userAgent.footer"))
        }
    }

    @ViewBuilder
    private var streamDetailsSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            Section {
                Toggle(isOn: Binding(
                    get: { settingsManager.showAdvancedStreamDetails },
                    set: { settingsManager.showAdvancedStreamDetails = $0 }
                )) {
                    Label(String(localized: "settings.advanced.stream.showDetails"), systemImage: "list.bullet.rectangle")
                }
            } footer: {
                Text(String(localized: "settings.advanced.stream.showDetails.footer"))
            }
        }
    }

    @ViewBuilder
    private var mpvSection: some View {
        if let settingsManager = appEnvironment?.settingsManager {
            Section {
                Picker(selection: Binding(
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

                NavigationLink {
                    MPVOptionsSettingsView()
                } label: {
                    Label(String(localized: "settings.advanced.mpv.options"), systemImage: "slider.horizontal.3")
                }
            } header: {
                Text(String(localized: "settings.advanced.mpv.title"))
            }
        }
    }

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
        Section {
            // Storage diagnostic button
            Button {
                runStorageDiagnostics()
            } label: {
                HStack {
                    Label(String(localized: "settings.advanced.storage.scan"), systemImage: "internaldrive")
                    Spacer()
                    if isScanningStorage {
                        ProgressView()
                            .controlSize(.small)
                    } else if let diagnostics = storageDiagnostics {
                        Text(diagnostics.formattedTotal)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isScanningStorage)

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
            Button(role: .destructive) {
                showingClearDataConfirmation = true
            } label: {
                Label(String(localized: "settings.advanced.data.clearCache"), systemImage: "trash")
            }

            // Delete orphaned files button
            Button(role: .destructive) {
                showingOrphanCleanupConfirmation = true
            } label: {
                HStack {
                    Label(String(localized: "settings.advanced.storage.deleteOrphaned"), systemImage: "trash")
                    Spacer()
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(orphanedFilesCount == 0 || isScanning)
        } header: {
            Text(String(localized: "settings.advanced.storage.title"))
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
            Section {
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
            } header: {
                Text(String(localized: "settings.advanced.remoteControl.sectionTitle"))
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



    @ViewBuilder
    private var developerSection: some View {
        Section {
            NavigationLink {
                DeveloperSettingsView()
            } label: {
                Label(String(localized: "settings.developer.title"), systemImage: "hammer")
            }

            if appEnvironment?.legacyMigrationService.hasLegacyData() == true {
                NavigationLink {
                    LegacyDataImportView()
                } label: {
                    Label(String(localized: "settings.advanced.data.importLegacy"), systemImage: "arrow.up.doc")
                }
            }
        } footer: {
            Text(String(localized: "settings.developer.footer"))
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
