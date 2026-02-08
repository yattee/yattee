//
//  iCloudSettingsView.swift
//  Yattee
//
//  Settings for iCloud sync configuration.
//

import CloudKit
import SwiftUI

struct iCloudSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var showingEnableConfirmation = false
    @State private var showingDisableConfirmation = false
    @State private var showingCategoryEnableConfirmation: SyncCategory?
    @State private var showingCategorySyncConfirmation: SyncCategory?
    @State private var lastManualSyncTime: Date?
    @State private var expandedError = false
    @State private var expandedUpdateWarning = false
    @State private var syncRotation: Double = 0

    private var settingsManager: SettingsManager? {
        appEnvironment?.settingsManager
    }

    private var instancesManager: InstancesManager? {
        appEnvironment?.instancesManager
    }

    private var cloudKitSync: CloudKitSyncEngine? {
        appEnvironment?.cloudKitSync
    }

    private var mediaSourcesManager: MediaSourcesManager? {
        appEnvironment?.mediaSourcesManager
    }

    private var lastManualSyncRelative: String? {
        guard let lastSync = lastManualSyncTime else { return nil }
        return RelativeDateFormatter.string(for: lastSync, unitsStyle: .full)
    }

    private var syncNowIcon: String {
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, *) {
            return "arrow.trianglehead.2.clockwise.rotate.90.icloud"
        } else {
            return "bolt.horizontal.icloud"
        }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { settingsManager?.iCloudSyncEnabled ?? false },
                    set: { newValue in
                        if newValue {
                            showingEnableConfirmation = true
                        } else {
                            showingDisableConfirmation = true
                        }
                    }
                )) {
                    Label(String(localized: "settings.icloud.enable"), systemImage: "icloud")
                }
            } footer: {
                Text(String(localized: "settings.icloud.footer"))
            }

            if settingsManager?.iCloudSyncEnabled == true {
                syncCategoriesSection
                syncStatusSection
            }
        }
        .navigationTitle(String(localized: "settings.icloud.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await cloudKitSync?.refreshAccountStatus()
        }
        .confirmationDialog(
            String(localized: "settings.icloud.enable.confirmation.title"),
            isPresented: $showingEnableConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.icloud.enable.confirmation.action"), role: .destructive) {
                enableiCloudSync()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.icloud.enable.confirmation.message"))
        }
        .confirmationDialog(
            String(localized: "settings.icloud.disable.confirmation.title"),
            isPresented: $showingDisableConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.icloud.disable.confirmation.action"), role: .destructive) {
                disableiCloudSync()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.icloud.disable.confirmation.message"))
        }
        // Confirmation for categories that replace local data (instances, settings, media sources)
        .confirmationDialog(
            String(localized: "settings.icloud.category.enable.title"),
            isPresented: .init(
                get: { showingCategoryEnableConfirmation != nil },
                set: { if !$0 { showingCategoryEnableConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.icloud.category.enable.action"), role: .destructive) {
                if let category = showingCategoryEnableConfirmation {
                    enableCategory(category)
                }
                showingCategoryEnableConfirmation = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                showingCategoryEnableConfirmation = nil
            }
        } message: {
            Text(String(localized: "settings.icloud.category.enable.message"))
        }
        // Confirmation for categories that upload/merge local data (subscriptions, bookmarks, playlists, history)
        .confirmationDialog(
            String(localized: "settings.icloud.category.sync.title"),
            isPresented: .init(
                get: { showingCategorySyncConfirmation != nil },
                set: { if !$0 { showingCategorySyncConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.icloud.category.sync.action")) {
                if let category = showingCategorySyncConfirmation {
                    enableCategory(category)
                }
                showingCategorySyncConfirmation = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                showingCategorySyncConfirmation = nil
            }
        } message: {
            Text(String(localized: "settings.icloud.category.sync.message"))
        }
    }

    // MARK: - Sync Categories Section

    @ViewBuilder
    private var syncCategoriesSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settingsManager?.syncInstances ?? true },
                set: { newValue in
                    if newValue {
                        showCategoryConfirmation(for: .instances)
                    } else {
                        settingsManager?.syncInstances = false
                    }
                }
            )) {
                Label(String(localized: "settings.icloud.category.instances"), systemImage: "server.rack")
            }

            Toggle(isOn: Binding(
                get: { settingsManager?.syncSubscriptions ?? true },
                set: { newValue in
                    if newValue {
                        showCategoryConfirmation(for: .subscriptions)
                    } else {
                        settingsManager?.syncSubscriptions = false
                    }
                }
            )) {
                Label(String(localized: "settings.icloud.category.subscriptions"), systemImage: "person.2")
            }

            Toggle(isOn: Binding(
                get: { settingsManager?.syncBookmarks ?? true },
                set: { newValue in
                    if newValue {
                        showCategoryConfirmation(for: .bookmarks)
                    } else {
                        settingsManager?.syncBookmarks = false
                    }
                }
            )) {
                Label(String(localized: "settings.icloud.category.bookmarks"), systemImage: "bookmark.fill")
            }

            Toggle(isOn: Binding(
                get: { settingsManager?.syncPlaylists ?? true },
                set: { newValue in
                    if newValue {
                        showCategoryConfirmation(for: .playlists)
                    } else {
                        settingsManager?.syncPlaylists = false
                    }
                }
            )) {
                Label(String(localized: "settings.icloud.category.playlists"), systemImage: "list.bullet.rectangle")
            }

            Toggle(isOn: Binding(
                get: { settingsManager?.syncPlaybackHistory ?? true },
                set: { newValue in
                    if newValue {
                        showCategoryConfirmation(for: .playbackHistory)
                    } else {
                        settingsManager?.syncPlaybackHistory = false
                    }
                }
            )) {
                Label(String(localized: "settings.icloud.category.playbackHistory"), systemImage: "clock.arrow.circlepath")
            }

            Toggle(isOn: Binding(
                get: { settingsManager?.syncSearchHistory ?? true },
                set: { newValue in
                    if newValue {
                        showCategoryConfirmation(for: .searchHistory)
                    } else {
                        settingsManager?.syncSearchHistory = false
                    }
                }
            )) {
                Label(String(localized: "settings.icloud.category.searchHistory"), systemImage: "magnifyingglass.circle")
            }

            Toggle(isOn: Binding(
                get: { settingsManager?.syncSettings ?? true },
                set: { newValue in
                    if newValue {
                        showCategoryConfirmation(for: .settings)
                    } else {
                        settingsManager?.syncSettings = false
                    }
                }
            )) {
                Label(String(localized: "settings.icloud.category.settings"), systemImage: "gearshape")
            }

            Toggle(isOn: Binding(
                get: { settingsManager?.syncMediaSources ?? true },
                set: { newValue in
                    if newValue {
                        showCategoryConfirmation(for: .mediaSources)
                    } else {
                        settingsManager?.syncMediaSources = false
                    }
                }
            )) {
                Label(String(localized: "settings.icloud.category.mediaSources"), systemImage: "externaldrive.connected.to.line.below")
            }
        } footer: {
            Text(String(localized: "settings.icloud.categories.footer"))
        }
    }

    // MARK: - Sync Status Section

    @ViewBuilder
    private var syncStatusSection: some View {
        Section {
            // iCloud Account Status
            HStack {
                Label("Account", systemImage: "person.crop.circle")
                Spacer()
                HStack(spacing: 6) {
                    accountStatusIcon
                    Text(cloudKitSync?.accountStatusText ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Sync Status
            HStack {
                Label("Status", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                HStack(spacing: 6) {
                    syncStatusIcon
                    Text(cloudKitSync?.syncStatusText ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Pending Changes (if any)
            if let count = cloudKitSync?.pendingChangesCount, count > 0 {
                HStack {
                    Label("Pending", systemImage: "clock")
                    Spacer()
                    Text("\(count) item\(count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Last Sync (automatic)
            if let lastSync = cloudKitSync?.lastSyncDate {
                HStack {
                    Label("Last Synced", systemImage: "checkmark.circle")
                    Spacer()
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Error Row (expandable)
            if case .error(let error) = cloudKitSync?.syncStatus {
                errorRow(error)
            }

            // Update available warning (newer schema detected)
            if cloudKitSync?.hasNewerSchemaRecords == true {
                updateAvailableRow
            }

            // Upload Progress (initial sync)
            if let progress = cloudKitSync?.uploadProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if !progress.isComplete {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Text(progress.displayText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Sync Now Button
            Button {
                syncNow()
            } label: {
                Label("Sync Now", systemImage: syncNowIcon)
            }
            .disabled(cloudKitSync?.isSyncing == true)
            
        } footer: {
            if let lastSync = lastManualSyncRelative {
                Text("Last manual sync: \(lastSync)")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: cloudKitSync?.syncStatus)
        .animation(.easeInOut(duration: 0.3), value: cloudKitSync?.uploadProgress)
    }

    // MARK: - Status Icons
    
    private var accountStatusIcon: some View {
        Group {
            switch cloudKitSync?.accountStatus {
            case .available:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .noAccount, .restricted:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .temporarilyUnavailable:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.yellow)
            default:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.gray)
            }
        }
    }
    
    private var syncStatusIcon: some View {
        Group {
            // Show rotating icon for both syncing and receiving changes
            if cloudKitSync?.isSyncing == true || cloudKitSync?.isReceivingChanges == true {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(syncRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            syncRotation = 360
                        }
                    }
                    .onDisappear {
                        syncRotation = 0
                    }
            } else {
                switch cloudKitSync?.syncStatus {
                case .syncing:
                    // Handled above
                    EmptyView()
                case .upToDate:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .pending:
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                case .none:
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.gray)
                }
            }
        }
    }
    
    // MARK: - Error Display
    
    @ViewBuilder
    private func errorRow(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsed view
            Button {
                withAnimation {
                    expandedError.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Sync Error")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expandedError ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            
            // Expanded view with details
            if expandedError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Retry button
                    Button {
                        Task {
                            await cloudKitSync?.sync()
                        }
                    } label: {
                        Label("Retry Sync", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.leading, 28) // Align with text
            }
        }
    }

    @ViewBuilder
    private var updateAvailableRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    expandedUpdateWarning.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                    Text(String(localized: "settings.icloud.update.title"))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expandedUpdateWarning ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if expandedUpdateWarning {
                Text(String(localized: "settings.icloud.update.message"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
            }
        }
    }

    // MARK: - Actions

    private func showCategoryConfirmation(for category: SyncCategory) {
        if category.usesReplaceStrategy {
            showingCategoryEnableConfirmation = category
        } else {
            showingCategorySyncConfirmation = category
        }
    }

    private func enableiCloudSync() {
        // Enable sync setting and all categories by default
        settingsManager?.iCloudSyncEnabled = true
        settingsManager?.enableAllSyncCategories()

        // Enable CloudKit sync engine then upload all existing local data
        Task {
            await cloudKitSync?.enable()
            await cloudKitSync?.performInitialUpload()
        }

        // Keep old sync for non-migrated data
        settingsManager?.replaceWithiCloudData()
        instancesManager?.replaceWithiCloudData()
        mediaSourcesManager?.replaceWithiCloudData()
    }

    private func disableiCloudSync() {
        settingsManager?.iCloudSyncEnabled = false
        cloudKitSync?.disable()
    }

    private func enableCategory(_ category: SyncCategory) {
        switch category {
        case .instances:
            settingsManager?.syncInstances = true
            instancesManager?.replaceWithiCloudData()
        case .subscriptions:
            settingsManager?.syncSubscriptions = true
            // Upload existing subscriptions to CloudKit
            Task {
                await cloudKitSync?.uploadAllLocalSubscriptions()
            }
        case .playbackHistory:
            settingsManager?.syncPlaybackHistory = true
            // Upload existing watch history to CloudKit
            Task {
                await cloudKitSync?.uploadAllLocalWatchHistory()
            }
        case .bookmarks:
            settingsManager?.syncBookmarks = true
            // Upload existing bookmarks to CloudKit
            Task {
                await cloudKitSync?.uploadAllLocalBookmarks()
            }
        case .playlists:
            settingsManager?.syncPlaylists = true
            // Upload existing playlists to CloudKit
            Task {
                await cloudKitSync?.uploadAllLocalPlaylists()
            }
        case .searchHistory:
            settingsManager?.syncSearchHistory = true
            // Upload existing search history to CloudKit
            Task {
                await cloudKitSync?.uploadAllLocalSearchHistory()
                await cloudKitSync?.uploadAllRecentChannels()
                await cloudKitSync?.uploadAllRecentPlaylists()
            }
        case .settings:
            settingsManager?.syncSettings = true
            settingsManager?.replaceWithiCloudData()
            // Upload existing controls presets to CloudKit
            Task {
                await cloudKitSync?.uploadAllLocalControlsPresets()
            }
        case .mediaSources:
            settingsManager?.syncMediaSources = true
            mediaSourcesManager?.replaceWithiCloudData()
        }
    }

    private func syncNow() {
        // Trigger CloudKit refresh sync (clears stale tokens, fetches all changes)
        Task {
            await cloudKitSync?.refreshSync()
        }
        
        // Push other data to iCloud (non-CloudKit)
        settingsManager?.syncToiCloud()
        instancesManager?.syncToiCloud()
        mediaSourcesManager?.syncToiCloud()
        lastManualSyncTime = Date()
    }
}

// MARK: - Sync Category

private enum SyncCategory {
    case instances
    case subscriptions
    case bookmarks
    case playbackHistory
    case playlists
    case searchHistory
    case mediaSources
    case settings
    

    /// Categories that replace local data with iCloud data
    var usesReplaceStrategy: Bool {
        switch self {
        case .instances, .settings, .mediaSources:
            return true
        case .subscriptions, .bookmarks, .playlists, .playbackHistory, .searchHistory:
            return false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        iCloudSettingsView()
    }
    .appEnvironment(.preview)
}
