//
//  CloudKitSyncEngine.swift
//  Yattee
//
//  Main CloudKit sync engine using CKSyncEngine for robust iCloud sync.
//

import CloudKit
import Foundation
import SwiftData

// MARK: - Deferred Playlist Item

/// Tracks deferred playlist items with retry counts for persistent recovery.
/// When playlist items arrive from CloudKit before their parent playlist,
/// they are stored in this structure and persisted to UserDefaults.
struct DeferredPlaylistItem: Codable {
    /// Serialized CKRecord data.
    let recordData: Data

    /// The playlist ID this item belongs to.
    let playlistID: String

    /// The playlist item ID.
    let itemID: String

    /// Number of retry attempts.
    var retryCount: Int

    /// When this item was first deferred.
    let firstDeferredAt: Date

    init(record: CKRecord, playlistID: UUID, itemID: UUID) throws {
        self.recordData = try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
        self.playlistID = playlistID.uuidString
        self.itemID = itemID.uuidString
        self.retryCount = 0
        self.firstDeferredAt = Date()
    }

    func toCKRecord() throws -> CKRecord? {
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: recordData)
    }
}

/// Result of applying a remote record.
private enum ApplyRecordResult {
    /// Record was successfully applied.
    case success
    /// Record was deferred (playlist item without parent playlist).
    case deferred(playlistID: UUID, itemID: UUID)
    /// Record processing failed (logged but not fatal).
    case failed
}

/// Main CloudKit sync engine that manages bidirectional sync between local SwiftData and iCloud.
@MainActor
@Observable
final class CloudKitSyncEngine: @unchecked Sendable {
    // MARK: - Singleton Reference

    /// Weak reference to the current sync engine instance, used by AppDelegate to forward push notifications.
    static weak var current: CloudKitSyncEngine?

    // MARK: - State

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneManager: CloudKitZoneManager
    private var recordMapper: CloudKitRecordMapper
    private var conflictResolver: CloudKitConflictResolver
    private var syncEngine: CKSyncEngine?
    
    /// Whether sync is currently in progress.
    var isSyncing = false
    
    /// Whether currently receiving changes from CloudKit.
    var isReceivingChanges = false
    
    /// Last successful sync timestamp.
    var lastSyncDate: Date?
    
    /// Current sync error, if any.
    var syncError: Error?
    
    /// Pending changes queued before the sync engine is ready; flushed into
    /// the engine state as soon as it is created.
    private var pendingChangesBuffer: [CKSyncEngine.PendingRecordZoneChange] = []

    /// Conflict-resolved records awaiting upload, keyed by record name.
    /// These carry the server change tag from the conflict error and take
    /// precedence over freshly materialized records at send time.
    private var conflictResolvedRecords: [String: CKRecord] = [:]

    /// The CloudKit zone all records live in (constant name, never changes).
    private let zone = RecordType.createZone()

    /// Debounce timer for batching changes.
    private var debounceTimer: Timer?

    /// Debounce delay in seconds.
    private let debounceDelay: TimeInterval = 5.0

    /// Guard against re-entrant setupSyncEngine calls (e.g. from .accountChange during setup).
    private var isSettingUpEngine = false

    /// Timer for periodic foreground polling (fallback when push notifications don't arrive).
    private var foregroundPollTimer: Timer?

    /// Foreground polling interval in seconds (3 minutes).
    private let foregroundPollInterval: TimeInterval = 180
    
    /// Retry tracking: recordName -> retry count
    private var retryCount: [String: Int] = [:]
    
    /// Maximum number of retry attempts for conflict resolution.
    private let maxRetryAttempts = 5

    // MARK: - Account Identity Tracking
    
    /// UserDefaults key for storing the current iCloud account's record ID.
    private let accountRecordIDKey = "cloudKitAccountRecordID"
    
    /// UserDefaults key for CloudKit sync state.
    private let syncStateKey = "cloudKitSyncState"

    /// UserDefaults key for the record schema version this app last synced with.
    private let lastSchemaVersionKey = "cloudKitLastSchemaVersion"
    
    /// Legacy UserDefaults key for pending save record names (pre state-driven
    /// engine). Only read once for migration, then removed.
    private let pendingSaveRecordNamesKey = "cloudKitPendingSaveRecordNames"

    /// Legacy UserDefaults key for pending delete record names (pre state-driven
    /// engine). Only read once for migration, then removed.
    private let pendingDeleteRecordNamesKey = "cloudKitPendingDeleteRecordNames"

    // MARK: - Deferred Playlist Item Management

    /// UserDefaults key for persisting deferred playlist items.
    private let deferredPlaylistItemsKey = "cloudKitDeferredPlaylistItems"

    /// Deferred playlist items waiting for their parent playlists to arrive.
    private var deferredPlaylistItems: [DeferredPlaylistItem] = []

    /// Maximum number of retry attempts before creating a placeholder playlist.
    private let maxDeferralRetries = 5

    // MARK: - UI-Friendly State
    
    /// Current account status (cached, refreshed periodically)
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    
    /// Initial upload progress (nil when not doing initial upload)
    private(set) var uploadProgress: UploadProgress?

    /// Whether newer schema versions were encountered that require app update.
    private(set) var hasNewerSchemaRecords = false

    /// Computed sync status for UI display
    var syncStatus: SyncStatus {
        if let error = syncError {
            return .error(error)
        }
        if isSyncing {
            return .syncing
        }
        if pendingChangesCount == 0 {
            return .upToDate
        }
        return .pending(count: pendingChangesCount)
    }

    /// Pending changes count (mirrors the sync engine state so the UI can observe it).
    private(set) var pendingChangesCount = 0
    
    /// User-friendly sync status text
    var syncStatusText: String {
        // Show "Receiving changes..." when downloading from other devices
        if isReceivingChanges {
            return "Receiving changes..."
        }
        
        switch syncStatus {
        case .syncing:
            return "Syncing..."
        case .upToDate:
            return "Up to Date"
        case .pending(let count):
            return "\(count) change\(count == 1 ? "" : "s") pending"
        case .error:
            return "Error"
        }
    }
    
    /// User-friendly account status text
    var accountStatusText: String {
        switch accountStatus {
        case .available:
            return "iCloud Account Active"
        case .noAccount:
            return "No iCloud Account"
        case .restricted:
            return "iCloud Restricted"
        case .couldNotDetermine:
            return "Checking iCloud..."
        case .temporarilyUnavailable:
            return "iCloud Temporarily Unavailable"
        @unknown default:
            return "Unknown iCloud Status"
        }
    }
    
    // MARK: - Dependencies
    
    private weak var dataManager: DataManager?
    private weak var settingsManager: SettingsManager?
    private weak var instancesManager: InstancesManager?
    
    /// Player controls layout service for importing/removing presets from CloudKit.
    /// Set after initialization to use shared instance instead of creating new ones.
    weak var playerControlsLayoutService: PlayerControlsLayoutService?
    
    // MARK: - Initialization
    
    init(
        dataManager: DataManager? = nil,
        settingsManager: SettingsManager? = nil,
        instancesManager: InstancesManager? = nil
    ) {
        self.dataManager = dataManager
        self.settingsManager = settingsManager
        self.instancesManager = instancesManager
        
        // Initialize CloudKit
        self.container = CKContainer(identifier: AppIdentifiers.iCloudContainer)
        self.database = container.privateCloudDatabase
        
        // Initialize zone manager
        self.zoneManager = CloudKitZoneManager(database: database)
        
        // Initialize with temporary zone (will be updated in setupSyncEngine)
        let tempZone = RecordType.createZone()
        self.recordMapper = CloudKitRecordMapper(zone: tempZone)
        self.conflictResolver = CloudKitConflictResolver()
        
        // Make this instance accessible for push notification forwarding
        CloudKitSyncEngine.current = self

        // Setup sync engine after initialization complete - only if sync is enabled
        Task {
            if settingsManager?.iCloudSyncEnabled == true {
                await setupSyncEngine()
            } else {
                LoggingService.shared.logCloudKit("CloudKit sync disabled at startup, skipping engine setup")
            }
        }
    }

    // MARK: - Dynamic Enable/Disable

    /// Enables CloudKit sync. Creates CKSyncEngine and starts syncing.
    func enable() async {
        guard syncEngine == nil else {
            LoggingService.shared.logCloudKit("Sync engine already enabled")
            return
        }
        LoggingService.shared.logCloudKit("Enabling CloudKit sync...")
        await setupSyncEngine()
    }

    /// Disables CloudKit sync. Tears down CKSyncEngine.
    func disable() {
        guard syncEngine != nil else {
            LoggingService.shared.logCloudKit("Sync engine already disabled")
            return
        }
        LoggingService.shared.logCloudKit("Disabling CloudKit sync...")

        debounceTimer?.invalidate()
        debounceTimer = nil
        foregroundPollTimer?.invalidate()
        foregroundPollTimer = nil
        pendingChangesBuffer.removeAll()
        conflictResolvedRecords.removeAll()
        retryCount.removeAll()
        deferredPlaylistItems.removeAll()
        syncEngine = nil
        updatePendingCount()
        isSyncing = false
        isReceivingChanges = false
        syncError = nil
        hasNewerSchemaRecords = false

        LoggingService.shared.logCloudKit("CloudKit sync disabled")
    }

    // MARK: - Setup

    private func setupSyncEngine() async {
        // Guard: prevent re-entrant calls (e.g. .accountChange firing during setup)
        guard !isSettingUpEngine else {
            LoggingService.shared.logCloudKit("setupSyncEngine already in progress, skipping re-entrant call")
            return
        }
        isSettingUpEngine = true
        defer { isSettingUpEngine = false }

        // Guard: only setup if sync is enabled
        guard settingsManager?.iCloudSyncEnabled == true else {
            LoggingService.shared.logCloudKit("setupSyncEngine called but sync is disabled, skipping")
            return
        }

        do {
            // Check iCloud account status
            let status = try await container.accountStatus()
            self.accountStatus = status // Cache for UI
            guard status == .available else {
                let error = CloudKitError.iCloudNotAvailable(status: status)
                syncError = error
                LoggingService.shared.logCloudKitError("iCloud not available", error: error)
                return
            }
            
            // Check for account change before setting up sync
            let accountChanged = await checkAndHandleAccountChange()
            
            // Create zone
            try await zoneManager.createZoneIfNeeded()
            
            // Reinitialize mapper with actual zone
            let zone = await zoneManager.getZone()
            self.recordMapper = CloudKitRecordMapper(zone: zone)
            
            // Records written by a newer app version fail to parse and are only
            // re-delivered on a full fetch, so a schema upgrade must invalidate the
            // persisted state once to pick them up.
            invalidateSyncStateAfterSchemaUpgradeIfNeeded()

            // Resume from persisted sync state so launches fetch only changes since
            // the last session instead of replaying the entire zone change history.
            // Starts with nil (full fetch) on first sync, account change, manual
            // refresh, or schema upgrade.
            let savedState = loadSyncState()
            LoggingService.shared.logCloudKit(savedState != nil
                ? "Creating CKSyncEngine with persisted state (incremental fetch)"
                : "Creating CKSyncEngine with fresh state (full fetch)")

            let config = CKSyncEngine.Configuration(
                database: database,
                stateSerialization: savedState,
                delegate: self
            )

            let engine = CKSyncEngine(config)
            self.syncEngine = engine
            LoggingService.shared.logCloudKit("CKSyncEngine created")

            // Flush changes queued while the engine was not ready
            if !pendingChangesBuffer.isEmpty {
                engine.state.add(pendingRecordZoneChanges: pendingChangesBuffer)
                pendingChangesBuffer.removeAll()
            }

            if accountChanged {
                LoggingService.shared.logCloudKit("CloudKit sync engine initialized with new account (fresh sync state)")
            } else {
                LoggingService.shared.logCloudKit("CloudKit sync engine initialized successfully")
                // One-time migration of pending changes persisted by the old
                // array-based queue (pre state-driven engine)
                migrateLegacyPendingChanges(into: engine)
            }

            loadDeferredItems()
            updatePendingCount()
            
            // Perform initial sync
            await sync()
            
        } catch {
            LoggingService.shared.logCloudKitError("Failed to setup sync engine", error: error)
            syncError = error
        }
    }
    
    /// Checks if the iCloud account has changed and handles it by clearing sync state.
    /// - Returns: `true` if account changed and sync state was cleared, `false` otherwise.
    private func checkAndHandleAccountChange() async -> Bool {
        do {
            // Fetch the current user's record ID using async wrapper
            let currentUserRecordID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord.ID, Error>) in
                container.fetchUserRecordID { recordID, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let recordID = recordID {
                        continuation.resume(returning: recordID)
                    } else {
                        continuation.resume(throwing: NSError(domain: "CloudKitSyncEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user record ID"]))
                    }
                }
            }
            let currentRecordName = currentUserRecordID.recordName
            
            // Get the stored account ID (if any)
            let storedRecordName = UserDefaults.standard.string(forKey: accountRecordIDKey)
            
            if let storedID = storedRecordName {
                if storedID != currentRecordName {
                    // Account changed! Clear sync state to prevent conflicts
                    LoggingService.shared.logCloudKit(
                        "iCloud account changed detected: \(storedID.prefix(8))... -> \(currentRecordName.prefix(8))... - clearing sync state"
                    )
                    clearSyncStateForAccountChange()
                    
                    // Store new account ID
                    UserDefaults.standard.set(currentRecordName, forKey: accountRecordIDKey)
                    return true
                } else {
                    LoggingService.shared.logCloudKit("iCloud account unchanged: \(currentRecordName.prefix(8))...")
                    return false
                }
            } else {
                // First time setup - store the account ID
                LoggingService.shared.logCloudKit("First iCloud account recorded: \(currentRecordName.prefix(8))...")
                UserDefaults.standard.set(currentRecordName, forKey: accountRecordIDKey)
                return false
            }
        } catch {
            // If we can't fetch the user record ID, log and continue without account tracking
            LoggingService.shared.logCloudKitError("Failed to fetch user record ID for account tracking", error: error)
            return false
        }
    }
    
    /// Clears sync state when account changes to ensure fresh sync with new account.
    private func clearSyncStateForAccountChange() {
        // Clear CKSyncEngine state
        UserDefaults.standard.removeObject(forKey: syncStateKey)

        // Clear pending changes (they belong to the old account context)
        pendingChangesBuffer.removeAll()
        conflictResolvedRecords.removeAll()
        retryCount.removeAll()

        // Clear deferred playlist items (they belong to the old account context)
        clearDeferredItems()

        // Clear any existing sync engine
        syncEngine = nil
        updatePendingCount()

        // Reset newer schema warning
        hasNewerSchemaRecords = false

        LoggingService.shared.logCloudKit("Cleared sync state for account change")
    }
    
    /// Clears persisted sync state after an app update that raised the record
    /// schema version. Records from newer schema versions are rejected by the
    /// mapper and are not re-delivered by an incremental fetch, so the first
    /// launch that understands them must do one full re-fetch.
    private func invalidateSyncStateAfterSchemaUpgradeIfNeeded() {
        let storedVersion = Int64(UserDefaults.standard.integer(forKey: lastSchemaVersionKey))
        let currentVersion = CloudKitRecordMapper.currentSchemaVersion
        guard storedVersion < currentVersion else { return }

        if UserDefaults.standard.data(forKey: syncStateKey) != nil {
            UserDefaults.standard.removeObject(forKey: syncStateKey)
            LoggingService.shared.logCloudKit("Schema version upgraded (\(storedVersion) -> \(currentVersion)), cleared sync state for full re-fetch")
        }
        UserDefaults.standard.set(Int(currentVersion), forKey: lastSchemaVersionKey)
    }

    /// Loads persisted sync state from disk.
    private func loadSyncState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: syncStateKey) else {
            return nil
        }
        
        do {
            let decoder = PropertyListDecoder()
            return try decoder.decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to load sync state", error: error)
            return nil
        }
    }
    
    /// Saves sync state to disk.
    private func saveSyncState(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            let encoder = PropertyListEncoder()
            let data = try encoder.encode(serialization)
            UserDefaults.standard.set(data, forKey: syncStateKey)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to save sync state", error: error)
        }
    }
    
    // MARK: - Public API
    
    /// Whether CloudKit sync is enabled in settings.
    var isSyncEnabled: Bool {
        settingsManager?.iCloudSyncEnabled ?? false
    }
    
    // MARK: - Category Sync Helpers
    
    /// Whether subscription sync is enabled (master toggle + category toggle).
    private var canSyncSubscriptions: Bool {
        isSyncEnabled && (settingsManager?.syncSubscriptions ?? true)
    }
    
    /// Whether playback history sync is enabled (master toggle + category toggle).
    private var canSyncPlaybackHistory: Bool {
        isSyncEnabled && (settingsManager?.syncPlaybackHistory ?? true)
    }
    
    /// Whether bookmark sync is enabled (master toggle + category toggle).
    private var canSyncBookmarks: Bool {
        isSyncEnabled && (settingsManager?.syncBookmarks ?? true)
    }
    
    /// Whether playlist sync is enabled (master toggle + category toggle).
    private var canSyncPlaylists: Bool {
        isSyncEnabled && (settingsManager?.syncPlaylists ?? true)
    }
    
    /// Whether search history sync is enabled (master toggle + category toggle).
    private var canSyncSearchHistory: Bool {
        isSyncEnabled && (settingsManager?.syncSearchHistory ?? true)
    }
    
    /// Whether controls presets sync is enabled (master toggle + settings category toggle).
    private var canSyncControlsPresets: Bool {
        isSyncEnabled && (settingsManager?.syncSettings ?? true)
    }
    
    /// Manually trigger a full sync.
    func sync() async {
        guard isSyncEnabled, let syncEngine else {
            LoggingService.shared.logCloudKit("Sync skipped: sync disabled or engine not ready")
            return
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            // Fetch remote changes first
            LoggingService.shared.logCloudKit("Fetching remote changes...")
            try await syncEngine.fetchChanges()
            let pendingCount = syncEngine.state.pendingRecordZoneChanges.count
            LoggingService.shared.logCloudKit("fetchChanges() completed (\(pendingCount) pending changes)")

            // Then send local changes
            if pendingCount > 0 {
                LoggingService.shared.logCloudKit("Sending \(pendingCount) pending changes...")
                try await syncEngine.sendChanges()
            }

            lastSyncDate = Date()
            settingsManager?.updateLastSyncTime()

            LoggingService.shared.logCloudKit("Sync completed successfully")
            
        } catch {
            // Always log for debugging
            LoggingService.shared.logCloudKitError("Sync failed", error: error)
            
            // Only show user-actionable errors in UI (filter out auto-resolved conflicts)
            if shouldShowError(error) {
                syncError = error
            } else {
                syncError = nil
            }
            
            handleSyncError(error)
        }

        updatePendingCount()
        isSyncing = false
    }

    /// Queue a subscription for sync (debounced).
    func queueSubscriptionSave(_ subscription: Subscription) {
        guard canSyncSubscriptions else { return }

        let recordID = recordMapper.toCKRecord(subscription: subscription).recordID
        addPendingChanges([.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued subscription save: \(subscription.channelID)")
    }

    /// Queue a subscription deletion for sync (debounced).
    func queueSubscriptionDelete(channelID: String, scope: SourceScope) {
        guard canSyncSubscriptions else { return }

        let recordID = SyncableRecordType.subscription(channelID: channelID, scope: scope).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued subscription delete: \(channelID)")
    }
    
    /// Upload all existing local subscriptions to CloudKit (for initial sync).
    /// Call this when enabling iCloud sync for the first time.
    func uploadAllLocalSubscriptions() async {
        guard isSyncEnabled, let dataManager else {
            LoggingService.shared.logCloudKit("Cannot upload: sync disabled or data manager unavailable")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Subscriptions"
        
        LoggingService.shared.logCloudKit("Starting initial bulk upload of local subscriptions...")
        
        // Get all local subscriptions
        let subscriptions = dataManager.subscriptions()
        
        guard !subscriptions.isEmpty else {
            LoggingService.shared.logCloudKit("No local subscriptions to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += subscriptions.count

        // Register all record IDs with the sync engine; records are
        // materialized from local data at send time.
        let changes = subscriptions.map { subscription in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordMapper.toCKRecord(subscription: subscription).recordID)
        }
        addPendingChanges(changes, debounce: false)

        LoggingService.shared.logCloudKit("Queued \(subscriptions.count) existing subscriptions for initial upload")
        
        // Trigger immediate sync (no debounce for initial upload)
        await sync()
    }
    
    // MARK: - WatchEntry Sync Operations

    /// Whether a watch entry is eligible for iCloud sync.
    /// Local-folder media plays from a per-device path, so syncing its watch progress
    /// to other devices (where the file is not reachable) is wasted noise.
    private func shouldSyncWatchEntry(sourceRawValue: String, externalExtractor: String?) -> Bool {
        !(sourceRawValue == "extracted" && externalExtractor == MediaFile.localFolderProvider)
    }

    private func shouldSyncWatchEntry(_ watchEntry: WatchEntry) -> Bool {
        shouldSyncWatchEntry(sourceRawValue: watchEntry.sourceRawValue, externalExtractor: watchEntry.externalExtractor)
    }

    /// Queue a watch entry for sync (debounced).
    func queueWatchEntrySave(_ watchEntry: WatchEntry) {
        guard canSyncPlaybackHistory else { return }
        guard shouldSyncWatchEntry(watchEntry) else {
            LoggingService.shared.logCloudKit("Skipping local-folder watch entry: \(watchEntry.videoID)")
            return
        }

        let recordID = recordMapper.toCKRecord(watchEntry: watchEntry).recordID
        addPendingChanges([.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued watch entry save: \(watchEntry.videoID)")
    }

    /// Queue a watch entry deletion for sync (debounced).
    func queueWatchEntryDelete(videoID: String, scope: SourceScope) {
        guard canSyncPlaybackHistory else { return }

        let recordID = SyncableRecordType.watchEntry(videoID: videoID, scope: scope).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued watch entry delete: \(videoID)")
    }
    
    /// Upload all existing local watch history to CloudKit (for initial sync).
    /// Call this when enabling iCloud sync for the first time.
    func uploadAllLocalWatchHistory() async {
        guard isSyncEnabled, let dataManager else {
            LoggingService.shared.logCloudKit("Cannot upload: sync disabled or data manager unavailable")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Watch History"
        
        LoggingService.shared.logCloudKit("Starting initial bulk upload of local watch history...")
        
        // Get all local watch history (limit to reasonable amount)
        let watchHistory = dataManager.watchHistory(limit: 5000)
            .filter { shouldSyncWatchEntry($0) }

        guard !watchHistory.isEmpty else {
            LoggingService.shared.logCloudKit("No local watch history to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += watchHistory.count

        let changes = watchHistory.map { entry in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordMapper.toCKRecord(watchEntry: entry).recordID)
        }
        addPendingChanges(changes, debounce: false)

        LoggingService.shared.logCloudKit("Queued \(watchHistory.count) existing watch entries for initial upload")
        
        // Trigger immediate sync (no debounce for initial upload)
        await sync()
    }
    
    // MARK: - Bookmark Sync Operations
    
    /// Queue a bookmark for sync (debounced).
    func queueBookmarkSave(_ bookmark: Bookmark) {
        guard canSyncBookmarks else { return }

        let recordID = recordMapper.toCKRecord(bookmark: bookmark).recordID
        addPendingChanges([.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued bookmark save: \(bookmark.videoID)")
    }

    /// Queue a bookmark deletion for sync (debounced).
    func queueBookmarkDelete(videoID: String, scope: SourceScope) {
        guard canSyncBookmarks else { return }

        let recordID = SyncableRecordType.bookmark(videoID: videoID, scope: scope).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued bookmark delete: \(videoID)")
    }
    
    /// Upload all existing local bookmarks to CloudKit (for initial sync).
    /// Call this when enabling iCloud sync for the first time.
    func uploadAllLocalBookmarks() async {
        guard isSyncEnabled, let dataManager else {
            LoggingService.shared.logCloudKit("Cannot upload: sync disabled or data manager unavailable")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Bookmarks"
        
        LoggingService.shared.logCloudKit("Starting initial bulk upload of local bookmarks...")
        
        // Get all local bookmarks
        let bookmarks = dataManager.bookmarks()
        
        guard !bookmarks.isEmpty else {
            LoggingService.shared.logCloudKit("No local bookmarks to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += bookmarks.count

        let changes = bookmarks.map { bookmark in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordMapper.toCKRecord(bookmark: bookmark).recordID)
        }
        addPendingChanges(changes, debounce: false)

        LoggingService.shared.logCloudKit("Queued \(bookmarks.count) existing bookmarks for initial upload")
        
        // Trigger immediate sync (no debounce for initial upload)
        await sync()
    }
    
    // MARK: - Playlist Sync Operations
    
    /// Queue a playlist for sync (debounced).
    func queuePlaylistSave(_ playlist: LocalPlaylist) {
        guard canSyncPlaylists else { return }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = [
            .saveRecord(SyncableRecordType.localPlaylist(id: playlist.id).recordID(in: zone))
        ]

        // Also queue all items
        for item in playlist.items ?? [] {
            changes.append(.saveRecord(SyncableRecordType.localPlaylistItem(id: item.id).recordID(in: zone)))
        }

        addPendingChanges(changes)
        LoggingService.shared.logCloudKit("Queued playlist save: \(playlist.title)")
    }

    /// Queue a playlist deletion for sync (debounced).
    func queuePlaylistDelete(playlistID: UUID) {
        guard canSyncPlaylists else { return }

        let recordID = SyncableRecordType.localPlaylist(id: playlistID).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued playlist delete: \(playlistID)")
    }

    /// Queue a playlist item deletion for sync (debounced).
    func queuePlaylistItemDelete(itemID: UUID) {
        guard canSyncPlaylists else { return }

        let recordID = SyncableRecordType.localPlaylistItem(id: itemID).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued playlist item delete: \(itemID)")
    }
    
    /// Upload all existing local playlists to CloudKit (for initial sync).
    func uploadAllLocalPlaylists() async {
        guard isSyncEnabled, let dataManager else {
            LoggingService.shared.logCloudKit("Cannot upload: sync disabled or data manager unavailable")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Playlists"
        
        LoggingService.shared.logCloudKit("Starting initial bulk upload of local playlists...")
        
        let playlists = dataManager.playlists()
        guard !playlists.isEmpty else {
            LoggingService.shared.logCloudKit("No local playlists to upload")
            return
        }
        
        // Register all playlists and their items with the sync engine
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for playlist in playlists {
            changes.append(.saveRecord(SyncableRecordType.localPlaylist(id: playlist.id).recordID(in: zone)))

            // Add all items
            for item in playlist.items ?? [] {
                changes.append(.saveRecord(SyncableRecordType.localPlaylistItem(id: item.id).recordID(in: zone)))
            }
        }
        addPendingChanges(changes, debounce: false)

        // Track total operations (playlists + items)
        let totalItems = playlists.reduce(0) { $0 + ($1.items?.count ?? 0) }
        uploadProgress?.totalOperations += playlists.count + totalItems
        
        LoggingService.shared.logCloudKit("Queued \(playlists.count) existing playlists for initial upload")
        await sync()
    }
    
    // MARK: - SearchHistory Sync Operations
    
    /// Queue a search history entry for sync (debounced).
    func queueSearchHistorySave(_ searchHistory: SearchHistory) {
        guard canSyncSearchHistory else { return }

        let recordID = SyncableRecordType.searchHistory(id: searchHistory.id).recordID(in: zone)
        addPendingChanges([.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued search history save: \(searchHistory.query)")
    }

    /// Queue a search history entry deletion for sync (debounced).
    func queueSearchHistoryDelete(id: UUID) {
        guard canSyncSearchHistory else { return }

        let recordID = SyncableRecordType.searchHistory(id: id).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued search history delete: \(id)")
    }
    
    /// Upload all existing local search history to CloudKit (for initial sync).
    func uploadAllLocalSearchHistory() async {
        guard isSyncEnabled, let dataManager else {
            LoggingService.shared.logCloudKit("Cannot upload: sync disabled or data manager unavailable")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Search History"
        
        LoggingService.shared.logCloudKit("Starting initial bulk upload of search history...")
        
        let searchHistory = dataManager.allSearchHistory()
        guard !searchHistory.isEmpty else {
            LoggingService.shared.logCloudKit("No local search history to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += searchHistory.count

        let changes = searchHistory.map { entry in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(SyncableRecordType.searchHistory(id: entry.id).recordID(in: zone))
        }
        addPendingChanges(changes, debounce: false)

        LoggingService.shared.logCloudKit("Queued \(searchHistory.count) search history entries for initial upload")
        await sync()
    }
    
    // MARK: - RecentChannel Sync Operations
    
    /// Queue a recent channel for sync (debounced).
    func queueRecentChannelSave(_ recentChannel: RecentChannel) {
        guard canSyncSearchHistory else { return }

        let recordID = recordMapper.toCKRecord(recentChannel: recentChannel).recordID
        addPendingChanges([.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued recent channel save: \(recentChannel.channelID)")
    }

    /// Queue a recent channel deletion for sync (debounced).
    func queueRecentChannelDelete(channelID: String, scope: SourceScope) {
        guard canSyncSearchHistory else { return }

        let recordID = SyncableRecordType.recentChannel(channelID: channelID, scope: scope).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued recent channel delete: \(channelID)")
    }
    
    /// Upload all existing recent channels to CloudKit (for initial sync).
    func uploadAllRecentChannels() async {
        guard isSyncEnabled, let dataManager else {
            LoggingService.shared.logCloudKit("Cannot upload: sync disabled or data manager unavailable")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Recent Channels"
        
        LoggingService.shared.logCloudKit("Starting initial bulk upload of recent channels...")
        
        let recentChannels = dataManager.allRecentChannels()
        guard !recentChannels.isEmpty else {
            LoggingService.shared.logCloudKit("No recent channels to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += recentChannels.count

        let changes = recentChannels.map { channel in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordMapper.toCKRecord(recentChannel: channel).recordID)
        }
        addPendingChanges(changes, debounce: false)

        LoggingService.shared.logCloudKit("Queued \(recentChannels.count) recent channels for initial upload")
        await sync()
    }
    
    // MARK: - RecentPlaylist Sync Operations
    
    /// Queue a recent playlist for sync (debounced).
    func queueRecentPlaylistSave(_ recentPlaylist: RecentPlaylist) {
        guard canSyncSearchHistory else { return }

        let recordID = recordMapper.toCKRecord(recentPlaylist: recentPlaylist).recordID
        addPendingChanges([.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued recent playlist save: \(recentPlaylist.playlistID)")
    }

    /// Queue a recent playlist deletion for sync (debounced).
    func queueRecentPlaylistDelete(playlistID: String, scope: SourceScope) {
        guard canSyncSearchHistory else { return }

        let recordID = SyncableRecordType.recentPlaylist(playlistID: playlistID, scope: scope).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued recent playlist delete: \(playlistID)")
    }
    
    /// Upload all existing recent playlists to CloudKit (for initial sync).
    func uploadAllRecentPlaylists() async {
        guard isSyncEnabled, let dataManager else {
            LoggingService.shared.logCloudKit("Cannot upload: sync disabled or data manager unavailable")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Recent Playlists"
        
        LoggingService.shared.logCloudKit("Starting initial bulk upload of recent playlists...")
        
        let recentPlaylists = dataManager.allRecentPlaylists()
        guard !recentPlaylists.isEmpty else {
            LoggingService.shared.logCloudKit("No recent playlists to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += recentPlaylists.count

        let changes = recentPlaylists.map { playlist in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordMapper.toCKRecord(recentPlaylist: playlist).recordID)
        }
        addPendingChanges(changes, debounce: false)

        LoggingService.shared.logCloudKit("Queued \(recentPlaylists.count) recent playlists for initial upload")
        await sync()
    }
    
    // MARK: - ChannelNotificationSettings Sync Operations
    
    /// Queue channel notification settings for sync (debounced).
    func queueChannelNotificationSettingsSave(_ settings: ChannelNotificationSettings) {
        guard canSyncSubscriptions else { return }

        let recordID = recordMapper.toCKRecord(channelNotificationSettings: settings).recordID
        addPendingChanges([.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued channel notification settings save: \(settings.channelID)")
    }

    /// Queue channel notification settings deletion for sync (debounced).
    func queueChannelNotificationSettingsDelete(channelID: String, scope: SourceScope) {
        guard canSyncSubscriptions else { return }

        let recordID = SyncableRecordType.channelNotificationSettings(channelID: channelID, scope: scope).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued channel notification settings delete: \(channelID)")
    }
    
    /// Upload all existing channel notification settings to CloudKit (for initial sync).
    func uploadAllLocalChannelNotificationSettings() async {
        guard isSyncEnabled, let dataManager else {
            LoggingService.shared.logCloudKit("Cannot upload: sync disabled or data manager unavailable")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Notification Settings"
        
        LoggingService.shared.logCloudKit("Starting initial bulk upload of channel notification settings...")
        
        let allSettings = dataManager.allChannelNotificationSettings()
        guard !allSettings.isEmpty else {
            LoggingService.shared.logCloudKit("No channel notification settings to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += allSettings.count

        let changes = allSettings.map { settings in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(recordMapper.toCKRecord(channelNotificationSettings: settings).recordID)
        }
        addPendingChanges(changes, debounce: false)

        LoggingService.shared.logCloudKit("Queued \(allSettings.count) channel notification settings for initial upload")
        await sync()
    }
    
    // MARK: - ControlsPreset Sync Operations
    
    /// Upload all local controls presets to CloudKit (for initial sync when enabling category).
    func uploadAllLocalControlsPresets() async {
        guard canSyncControlsPresets else {
            LoggingService.shared.logCloudKit("Cannot upload controls presets: sync disabled or settings category disabled")
            return
        }
        
        // Update progress
        uploadProgress?.currentCategory = "Controls Presets"
        
        LoggingService.shared.logCloudKit("Starting upload of local controls presets...")

        let layoutService = playerControlsLayoutService ?? PlayerControlsLayoutService()
        let presets = await layoutService.presetsForSync()

        guard !presets.isEmpty else {
            LoggingService.shared.logCloudKit("No controls presets to upload")
            return
        }

        // Track total operations
        uploadProgress?.totalOperations += presets.count

        let changes = presets.map { preset in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(SyncableRecordType.controlsPreset(id: preset.id).recordID(in: zone))
        }
        addPendingChanges(changes, debounce: false)

        LoggingService.shared.logCloudKit("Queued \(presets.count) controls presets for upload")
        await sync()
    }
    
    /// Queue a controls preset for sync (debounced).
    func queueControlsPresetSave(_ preset: LayoutPreset) {
        guard canSyncControlsPresets else { return }

        // Only sync non-built-in presets for current device class
        guard !preset.isBuiltIn, preset.deviceClass == .current else { return }

        let recordID = SyncableRecordType.controlsPreset(id: preset.id).recordID(in: zone)
        addPendingChanges([.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued controls preset save: \(preset.name)")
    }

    /// Queue a controls preset deletion for sync (debounced).
    func queueControlsPresetDelete(id: UUID) {
        guard canSyncControlsPresets else { return }

        let recordID = SyncableRecordType.controlsPreset(id: id).recordID(in: zone)
        addPendingChanges([.deleteRecord(recordID)])
        LoggingService.shared.logCloudKit("Queued controls preset delete: \(id)")
    }
    
    /// Registers pending changes with the sync engine state (or buffers them
    /// until the engine is ready) and schedules a debounced send. The engine
    /// state is persisted via `.stateUpdate` events, so registered changes
    /// survive app termination; records are materialized from local data at
    /// send time in `nextRecordZoneChangeBatch`.
    private func addPendingChanges(_ changes: [CKSyncEngine.PendingRecordZoneChange], debounce: Bool = true) {
        guard !changes.isEmpty else { return }

        for change in changes {
            switch change {
            case .saveRecord(let recordID), .deleteRecord(let recordID):
                // A fresh local change supersedes any conflict-resolved record
                // awaiting upload; drop it so the next send uses current data.
                conflictResolvedRecords.removeValue(forKey: recordID.recordName)
            @unknown default:
                break
            }
        }

        if let syncEngine {
            syncEngine.state.add(pendingRecordZoneChanges: changes)
        } else {
            pendingChangesBuffer.append(contentsOf: changes)
        }
        updatePendingCount()

        if debounce {
            scheduleDebounceSync()
        }
    }

    /// Whether a delete for the given record name is pending upload.
    private func hasPendingDelete(recordName: String) -> Bool {
        let matches: (CKSyncEngine.PendingRecordZoneChange) -> Bool = { change in
            if case .deleteRecord(let recordID) = change {
                return recordID.recordName == recordName
            }
            return false
        }
        if pendingChangesBuffer.contains(where: matches) { return true }
        return syncEngine?.state.pendingRecordZoneChanges.contains(where: matches) ?? false
    }

    /// Refreshes the observable pending count from the engine state.
    private func updatePendingCount() {
        pendingChangesCount = (syncEngine?.state.pendingRecordZoneChanges.count ?? 0) + pendingChangesBuffer.count
    }

    /// Schedule a debounced sync after changes.
    private func scheduleDebounceSync() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Guard against timer firing after disable() has cleared state
                guard let self, self.debounceTimer != nil else { return }
                await self.sync()
            }
        }
    }
    
    /// Immediately sync all pending changes without debounce.
    /// Call this when the app is about to enter background to prevent data loss.
    func flushPendingChanges() async {
        debounceTimer?.invalidate()
        debounceTimer = nil

        updatePendingCount()
        guard pendingChangesCount > 0 else { return }

        LoggingService.shared.logCloudKit("Flushing \(pendingChangesCount) pending changes before background")
        await sync()
    }

    /// Handle a remote push notification by fetching changes from CloudKit.
    /// Called from AppDelegate's `didReceiveRemoteNotification`.
    func handleRemoteNotification() {
        guard isSyncEnabled, syncEngine != nil else {
            LoggingService.shared.logCloudKit("handleRemoteNotification: sync engine not ready, ignoring")
            return
        }
        LoggingService.shared.logCloudKit("Handling remote notification — fetching changes")
        Task {
            await fetchRemoteChanges()
        }
    }

    /// Fetch remote changes from CloudKit. Used when the app returns to foreground
    /// to catch any changes that may have been missed (e.g. dropped push notifications).
    func fetchRemoteChanges() async {
        guard isSyncEnabled, let syncEngine else {
            if !isSyncEnabled {
                LoggingService.shared.logCloudKit("fetchRemoteChanges skipped: sync disabled")
            } else {
                LoggingService.shared.logCloudKit("fetchRemoteChanges skipped: sync engine not ready (nil)")
            }
            return
        }

        LoggingService.shared.logCloudKit("Fetching remote changes on foreground")

        do {
            try await syncEngine.fetchChanges()
            lastSyncDate = Date()
            settingsManager?.updateLastSyncTime()
            LoggingService.shared.logCloudKit("Foreground fetch completed")
        } catch {
            LoggingService.shared.logCloudKitError("Foreground fetch failed", error: error)
        }
    }

    /// Start periodic foreground polling as a fallback for missed push notifications.
    /// The timer fires every 3 minutes and fetches remote changes.
    func startForegroundPolling() {
        guard foregroundPollTimer == nil else { return }
        LoggingService.shared.logCloudKit("Starting foreground polling (every \(Int(foregroundPollInterval))s)")
        foregroundPollTimer = Timer.scheduledTimer(withTimeInterval: foregroundPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchRemoteChanges()
            }
        }
    }

    /// Stop periodic foreground polling (e.g. when app enters background).
    func stopForegroundPolling() {
        guard foregroundPollTimer != nil else { return }
        foregroundPollTimer?.invalidate()
        foregroundPollTimer = nil
        LoggingService.shared.logCloudKit("Stopped foreground polling")
    }

    /// One-time migration of pending changes persisted by the previous
    /// array-based queue. Both saves and deletes are recovered by record
    /// name — save records are materialized from local data at send time.
    private func migrateLegacyPendingChanges(into engine: CKSyncEngine) {
        let defaults = UserDefaults.standard
        let saveNames = defaults.stringArray(forKey: pendingSaveRecordNamesKey) ?? []
        let deleteNames = defaults.stringArray(forKey: pendingDeleteRecordNamesKey) ?? []
        guard !saveNames.isEmpty || !deleteNames.isEmpty else { return }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for name in saveNames {
            changes.append(.saveRecord(CKRecord.ID(recordName: name, zoneID: zone.zoneID)))
        }
        for name in deleteNames {
            changes.append(.deleteRecord(CKRecord.ID(recordName: name, zoneID: zone.zoneID)))
        }
        engine.state.add(pendingRecordZoneChanges: changes)

        defaults.removeObject(forKey: pendingSaveRecordNamesKey)
        defaults.removeObject(forKey: pendingDeleteRecordNamesKey)
        LoggingService.shared.logCloudKit("Migrated \(saveNames.count) legacy pending saves, \(deleteNames.count) legacy pending deletes")
    }

    // MARK: - Deferred Playlist Item Management

    /// Load deferred playlist items from UserDefaults.
    private func loadDeferredItems() {
        guard let data = UserDefaults.standard.data(forKey: deferredPlaylistItemsKey) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            deferredPlaylistItems = try decoder.decode([DeferredPlaylistItem].self, from: data)
            if !deferredPlaylistItems.isEmpty {
                LoggingService.shared.logCloudKit("Loaded \(deferredPlaylistItems.count) deferred playlist items from previous session")
            }
        } catch {
            LoggingService.shared.logCloudKitError("Failed to load deferred playlist items", error: error)
            deferredPlaylistItems = []
        }
    }

    /// Persist deferred playlist items to UserDefaults.
    private func persistDeferredItems() {
        if deferredPlaylistItems.isEmpty {
            UserDefaults.standard.removeObject(forKey: deferredPlaylistItemsKey)
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(deferredPlaylistItems)
            UserDefaults.standard.set(data, forKey: deferredPlaylistItemsKey)
            LoggingService.shared.logCloudKit("Persisted \(deferredPlaylistItems.count) deferred playlist items")
        } catch {
            LoggingService.shared.logCloudKitError("Failed to persist deferred playlist items", error: error)
        }
    }

    /// Clear persisted deferred playlist items.
    private func clearDeferredItems() {
        deferredPlaylistItems.removeAll()
        UserDefaults.standard.removeObject(forKey: deferredPlaylistItemsKey)
    }

    /// Retry deferred playlist items and create placeholders for items that exceed max retries.
    private func retryDeferredItems(dataManager: DataManager) async {
        guard !deferredPlaylistItems.isEmpty else { return }

        LoggingService.shared.logCloudKit("Retrying \(deferredPlaylistItems.count) deferred playlist items...")

        var itemsToKeep: [DeferredPlaylistItem] = []
        var successCount = 0

        for var deferredItem in deferredPlaylistItems {
            // Drop items whose parent playlist is pending deletion
            let playlistRecordName = "playlist-\(deferredItem.playlistID)"
            if hasPendingDelete(recordName: playlistRecordName) {
                LoggingService.shared.logCloudKit("Dropping deferred item (parent playlist pending delete): \(deferredItem.itemID)")
                continue
            }

            // Increment retry count
            deferredItem.retryCount += 1

            // Try to get the CKRecord
            guard let record = try? deferredItem.toCKRecord() else {
                LoggingService.shared.logCloudKitError("Failed to deserialize deferred record", error: NSError(domain: "CloudKitSyncEngine", code: -1, userInfo: nil))
                continue
            }

            // Try to find the parent playlist
            guard let playlistID = UUID(uuidString: deferredItem.playlistID) else {
                continue
            }

            if dataManager.playlist(forID: playlistID) != nil {
                // Parent playlist exists - apply the record
                let result = await applyRemoteRecord(record, to: dataManager)
                if case .success = result {
                    successCount += 1
                    LoggingService.shared.logCloudKit("Successfully applied deferred item on retry \(deferredItem.retryCount): \(deferredItem.itemID)")
                } else if case .deferred = result {
                    // Still deferred (shouldn't happen if parent exists, but handle gracefully)
                    if deferredItem.retryCount < maxDeferralRetries {
                        itemsToKeep.append(deferredItem)
                    } else {
                        // Create placeholder after max retries even in this edge case
                        await createPlaceholderAndAttachItem(record: record, playlistID: playlistID, itemID: UUID(uuidString: deferredItem.itemID), dataManager: dataManager)
                    }
                }
            } else if deferredItem.retryCount >= maxDeferralRetries {
                // Max retries exceeded - create placeholder playlist
                LoggingService.shared.logCloudKit("Max retries (\(maxDeferralRetries)) exceeded for item \(deferredItem.itemID) - creating placeholder playlist")
                await createPlaceholderAndAttachItem(record: record, playlistID: playlistID, itemID: UUID(uuidString: deferredItem.itemID), dataManager: dataManager)
            } else {
                // Keep for next retry
                itemsToKeep.append(deferredItem)
                LoggingService.shared.logCloudKit("Keeping item \(deferredItem.itemID) for retry \(deferredItem.retryCount + 1)/\(maxDeferralRetries)")
            }
        }

        deferredPlaylistItems = itemsToKeep
        LoggingService.shared.logCloudKit("Retry complete: \(successCount) succeeded, \(itemsToKeep.count) still deferred")
    }

    /// Creates a placeholder playlist and attaches the orphaned item to it.
    private func createPlaceholderAndAttachItem(record: CKRecord, playlistID: UUID, itemID: UUID?, dataManager: DataManager) async {
        // Check if placeholder already exists for this playlist ID
        if let existingPlaylist = dataManager.playlist(forID: playlistID) {
            // Playlist arrived while we were processing - just attach the item
            await attachItemToPlaylist(record: record, playlist: existingPlaylist, dataManager: dataManager)
            return
        }

        // Create placeholder playlist
        let placeholder = LocalPlaylist(
            id: playlistID,
            title: "Syncing...",
            description: "This playlist is waiting for data from iCloud"
        )
        placeholder.isPlaceholder = true

        dataManager.insertPlaylist(placeholder)
        LoggingService.shared.logCloudKit("Created placeholder playlist: \(playlistID)")

        // Attach the item
        await attachItemToPlaylist(record: record, playlist: placeholder, dataManager: dataManager)

        // Post notification to update UI
        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
    }

    /// Attaches a playlist item record to an existing playlist.
    private func attachItemToPlaylist(record: CKRecord, playlist: LocalPlaylist, dataManager: DataManager) async {
        do {
            let (item, _) = try recordMapper.toLocalPlaylistItem(from: record)
            item.playlist = playlist
            dataManager.insertPlaylistItem(item)
            LoggingService.shared.logCloudKit("Attached item \(item.id) to playlist \(playlist.id)")
        } catch {
            LoggingService.shared.logCloudKitError("Failed to attach item to playlist", error: error)
        }
    }

    /// Refreshes sync by clearing local sync state (tokens) without deleting the CloudKit zone.
    /// This forces CKSyncEngine to re-fetch all changes from scratch on next sync.
    /// Unlike `resetSync()`, this preserves all CloudKit records.
    func refreshSync() async {
        guard isSyncEnabled else {
            LoggingService.shared.logCloudKit("Refresh sync skipped: sync disabled")
            return
        }

        LoggingService.shared.logCloudKit("Refreshing sync state (clearing local tokens)...")

        // Clear local sync state so CKSyncEngine fetches everything fresh
        UserDefaults.standard.removeObject(forKey: syncStateKey)

        // Tear down existing engine
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingChangesBuffer.removeAll()
        conflictResolvedRecords.removeAll()
        retryCount.removeAll()
        syncEngine = nil
        updatePendingCount()

        // Reinitialize - with the persisted state cleared above, setup starts
        // from nil state serialization (forces full fetch)
        await setupSyncEngine()

        LoggingService.shared.logCloudKit("Refresh sync completed")
    }

    /// Clear all sync state and reset. For testing/debugging only.
    func resetSync() async throws {
        // Delete zone (and all records)
        try await zoneManager.deleteZone()

        // Clear pending changes
        pendingChangesBuffer.removeAll()
        conflictResolvedRecords.removeAll()
        retryCount.removeAll()
        syncEngine = nil
        updatePendingCount()

        // Clear sync state
        UserDefaults.standard.removeObject(forKey: syncStateKey)
        clearDeferredItems()
        
        // Recreate zone
        try await zoneManager.createZoneIfNeeded()
        
        // Reinitialize sync engine
        await setupSyncEngine()
        
        LoggingService.shared.logCloudKit("Sync reset completed")
    }
    
    // MARK: - Account Status
    
    /// Refreshes the cached iCloud account status
    func refreshAccountStatus() async {
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            LoggingService.shared.logCloudKitError("Failed to check account status", error: error)
            accountStatus = .couldNotDetermine
        }
    }
    
    // MARK: - Error Filtering
    
    /// Determines if an error should be shown to the user in the UI.
    /// Filters out expected conflict errors that are automatically resolved.
    private func shouldShowError(_ error: Error) -> Bool {
        // Unwrap CKError
        guard let ckError = error as? CKError else {
            // Non-CloudKit errors should always be shown
            return true
        }
        
        switch ckError.code {
        case .serverRecordChanged:
            // This is a conflict - handled automatically by conflict resolver
            // Only show if message is NOT about "already exists"
            let errorMessage = ckError.localizedDescription.lowercased()
            if errorMessage.contains("already exists") || errorMessage.contains("record to insert") {
                return false // Conflict error - don't show in UI
            }
            return true // Other serverRecordChanged errors - show them
            
        case .partialFailure:
            // Check if ALL sub-errors are conflicts
            // If any sub-error is NOT a conflict, show the error
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                let hasNonConflictError = partialErrors.values.contains { subError in
                    guard let subCKError = subError as? CKError else { return true }
                    
                    // Check if this sub-error is a conflict
                    if subCKError.code == .serverRecordChanged {
                        let message = subCKError.localizedDescription.lowercased()
                        if message.contains("already exists") || message.contains("record to insert") {
                            return false // This is a conflict
                        }
                    }
                    return true // This is NOT a conflict
                }
                
                // Only show if there's at least one non-conflict error
                return hasNonConflictError
            }
            return true // Can't parse partial errors - show it to be safe
            
        default:
            // All other errors should be shown
            return true
        }
    }
    
    // MARK: - Initial Upload Coordination
    
    /// Performs full initial upload of all local data with progress tracking
    func performInitialUpload() async {
        guard isSyncEnabled else { return }
        
        uploadProgress = UploadProgress(
            currentCategory: "Starting...",
            isComplete: false,
            totalOperations: 0
        )
        
        // Upload each category sequentially with progress updates
        await uploadAllLocalSubscriptions()
        await uploadAllLocalWatchHistory()
        await uploadAllLocalBookmarks()
        await uploadAllLocalPlaylists()
        await uploadAllLocalSearchHistory()
        await uploadAllRecentChannels()
        await uploadAllRecentPlaylists()
        await uploadAllLocalChannelNotificationSettings()
        await uploadAllLocalControlsPresets()
        
        // Mark complete
        uploadProgress = UploadProgress(
            currentCategory: "Complete",
            isComplete: true,
            totalOperations: uploadProgress?.totalOperations ?? 0
        )
        
        // Clear after 3 seconds
        Task {
            try? await Task.sleep(for: .seconds(3))
            uploadProgress = nil
        }
    }
    
    // MARK: - Error Handling
    
    private func handleSyncError(_ error: Error) {
        guard let ckError = error as? CKError else {
            return
        }
        
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            LoggingService.shared.logCloudKit("Network unavailable, will retry when connection returns")
            scheduleRetry(delay: 30)
            
        case .quotaExceeded:
            LoggingService.shared.logCloudKitError("CloudKit quota exceeded", error: error)
            syncError = CloudKitError.quotaExceeded
            
        case .notAuthenticated:
            LoggingService.shared.logCloudKitError("User not signed into iCloud", error: error)
            syncError = CloudKitError.notAuthenticated
            
        case .zoneNotFound:
            LoggingService.shared.logCloudKit("Zone not found, recreating...")
            Task {
                try? await zoneManager.createZoneIfNeeded()
                await sync()
            }
            
        case .partialFailure:
            LoggingService.shared.logCloudKitError("Partial sync failure", error: error)
            if let partialErrors = ckError.partialErrorsByItemID {
                for (id, itemError) in partialErrors {
                    if let itemCKError = itemError as? CKError {
                        switch itemCKError.code {
                        case .serverRecordChanged:
                            // Record already exists - this is OK, we'll fetch it on next sync
                            LoggingService.shared.logCloudKit("Record already exists in CloudKit, will merge on next fetch: \(id)")
                            
                        default:
                            LoggingService.shared.logCloudKitError("Failed to sync record: \(id)", error: itemError)
                        }
                    } else {
                        LoggingService.shared.logCloudKitError("Failed to sync record: \(id)", error: itemError)
                    }
                }
            }
            
        default:
            LoggingService.shared.logCloudKitError("CloudKit error: \(ckError.code.rawValue)", error: error)
        }
    }
    
    private func scheduleRetry(delay: TimeInterval) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            await sync()
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudKitSyncEngine: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // Events that require async processing must be awaited directly (not in a fire-and-forget Task)
        // so that CKSyncEngine waits for processing to complete before advancing the sync state token.
        // Otherwise the state is saved before changes are applied, and on next launch CKSyncEngine
        // thinks those changes were already processed.
        switch event {
        case .fetchedRecordZoneChanges(let changes):
            await MainActor.run {
                LoggingService.shared.logCloudKit("Fetched \(changes.modifications.count) modifications, \(changes.deletions.count) deletions")
            }
            await handleFetchedChanges(changes)

        case .sentRecordZoneChanges(let changes):
            await handleSentRecordZoneChanges(changes)

        case .fetchedDatabaseChanges(let changes):
            await handleFetchedDatabaseChanges(changes)

        default:
            await MainActor.run {
                switch event {
                case .stateUpdate(let update):
                    let encoder = PropertyListEncoder()
                    let stateSize = (try? encoder.encode(update.stateSerialization))?.count ?? 0
                    LoggingService.shared.logCloudKit("Sync state updated and saved (\(stateSize) bytes)")
                    saveSyncState(update.stateSerialization)
                    updatePendingCount()

                case .accountChange:
                    LoggingService.shared.logCloudKit("iCloud account change event received - reinitializing sync engine")
                    Task.detached { [weak self] in
                        await self?.setupSyncEngine()
                    }

                case .willFetchChanges:
                    LoggingService.shared.logCloudKit("CKSyncEngine will fetch changes (auto-triggered)")
                    isReceivingChanges = true

                case .didFetchChanges:
                    LoggingService.shared.logCloudKit("CKSyncEngine finished fetching changes")
                    isReceivingChanges = false

                case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .willSendChanges, .didSendChanges, .sentDatabaseChanges:
                    break

                default:
                    LoggingService.shared.logCloudKit("Unknown sync engine event")
                }
            }
        }
    }
    
    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pendingChanges.isEmpty else { return nil }

        await MainActor.run {
            LoggingService.shared.logCloudKit("Preparing batch from \(pendingChanges.count) pending changes")
        }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) { [weak self] recordID in
            await self?.recordToSave(for: recordID, engine: syncEngine)
        }
    }

    /// Provides the record for a pending save at send time, materialized from
    /// current local data. Returns nil (and removes the pending change) when
    /// the entity no longer exists locally or is no longer syncable.
    private func recordToSave(for recordID: CKRecord.ID, engine: CKSyncEngine) async -> CKRecord? {
        let recordName = recordID.recordName

        // A conflict-resolved record (carrying the server change tag) takes precedence
        if let resolved = conflictResolvedRecords[recordName] {
            return resolved
        }

        if let record = await materializeRecord(named: recordName) {
            return record
        }

        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        LoggingService.shared.logCloudKit("Skipping save for \(recordName) — no matching local data")
        return nil
    }

    // MARK: - Scope-Aware Local Lookups

    /// Bare-ID lookups can return an entity from a different source scope when
    /// IDs collide across sources; these helpers match on the mapper-derived
    /// record name so the right entity is merged, materialized, or deleted.
    private func localSubscription(matching recordName: String, channelID: String, in dataManager: DataManager) -> Subscription? {
        dataManager.subscriptions(forChannelID: channelID).first {
            recordMapper.toCKRecord(subscription: $0).recordID.recordName == recordName
        }
    }

    private func localWatchEntry(matching recordName: String, videoID: String, in dataManager: DataManager) -> WatchEntry? {
        dataManager.watchEntries(forVideoID: videoID).first {
            recordMapper.toCKRecord(watchEntry: $0).recordID.recordName == recordName
        }
    }

    private func localBookmark(matching recordName: String, videoID: String, in dataManager: DataManager) -> Bookmark? {
        dataManager.bookmarks(forVideoID: videoID).first {
            recordMapper.toCKRecord(bookmark: $0).recordID.recordName == recordName
        }
    }

    private func localRecentChannel(matching recordName: String, channelID: String, in dataManager: DataManager) -> RecentChannel? {
        dataManager.recentChannelEntries(forChannelID: channelID).first {
            recordMapper.toCKRecord(recentChannel: $0).recordID.recordName == recordName
        }
    }

    private func localRecentPlaylist(matching recordName: String, playlistID: String, in dataManager: DataManager) -> RecentPlaylist? {
        dataManager.recentPlaylistEntries(forPlaylistID: playlistID).first {
            recordMapper.toCKRecord(recentPlaylist: $0).recordID.recordName == recordName
        }
    }

    private func localChannelNotificationSettings(matching recordName: String, channelID: String, in dataManager: DataManager) -> ChannelNotificationSettings? {
        dataManager.allChannelNotificationSettings(forChannelID: channelID).first {
            recordMapper.toCKRecord(channelNotificationSettings: $0).recordID.recordName == recordName
        }
    }

    /// Builds a CKRecord for the given record name from current local data.
    /// The record name prefix identifies the entity type; the local entity is
    /// matched on the full scoped record name (a mismatch means it belongs to
    /// a different source scope).
    private func materializeRecord(named recordName: String) async -> CKRecord? {
        guard let dataManager else { return nil }

        if recordName.hasPrefix("sub-") {
            guard canSyncSubscriptions else { return nil }
            let channelID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(4)))
            guard let subscription = localSubscription(matching: recordName, channelID: channelID, in: dataManager) else { return nil }
            return recordMapper.toCKRecord(subscription: subscription)
        }
        if recordName.hasPrefix("watch-") {
            guard canSyncPlaybackHistory else { return nil }
            let videoID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(6)))
            guard let entry = localWatchEntry(matching: recordName, videoID: videoID, in: dataManager),
                  shouldSyncWatchEntry(entry) else { return nil }
            return recordMapper.toCKRecord(watchEntry: entry)
        }
        if recordName.hasPrefix("bookmark-") {
            guard canSyncBookmarks else { return nil }
            let videoID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(9)))
            guard let bookmark = localBookmark(matching: recordName, videoID: videoID, in: dataManager) else { return nil }
            return recordMapper.toCKRecord(bookmark: bookmark)
        }
        if recordName.hasPrefix("recent-channel-") {
            guard canSyncSearchHistory else { return nil }
            let channelID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(15)))
            guard let recentChannel = localRecentChannel(matching: recordName, channelID: channelID, in: dataManager) else { return nil }
            return recordMapper.toCKRecord(recentChannel: recentChannel)
        }
        if recordName.hasPrefix("recent-playlist-") {
            guard canSyncSearchHistory else { return nil }
            let playlistID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(16)))
            guard let recentPlaylist = localRecentPlaylist(matching: recordName, playlistID: playlistID, in: dataManager) else { return nil }
            return recordMapper.toCKRecord(recentPlaylist: recentPlaylist)
        }
        if recordName.hasPrefix("channel-notif-") {
            guard canSyncSubscriptions else { return nil }
            let channelID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(14)))
            guard let settings = localChannelNotificationSettings(matching: recordName, channelID: channelID, in: dataManager) else { return nil }
            return recordMapper.toCKRecord(channelNotificationSettings: settings)
        }
        if recordName.hasPrefix("playlist-") {
            guard canSyncPlaylists,
                  let id = UUID(uuidString: String(recordName.dropFirst(9))),
                  let playlist = dataManager.playlist(forID: id),
                  !playlist.isPlaceholder else { return nil }
            return recordMapper.toCKRecord(playlist: playlist)
        }
        if recordName.hasPrefix("item-") {
            guard canSyncPlaylists,
                  let id = UUID(uuidString: String(recordName.dropFirst(5))),
                  let item = dataManager.playlistItem(forID: id) else { return nil }
            return recordMapper.toCKRecord(playlistItem: item)
        }
        if recordName.hasPrefix("search-") {
            guard canSyncSearchHistory,
                  let id = UUID(uuidString: String(recordName.dropFirst(7))),
                  let entry = dataManager.searchHistoryEntry(forID: id) else { return nil }
            return recordMapper.toCKRecord(searchHistory: entry)
        }
        if recordName.hasPrefix("controls-") {
            guard canSyncControlsPresets,
                  let id = UUID(uuidString: String(recordName.dropFirst(9))) else { return nil }
            let layoutService = playerControlsLayoutService ?? PlayerControlsLayoutService()
            let presets = await layoutService.presetsForSync()
            guard let preset = presets.first(where: { $0.id == id }) else { return nil }
            return try? recordMapper.toCKRecord(preset: preset)
        }

        LoggingService.shared.logCloudKit("Cannot materialize record with unknown prefix: \(recordName)")
        return nil
    }

    /// Handle the result of a sent batch: clean up bookkeeping for successes
    /// and decide per-record how to handle failures.
    private func handleSentRecordZoneChanges(_ changes: CKSyncEngine.Event.SentRecordZoneChanges) async {
        LoggingService.shared.logCloudKit("Sent \(changes.savedRecords.count) saves, \(changes.deletedRecordIDs.count) deletions (\(changes.failedRecordSaves.count) failed saves, \(changes.failedRecordDeletes.count) failed deletes)")

        for record in changes.savedRecords {
            let recordName = record.recordID.recordName
            conflictResolvedRecords.removeValue(forKey: recordName)
            retryCount.removeValue(forKey: recordName)
        }

        for failedSave in changes.failedRecordSaves {
            await handleFailedRecordSave(failedSave)
        }

        for (recordID, error) in changes.failedRecordDeletes {
            handleFailedRecordDelete(recordID: recordID, error: error)
        }

        updatePendingCount()
    }

    /// Handle a failed record save. Retryable failures are re-registered with
    /// the engine state (the engine schedules the retry with proper backoff),
    /// conflicts are merged and re-sent; only genuinely fatal errors drop the
    /// change.
    private func handleFailedRecordSave(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) async {
        let record = failedSave.record
        let error = failedSave.error
        let recordID = record.recordID
        let recordName = recordID.recordName

        switch error.code {
        case .serverRecordChanged:
            guard let serverRecord = error.serverRecord else {
                LoggingService.shared.logCloudKitError("No server record in conflict error for \(recordName)", error: error)
                conflictResolvedRecords.removeValue(forKey: recordName)
                return
            }

            let attempts = retryCount[recordName] ?? 0
            guard attempts < maxRetryAttempts else {
                LoggingService.shared.logCloudKitError(
                    "Record \(recordName) failed after \(maxRetryAttempts) conflict resolution attempts, giving up",
                    error: error
                )
                conflictResolvedRecords.removeValue(forKey: recordName)
                retryCount.removeValue(forKey: recordName)
                return
            }
            retryCount[recordName] = attempts + 1

            // Merge the record we tried to send with the server's version.
            // The resolved record keeps the server change tag, so the retry
            // is accepted as an update.
            let resolved = await resolveConflict(local: record, server: serverRecord)
            conflictResolvedRecords[recordName] = resolved
            syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            LoggingService.shared.logCloudKit("Resolved \(serverRecord.recordType) conflict for \(recordName), retrying (attempt \(attempts + 1))")

        case .unknownItem:
            // Record vanished server-side while we held its change tag —
            // drop the cached record and retry as a fresh insert.
            conflictResolvedRecords.removeValue(forKey: recordName)
            syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            LoggingService.shared.logCloudKit("Record \(recordName) missing on server, retrying as insert")

        case .zoneNotFound:
            // Zone was deleted — recreate it and retry the save
            syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            Task {
                try? await zoneManager.createZoneIfNeeded()
            }
            LoggingService.shared.logCloudKit("Zone missing for \(recordName), recreating and retrying")

        case .zoneBusy, .serviceUnavailable, .requestRateLimited, .networkFailure, .networkUnavailable,
             .notAuthenticated, .accountTemporarilyUnavailable, .batchRequestFailed, .limitExceeded:
            // Transient — keep the change pending; the engine retries with backoff
            syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            LoggingService.shared.logCloudKit("Transient error (\(error.code.rawValue)) for \(recordName), will retry")

        default:
            conflictResolvedRecords.removeValue(forKey: recordName)
            retryCount.removeValue(forKey: recordName)
            LoggingService.shared.logCloudKitError("Unrecoverable error for \(recordName), dropping change", error: error)
        }
    }

    /// Handle a failed record deletion. Retryable failures are re-registered
    /// with the engine state; a record already missing on the server is done.
    private func handleFailedRecordDelete(recordID: CKRecord.ID, error: CKError) {
        switch error.code {
        case .unknownItem, .zoneNotFound:
            // Already gone on the server — nothing to do
            break

        case .zoneBusy, .serviceUnavailable, .requestRateLimited, .networkFailure, .networkUnavailable,
             .notAuthenticated, .accountTemporarilyUnavailable, .batchRequestFailed, .limitExceeded:
            syncEngine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            LoggingService.shared.logCloudKit("Transient error (\(error.code.rawValue)) deleting \(recordID.recordName), will retry")

        default:
            LoggingService.shared.logCloudKitError("Unrecoverable error deleting \(recordID.recordName), dropping change", error: error)
        }
    }

    /// Applies type-specific conflict resolution between the record we tried
    /// to send and the server's current version.
    private func resolveConflict(local: CKRecord, server: CKRecord) async -> CKRecord {
        switch server.recordType {
        case RecordType.subscription:
            return await conflictResolver.resolveSubscriptionConflict(local: local, server: server)
        case RecordType.watchEntry:
            return await conflictResolver.resolveWatchEntryConflict(local: local, server: server)
        case RecordType.bookmark:
            return await conflictResolver.resolveBookmarkConflict(local: local, server: server)
        case RecordType.localPlaylist:
            return await conflictResolver.resolveLocalPlaylistConflict(local: local, server: server)
        case RecordType.localPlaylistItem:
            return await conflictResolver.resolveLocalPlaylistItemConflict(local: local, server: server)
        case RecordType.searchHistory:
            return await conflictResolver.resolveSearchHistoryConflict(local: local, server: server)
        case RecordType.recentChannel:
            return await conflictResolver.resolveRecentChannelConflict(local: local, server: server)
        case RecordType.recentPlaylist:
            return await conflictResolver.resolveRecentPlaylistConflict(local: local, server: server)
        case RecordType.controlsPreset:
            return await conflictResolver.resolveLayoutPresetConflict(local: local, server: server)
        default:
            // Unknown type - use server version (safe fallback)
            LoggingService.shared.logCloudKit("Unknown record type \(server.recordType), using server version")
            return server
        }
    }
    
    /// Handle fetched database-level changes (zone creations/deletions).
    /// Now that the engine resumes from persisted state, a remote deletion of our
    /// zone (reset from another device, iCloud data purge, encrypted data reset)
    /// would leave sync silently dead - recreate the zone and re-seed it from
    /// local data.
    private func handleFetchedDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) async {
        LoggingService.shared.logCloudKit("Fetched database changes")

        guard changes.deletions.contains(where: { $0.zoneID.zoneName == RecordType.zoneName }) else {
            return
        }

        LoggingService.shared.logCloudKit("Zone '\(RecordType.zoneName)' was deleted remotely - recreating and re-uploading local data")
        UserDefaults.standard.removeObject(forKey: syncStateKey)

        // Cached conflict records hold change tags from the deleted zone
        conflictResolvedRecords.removeAll()
        retryCount.removeAll()

        do {
            try await zoneManager.createZoneIfNeeded()
            await performInitialUpload()
        } catch {
            LoggingService.shared.logCloudKitError("Failed to recreate zone after remote deletion", error: error)
        }
    }

    /// Handle fetched changes from CloudKit.
    private func handleFetchedChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        guard let dataManager else { return }

        // Load persisted deferred items from previous sessions
        loadDeferredItems()

        // Track newly deferred playlist items from this batch
        var newlyDeferredItems: [(record: CKRecord, playlistID: UUID, itemID: UUID)] = []

        // Apply modifications - process all incoming records
        for modification in changes.modifications {
            let result = await applyRemoteRecord(modification.record, to: dataManager)
            if case .deferred(let playlistID, let itemID) = result {
                newlyDeferredItems.append((modification.record, playlistID, itemID))
            }
        }

        // Add newly deferred items to the persistent queue
        for (record, playlistID, itemID) in newlyDeferredItems {
            if let deferredItem = try? DeferredPlaylistItem(record: record, playlistID: playlistID, itemID: itemID) {
                // Check if already in the deferred list (avoid duplicates)
                if !deferredPlaylistItems.contains(where: { $0.itemID == deferredItem.itemID }) {
                    deferredPlaylistItems.append(deferredItem)
                    LoggingService.shared.logCloudKit("Added item to deferred queue: \(itemID), playlist: \(playlistID)")
                }
            }
        }

        // Retry ALL deferred items (including from previous sessions)
        await retryDeferredItems(dataManager: dataManager)

        // Persist remaining deferred items for next sync
        persistDeferredItems()

        // Clean up placeholders whose parent playlist is pending deletion
        let allPlaylists = dataManager.playlists()
        for playlist in allPlaylists where playlist.isPlaceholder {
            let playlistRecordName = "playlist-\(playlist.id.uuidString)"
            if hasPendingDelete(recordName: playlistRecordName) {
                dataManager.deletePlaylist(playlist)
                LoggingService.shared.logCloudKit("Cleaned up placeholder for deleted playlist: \(playlist.id)")
            }
        }

        // Apply deletions
        for deletion in changes.deletions {
            await applyRemoteDeletion(deletion.recordID, to: dataManager)
        }

        // Update last sync date when receiving changes from other devices
        if !changes.modifications.isEmpty || !changes.deletions.isEmpty {
            lastSyncDate = Date()
            settingsManager?.updateLastSyncTime()
            LoggingService.shared.logCloudKit("Updated lastSyncDate after receiving \(changes.modifications.count) modifications, \(changes.deletions.count) deletions")
        }
    }
    
    /// Apply a remote record change to local SwiftData.
    /// Returns the result indicating success, deferral (for playlist items without parent), or failure.
    @discardableResult
    private func applyRemoteRecord(_ record: CKRecord, to dataManager: DataManager) async -> ApplyRecordResult {
        // Skip records that are pending local deletion
        if hasPendingDelete(recordName: record.recordID.recordName) {
            LoggingService.shared.logCloudKit("Skipping incoming record (pending local delete): \(record.recordID.recordName)")
            return .success
        }

        // For playlist items, also skip if parent playlist is pending deletion
        if record.recordType == RecordType.localPlaylistItem,
           let playlistIDString = record["playlistID"] as? String {
            let playlistRecordName = "playlist-\(playlistIDString)"
            if hasPendingDelete(recordName: playlistRecordName) {
                LoggingService.shared.logCloudKit("Skipping playlist item (parent playlist pending delete): \(record.recordID.recordName)")
                return .success
            }
        }

        do {
            switch record.recordType {
            case RecordType.subscription:
                guard canSyncSubscriptions else { return .success }
                let subscription = try recordMapper.toSubscription(from: record)
                
                // Check if exists locally (same source scope only)
                if let existing = localSubscription(matching: record.recordID.recordName, channelID: subscription.channelID, in: dataManager) {
                    let localWasNewer = existing.lastUpdatedAt > subscription.lastUpdatedAt

                    // Conflict - resolve it
                    let localRecord = recordMapper.toCKRecord(subscription: existing)
                    let resolved = await conflictResolver.resolveSubscriptionConflict(local: localRecord, server: record)
                    let resolvedSubscription = try recordMapper.toSubscription(from: resolved)
                    
                    // Update existing subscription with resolved data
                    existing.name = resolvedSubscription.name
                    existing.channelDescription = resolvedSubscription.channelDescription
                    existing.subscriberCount = resolvedSubscription.subscriberCount
                    existing.avatarURLString = resolvedSubscription.avatarURLString
                    existing.bannerURLString = resolvedSubscription.bannerURLString
                    existing.isVerified = resolvedSubscription.isVerified
                    existing.lastUpdatedAt = resolvedSubscription.lastUpdatedAt
                    existing.providerName = resolvedSubscription.providerName
                    
                    dataManager.save()
                    
                    // Post notification for UI updates after conflict resolution
                    NotificationCenter.default.post(name: .subscriptionsDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Merged subscription from iCloud (conflict resolved): \(subscription.channelID)")

                    // Push the merge result back when local data won - the
                    // server still has the older version
                    if localWasNewer {
                        addPendingChanges([.saveRecord(record.recordID)])
                    }
                } else {
                    // New subscription from iCloud
                    dataManager.insertSubscription(subscription)
                    
                    // Post notification to update UI
                    let change = SubscriptionChange(addedSubscriptions: [subscription], removedChannelIDs: [])
                    NotificationCenter.default.post(
                        name: .subscriptionsDidChange,
                        object: nil,
                        userInfo: [SubscriptionChange.userInfoKey: change]
                    )
                    
                    LoggingService.shared.logCloudKit("Added subscription from iCloud: \(subscription.channelID)")
                }
                
            case RecordType.watchEntry:
                guard canSyncPlaybackHistory else { return .success }
                let watchEntry = try recordMapper.toWatchEntry(from: record)

                guard shouldSyncWatchEntry(watchEntry) else {
                    LoggingService.shared.logCloudKit("Ignoring incoming local-folder watch entry: \(watchEntry.videoID)")
                    return .success
                }

                // Check if exists locally (same source scope only)
                if let existing = localWatchEntry(matching: record.recordID.recordName, videoID: watchEntry.videoID, in: dataManager) {
                    let localWasNewer = existing.updatedAt > watchEntry.updatedAt

                    // Conflict - resolve it
                    let localRecord = recordMapper.toCKRecord(watchEntry: existing)
                    let resolved = await conflictResolver.resolveWatchEntryConflict(local: localRecord, server: record)
                    let resolvedEntry = try recordMapper.toWatchEntry(from: resolved)
                    
                    // Update existing watch entry with resolved data
                    existing.watchedSeconds = resolvedEntry.watchedSeconds
                    existing.isFinished = resolvedEntry.isFinished
                    existing.finishedAt = resolvedEntry.finishedAt
                    existing.updatedAt = resolvedEntry.updatedAt
                    
                    // Update metadata if newer
                    existing.title = resolvedEntry.title
                    existing.authorName = resolvedEntry.authorName
                    existing.authorID = resolvedEntry.authorID
                    existing.duration = resolvedEntry.duration
                    existing.thumbnailURLString = resolvedEntry.thumbnailURLString
                    
                    dataManager.save()
                    
                    // Post notification for UI updates after conflict resolution
                    NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Merged watch entry from iCloud (conflict resolved): \(watchEntry.videoID)")

                    // Push the merge result back when local data won - the
                    // server still has the older version
                    if localWasNewer {
                        addPendingChanges([.saveRecord(record.recordID)])
                    }
                } else {
                    // New watch entry from iCloud
                    dataManager.insertWatchEntry(watchEntry)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added watch entry from iCloud: \(watchEntry.videoID)")
                }
                
            case RecordType.bookmark:
                guard canSyncBookmarks else { return .success }
                let bookmark = try recordMapper.toBookmark(from: record)
                
                // Check if exists locally (same source scope only)
                if let existing = localBookmark(matching: record.recordID.recordName, videoID: bookmark.videoID, in: dataManager) {
                    let localWasNewer = existing.createdAt > bookmark.createdAt
                        || (existing.noteModifiedAt ?? .distantPast) > (bookmark.noteModifiedAt ?? .distantPast)
                        || (existing.tagsModifiedAt ?? .distantPast) > (bookmark.tagsModifiedAt ?? .distantPast)

                    // Conflict - resolve it
                    let localRecord = recordMapper.toCKRecord(bookmark: existing)
                    let resolved = await conflictResolver.resolveBookmarkConflict(local: localRecord, server: record)
                    let resolvedBookmark = try recordMapper.toBookmark(from: resolved)
                    
                    // Update existing bookmark with resolved data
                    existing.title = resolvedBookmark.title
                    existing.authorName = resolvedBookmark.authorName
                    existing.authorID = resolvedBookmark.authorID
                    existing.duration = resolvedBookmark.duration
                    existing.thumbnailURLString = resolvedBookmark.thumbnailURLString
                    existing.isLive = resolvedBookmark.isLive
                    existing.viewCount = resolvedBookmark.viewCount
                    existing.publishedAt = resolvedBookmark.publishedAt
                    existing.publishedText = resolvedBookmark.publishedText
                    existing.note = resolvedBookmark.note
                    existing.noteModifiedAt = resolvedBookmark.noteModifiedAt
                    existing.tags = resolvedBookmark.tags
                    existing.tagsModifiedAt = resolvedBookmark.tagsModifiedAt
                    existing.sortOrder = resolvedBookmark.sortOrder
                    existing.createdAt = resolvedBookmark.createdAt
                    
                    dataManager.save()
                    
                    // Post notification for UI updates after conflict resolution
                    NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Merged bookmark from iCloud (conflict resolved): \(bookmark.videoID)")

                    // Push the merge result back when local data won - the
                    // server still has the older version
                    if localWasNewer {
                        addPendingChanges([.saveRecord(record.recordID)])
                    }
                } else {
                    // New bookmark from iCloud
                    dataManager.insertBookmark(bookmark)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added bookmark from iCloud: \(bookmark.videoID)")
                }
                
            case RecordType.localPlaylist:
                guard canSyncPlaylists else { return .success }
                let playlist = try recordMapper.toLocalPlaylist(from: record)

                // Check if exists locally
                if let existing = dataManager.playlist(forID: playlist.id) {
                    // Check if this is a placeholder being upgraded to real playlist
                    let wasPlaceholder = existing.isPlaceholder

                    if wasPlaceholder {
                        // Upgrade placeholder to real playlist - use incoming data directly
                        existing.title = playlist.title
                        existing.playlistDescription = playlist.playlistDescription
                        existing.createdAt = playlist.createdAt
                        existing.updatedAt = playlist.updatedAt
                        existing.isPlaceholder = false

                        dataManager.save()

                        // Post notification for UI updates
                        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)

                        LoggingService.shared.logCloudKit("Upgraded placeholder to real playlist: \(playlist.title)")
                    } else {
                        let localWasNewer = existing.updatedAt > playlist.updatedAt

                        // Conflict - resolve it
                        let localRecord = recordMapper.toCKRecord(playlist: existing)
                        let resolved = await conflictResolver.resolveLocalPlaylistConflict(local: localRecord, server: record)
                        let resolvedPlaylist = try recordMapper.toLocalPlaylist(from: resolved)

                        // Update existing playlist with resolved data
                        existing.title = resolvedPlaylist.title
                        existing.playlistDescription = resolvedPlaylist.playlistDescription
                        existing.updatedAt = resolvedPlaylist.updatedAt

                        dataManager.save()

                        // Post notification for UI updates
                        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)

                        LoggingService.shared.logCloudKit("Merged playlist from iCloud (conflict resolved): \(playlist.title)")

                        // Push the merge result back when local data won - the
                        // server still has the older version
                        if localWasNewer {
                            addPendingChanges([.saveRecord(record.recordID)])
                        }
                    }
                } else {
                    // New playlist from iCloud
                    dataManager.insertPlaylist(playlist)

                    // Post notification to update UI
                    NotificationCenter.default.post(name: .playlistsDidChange, object: nil)

                    LoggingService.shared.logCloudKit("Added playlist from iCloud: \(playlist.title)")
                }
                
            case RecordType.localPlaylistItem:
                guard canSyncPlaylists else { return .success }
                let (item, playlistID) = try recordMapper.toLocalPlaylistItem(from: record)
                
                // Check if exists locally
                if let existing = dataManager.playlistItem(forID: item.id) {
                    let localWasNewer = existing.addedAt > item.addedAt

                    // Conflict - resolve it
                    let localRecord = recordMapper.toCKRecord(playlistItem: existing)
                    let resolved = await conflictResolver.resolveLocalPlaylistItemConflict(local: localRecord, server: record)
                    let (resolvedItem, _) = try recordMapper.toLocalPlaylistItem(from: resolved)
                    
                    // Update existing item with resolved data
                    existing.title = resolvedItem.title
                    existing.authorName = resolvedItem.authorName
                    existing.authorID = resolvedItem.authorID
                    existing.duration = resolvedItem.duration
                    existing.thumbnailURLString = resolvedItem.thumbnailURLString
                    existing.isLive = resolvedItem.isLive
                    existing.sortOrder = resolvedItem.sortOrder
                    
                    dataManager.save()
                    
                    LoggingService.shared.logCloudKit("Merged playlist item from iCloud (conflict resolved): \(item.videoID)")

                    // Push the merge result back when local data won - the
                    // server still has the older version
                    if localWasNewer {
                        addPendingChanges([.saveRecord(record.recordID)])
                    }
                } else {
                    // New item from iCloud - need to find parent playlist
                    if let playlistID = playlistID,
                       let parentPlaylist = dataManager.playlist(forID: playlistID) {
                        item.playlist = parentPlaylist
                        dataManager.insertPlaylistItem(item)
                        
                        // Post notification to update UI
                        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
                        
                        LoggingService.shared.logCloudKit("Added playlist item from iCloud: \(item.videoID)")
                    } else if let playlistID = playlistID {
                        // Parent playlist not found yet - defer this item
                        LoggingService.shared.logCloudKit("Deferring playlist item (parent not yet available): \(item.id)")
                        return .deferred(playlistID: playlistID, itemID: item.id)
                    } else {
                        // No playlist ID - can't process this item
                        LoggingService.shared.logCloudKitError("Playlist item has no playlistID", error: NSError(domain: "CloudKitSyncEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Playlist item missing playlistID"]))
                        return .failed
                    }
                }
                
            case RecordType.searchHistory:
                guard canSyncSearchHistory else { return .success }
                let searchHistory = try recordMapper.toSearchHistory(from: record)
                
                // Check if exists locally
                if let existing = dataManager.searchHistoryEntry(forID: searchHistory.id) {
                    let localWasNewer = existing.searchedAt > searchHistory.searchedAt

                    // Conflict - resolve it
                    let localRecord = recordMapper.toCKRecord(searchHistory: existing)
                    let resolved = await conflictResolver.resolveSearchHistoryConflict(local: localRecord, server: record)
                    let resolvedHistory = try recordMapper.toSearchHistory(from: resolved)
                    
                    // Update existing search history with resolved data
                    existing.query = resolvedHistory.query
                    existing.searchedAt = resolvedHistory.searchedAt
                    
                    dataManager.save()
                    
                    // Post notification for UI updates
                    NotificationCenter.default.post(name: .searchHistoryDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Merged search history from iCloud (conflict resolved): \(searchHistory.query)")

                    // Push the merge result back when local data won - the
                    // server still has the older version
                    if localWasNewer {
                        addPendingChanges([.saveRecord(record.recordID)])
                    }
                } else {
                    // New search history from iCloud
                    dataManager.insertSearchHistory(searchHistory)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .searchHistoryDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added search history from iCloud: \(searchHistory.query)")
                }
                
            case RecordType.recentChannel:
                guard canSyncSearchHistory else { return .success }
                let recentChannel = try recordMapper.toRecentChannel(from: record)
                
                // Check if exists locally (same source scope only)
                if let existing = localRecentChannel(matching: record.recordID.recordName, channelID: recentChannel.channelID, in: dataManager) {
                    let localWasNewer = existing.visitedAt > recentChannel.visitedAt

                    // Conflict - resolve it
                    let localRecord = recordMapper.toCKRecord(recentChannel: existing)
                    let resolved = await conflictResolver.resolveRecentChannelConflict(local: localRecord, server: record)
                    let resolvedChannel = try recordMapper.toRecentChannel(from: resolved)
                    
                    // Update existing recent channel with resolved data
                    existing.name = resolvedChannel.name
                    existing.thumbnailURLString = resolvedChannel.thumbnailURLString
                    existing.sourceRawValue = resolvedChannel.sourceRawValue
                    existing.instanceURLString = resolvedChannel.instanceURLString
                    existing.subscriberCount = resolvedChannel.subscriberCount
                    existing.isVerified = resolvedChannel.isVerified
                    existing.visitedAt = resolvedChannel.visitedAt
                    
                    dataManager.save()
                    
                    // Post notification for UI updates
                    NotificationCenter.default.post(name: .recentChannelsDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Merged recent channel from iCloud (conflict resolved): \(recentChannel.channelID)")

                    // Push the merge result back when local data won - the
                    // server still has the older version
                    if localWasNewer {
                        addPendingChanges([.saveRecord(record.recordID)])
                    }
                } else {
                    // New recent channel from iCloud
                    dataManager.insertRecentChannel(recentChannel)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .recentChannelsDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added recent channel from iCloud: \(recentChannel.channelID)")
                }
                
            case RecordType.recentPlaylist:
                guard canSyncSearchHistory else { return .success }
                let recentPlaylist = try recordMapper.toRecentPlaylist(from: record)
                
                // Check if exists locally (same source scope only)
                if let existing = localRecentPlaylist(matching: record.recordID.recordName, playlistID: recentPlaylist.playlistID, in: dataManager) {
                    let localWasNewer = existing.visitedAt > recentPlaylist.visitedAt

                    // Conflict - resolve it
                    let localRecord = recordMapper.toCKRecord(recentPlaylist: existing)
                    let resolved = await conflictResolver.resolveRecentPlaylistConflict(local: localRecord, server: record)
                    let resolvedPlaylist = try recordMapper.toRecentPlaylist(from: resolved)
                    
                    // Update existing recent playlist with resolved data
                    existing.title = resolvedPlaylist.title
                    existing.authorName = resolvedPlaylist.authorName
                    existing.thumbnailURLString = resolvedPlaylist.thumbnailURLString
                    existing.videoCount = resolvedPlaylist.videoCount
                    existing.sourceRawValue = resolvedPlaylist.sourceRawValue
                    existing.instanceURLString = resolvedPlaylist.instanceURLString
                    existing.visitedAt = resolvedPlaylist.visitedAt
                    
                    dataManager.save()
                    
                    // Post notification for UI updates
                    NotificationCenter.default.post(name: .recentPlaylistsDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Merged recent playlist from iCloud (conflict resolved): \(recentPlaylist.playlistID)")

                    // Push the merge result back when local data won - the
                    // server still has the older version
                    if localWasNewer {
                        addPendingChanges([.saveRecord(record.recordID)])
                    }
                } else {
                    // New recent playlist from iCloud
                    dataManager.insertRecentPlaylist(recentPlaylist)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .recentPlaylistsDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added recent playlist from iCloud: \(recentPlaylist.playlistID)")
                }
                
            case RecordType.channelNotificationSettings:
                guard canSyncSubscriptions else { return .success }
                let settings = try recordMapper.toChannelNotificationSettings(from: record)

                // Upsert keeps whichever side has the newer updatedAt
                let existingSettings = dataManager.channelNotificationSettings(for: settings.channelID)
                let localWasNewer = existingSettings.map { $0.updatedAt > settings.updatedAt } ?? false
                dataManager.upsertChannelNotificationSettings(settings)

                // Push the local version back when it won - the server still
                // has the older version
                if localWasNewer {
                    addPendingChanges([.saveRecord(record.recordID)])
                }

                LoggingService.shared.logCloudKit("Applied channel notification settings from iCloud: \(settings.channelID)")
                
            case RecordType.controlsPreset:
                guard canSyncControlsPresets else { return .success }
                let preset = try recordMapper.toLayoutPreset(from: record)

                // Only import if device class matches current device
                guard preset.deviceClass == .current else {
                    LoggingService.shared.logCloudKit("Skipping controls preset - wrong device class: \(preset.deviceClass)")
                    return .success
                }

                // Use shared layout service if available, fallback to new instance
                let layoutService = playerControlsLayoutService ?? PlayerControlsLayoutService()

                // importPreset keeps whichever side has the newer updatedAt
                let localPresets = await layoutService.presetsForSync()
                let localPresetWasNewer = localPresets.first(where: { $0.id == preset.id }).map { $0.updatedAt > preset.updatedAt } ?? false
                try await layoutService.importPreset(preset)

                // Push the local version back when it won - the server still
                // has the older version
                if localPresetWasNewer {
                    addPendingChanges([.saveRecord(record.recordID)])
                }

                LoggingService.shared.logCloudKit("Applied controls preset from iCloud: \(preset.name)")

            default:
                LoggingService.shared.logCloudKit("Received unknown record type: \(record.recordType)")
            }
        } catch let cloudKitError as CloudKitError {
            // Track unsupported schema version for UI warning
            if case .unsupportedSchemaVersion = cloudKitError {
                hasNewerSchemaRecords = true
            }
            LoggingService.shared.logCloudKitError("Failed to parse \(record.recordType) record: \(cloudKitError.localizedDescription)", error: cloudKitError)
            return .failed
        } catch {
            LoggingService.shared.logCloudKitError("Failed to apply remote \(record.recordType) record", error: error)
            return .failed
        }
        return .success
    }
    
    /// Apply a remote deletion to local SwiftData.
    /// Entities are matched on the full scoped record name, so a deletion in
    /// one source scope cannot remove same-ID entities from other scopes, and
    /// nothing is echoed back to CloudKit.
    private func applyRemoteDeletion(_ recordID: CKRecord.ID, to dataManager: DataManager) async {
        let recordName = recordID.recordName

        if recordName.hasPrefix("sub-") {
            guard canSyncSubscriptions else { return }
            let channelID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(4)))
            if let subscription = localSubscription(matching: recordName, channelID: channelID, in: dataManager) {
                dataManager.deleteSubscription(subscription)
                dataManager.save()
                let change = SubscriptionChange(addedSubscriptions: [], removedChannelIDs: [channelID])
                NotificationCenter.default.post(
                    name: .subscriptionsDidChange,
                    object: nil,
                    userInfo: [SubscriptionChange.userInfoKey: change]
                )
                LoggingService.shared.logCloudKit("Deleted subscription from iCloud: \(channelID)")
            }
        } else if recordName.hasPrefix("watch-") {
            guard canSyncPlaybackHistory else { return }
            let videoID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(6)))
            if let entry = localWatchEntry(matching: recordName, videoID: videoID, in: dataManager) {
                dataManager.deleteWatchEntry(entry)
                NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
                LoggingService.shared.logCloudKit("Deleted watch entry from iCloud: \(videoID)")
            }
        } else if recordName.hasPrefix("bookmark-") {
            guard canSyncBookmarks else { return }
            let videoID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(9)))
            if let bookmark = localBookmark(matching: recordName, videoID: videoID, in: dataManager) {
                dataManager.deleteBookmark(bookmark)
                NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
                LoggingService.shared.logCloudKit("Deleted bookmark from iCloud: \(videoID)")
            }
        } else if recordName.hasPrefix("playlist-") {
            guard canSyncPlaylists else { return }
            let playlistIDString = String(recordName.dropFirst(9))
            if let playlistID = UUID(uuidString: playlistIDString),
               let playlist = dataManager.playlist(forID: playlistID) {
                dataManager.deletePlaylist(playlist)
                LoggingService.shared.logCloudKit("Deleted playlist from iCloud: \(playlistID)")
            }
        } else if recordName.hasPrefix("item-") {
            guard canSyncPlaylists else { return }
            let itemIDString = String(recordName.dropFirst(5))
            if let itemID = UUID(uuidString: itemIDString),
               let item = dataManager.playlistItem(forID: itemID) {
                dataManager.deletePlaylistItem(item)
                LoggingService.shared.logCloudKit("Deleted playlist item from iCloud: \(itemID)")
            }
        } else if recordName.hasPrefix("search-") {
            guard canSyncSearchHistory else { return }
            let searchIDString = String(recordName.dropFirst(7))
            if let searchID = UUID(uuidString: searchIDString),
               let searchHistory = dataManager.searchHistoryEntry(forID: searchID) {
                dataManager.deleteSearchQuery(searchHistory)
                LoggingService.shared.logCloudKit("Deleted search history from iCloud: \(searchID)")
            }
        } else if recordName.hasPrefix("recent-channel-") {
            guard canSyncSearchHistory else { return }
            let channelID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(15)))
            if let recentChannel = localRecentChannel(matching: recordName, channelID: channelID, in: dataManager) {
                dataManager.deleteRecentChannelEntry(recentChannel)
                LoggingService.shared.logCloudKit("Deleted recent channel from iCloud: \(channelID)")
            }
        } else if recordName.hasPrefix("recent-playlist-") {
            guard canSyncSearchHistory else { return }
            let playlistID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(16)))
            if let recentPlaylist = localRecentPlaylist(matching: recordName, playlistID: playlistID, in: dataManager) {
                dataManager.deleteRecentPlaylistEntry(recentPlaylist)
                LoggingService.shared.logCloudKit("Deleted recent playlist from iCloud: \(playlistID)")
            }
        } else if recordName.hasPrefix("channel-notif-") {
            guard canSyncSubscriptions else { return }
            let channelID = SyncableRecordType.extractBareID(from: String(recordName.dropFirst(14)))
            if let settings = localChannelNotificationSettings(matching: recordName, channelID: channelID, in: dataManager) {
                dataManager.deleteChannelNotificationSettings(settings)
                LoggingService.shared.logCloudKit("Deleted channel notification settings from iCloud: \(channelID)")
            }
        } else if recordName.hasPrefix("controls-") {
            guard canSyncControlsPresets else { return }
            let presetIDString = String(recordName.dropFirst(9)) // Remove "controls-" prefix
            if let presetID = UUID(uuidString: presetIDString) {
                // Use shared layout service if available, fallback to new instance
                let layoutService = playerControlsLayoutService ?? PlayerControlsLayoutService()
                try? await layoutService.removePreset(id: presetID)
                LoggingService.shared.logCloudKit("Deleted controls preset from iCloud: \(presetID)")
            }
        }
    }
}

// MARK: - Sync Status Types

/// Upload progress tracking for initial sync
struct UploadProgress: Equatable {
    var currentCategory: String
    var isComplete: Bool
    var totalOperations: Int
    
    var displayText: String {
        if isComplete {
            return "Initial sync complete"
        }
        return "Uploading \(currentCategory)..."
    }
}

/// Computed sync status for UI display
enum SyncStatus: Equatable {
    case syncing
    case upToDate
    case pending(count: Int)
    case error(Error)
    
    static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.syncing, .syncing), (.upToDate, .upToDate):
            return true
        case (.pending(let lCount), .pending(let rCount)):
            return lCount == rCount
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

// MARK: - CloudKit Errors

enum CloudKitError: Error, LocalizedError, Sendable {
    case iCloudNotAvailable(status: CKAccountStatus)
    case notAuthenticated
    case quotaExceeded
    case zoneNotFound
    case recordNotFound
    case conflictResolutionFailed

    // Schema versioning errors
    case missingRequiredField(field: String, recordType: String)
    case typeMismatch(field: String, recordType: String, expected: String)
    case unsupportedSchemaVersion(version: Int64, recordType: String)

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable(let status):
            "iCloud is not available (status: \(status))"
        case .notAuthenticated:
            "Not signed into iCloud. Sign in to Settings to enable sync."
        case .quotaExceeded:
            "iCloud storage quota exceeded. Free up space in iCloud settings."
        case .zoneNotFound:
            "Sync zone not found. Will recreate automatically."
        case .recordNotFound:
            "Record not found in CloudKit"
        case .conflictResolutionFailed:
            "Failed to resolve sync conflict"
        case .missingRequiredField(let field, let recordType):
            "Missing required field '\(field)' in \(recordType) record"
        case .typeMismatch(let field, let recordType, let expected):
            "Type mismatch for field '\(field)' in \(recordType) record (expected \(expected))"
        case .unsupportedSchemaVersion(let version, let recordType):
            "Unsupported schema version \(version) for \(recordType) record. Please update the app."
        }
    }
}
