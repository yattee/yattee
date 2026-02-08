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
    
    /// Records pending upload to CloudKit.
    private var pendingSaves: [CKRecord] = []
    
    /// Record IDs pending deletion from CloudKit.
    private var pendingDeletes: [CKRecord.ID] = []
    
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
    
    /// Maximum delay between retries (5 minutes).
    private let maxRetryDelay: TimeInterval = 300.0

    /// Maximum number of retry attempts for conflict resolution.
    private let maxRetryAttempts = 5

    /// CloudKit batch size limit. CloudKit allows max 400 per request, use 350 for safety margin.
    private let cloudKitBatchSize = 350

    // MARK: - Account Identity Tracking
    
    /// UserDefaults key for storing the current iCloud account's record ID.
    private let accountRecordIDKey = "cloudKitAccountRecordID"
    
    /// UserDefaults key for CloudKit sync state.
    private let syncStateKey = "cloudKitSyncState"
    
    /// UserDefaults key for persisting pending save record names (crash recovery).
    private let pendingSaveRecordNamesKey = "cloudKitPendingSaveRecordNames"
    
    /// UserDefaults key for persisting pending delete record names (crash recovery).
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
        if pendingSaves.isEmpty && pendingDeletes.isEmpty {
            return .upToDate
        }
        return .pending(count: pendingSaves.count + pendingDeletes.count)
    }
    
    /// Pending changes count
    var pendingChangesCount: Int {
        pendingSaves.count + pendingDeletes.count
    }
    
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
        pendingSaves.removeAll()
        pendingDeletes.removeAll()
        retryCount.removeAll()
        deferredPlaylistItems.removeAll()
        syncEngine = nil
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
            
            // Initialize CKSyncEngine with nil state to always do a fresh fetch on launch.
            // This ensures we never miss changes due to stale tokens, at the cost of ~2s for typical record counts.
            // Sync state is still saved (see stateUpdate handler) so CKSyncEngine can use it within a session.
            LoggingService.shared.logCloudKit("Creating CKSyncEngine with fresh state (nil) for reliable sync")

            let config = CKSyncEngine.Configuration(
                database: database,
                stateSerialization: nil,
                delegate: self
            )

            self.syncEngine = CKSyncEngine(config)
            LoggingService.shared.logCloudKit("CKSyncEngine created")
            
            if accountChanged {
                LoggingService.shared.logCloudKit("CloudKit sync engine initialized with new account (fresh sync state)")
            } else {
                LoggingService.shared.logCloudKit("CloudKit sync engine initialized successfully")
                // Check for pending changes from a previous session that was terminated during debounce
                recoverPersistedPendingChanges()
            }
            
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
        pendingSaves.removeAll()
        pendingDeletes.removeAll()
        retryCount.removeAll()

        // Clear deferred playlist items (they belong to the old account context)
        clearDeferredItems()

        // Clear any existing sync engine
        syncEngine = nil

        // Reset newer schema warning
        hasNewerSchemaRecords = false

        LoggingService.shared.logCloudKit("Cleared sync state for account change")
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
            LoggingService.shared.logCloudKit("fetchChanges() completed (pending: \(pendingSaves.count) saves, \(pendingDeletes.count) deletes)")

            // Then send local changes
            if !pendingSaves.isEmpty || !pendingDeletes.isEmpty {
                LoggingService.shared.logCloudKit("Sending \(pendingSaves.count) saves, \(pendingDeletes.count) deletes...")
                try await syncEngine.sendChanges()
            }
            
            lastSyncDate = Date()
            settingsManager?.updateLastSyncTime()
            
            // Clear persisted pending changes after successful sync
            clearPersistedPendingRecordNames()
            
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
        
        isSyncing = false
    }
    
    /// Queue a subscription for sync (debounced).
    func queueSubscriptionSave(_ subscription: Subscription) {
        guard canSyncSubscriptions else { return }
        
        Task {
            let record = await recordMapper.toCKRecord(subscription: subscription)
            
            // Remove from deletes if it was queued for deletion
            pendingDeletes.removeAll { $0.recordName == record.recordID.recordName }
            
            // Add/update in saves
            pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
            pendingSaves.append(record)
            
            LoggingService.shared.logCloudKit("Queued subscription save: \(subscription.channelID)")
            
            scheduleDebounceSync()
        }
    }
    
    /// Queue a subscription deletion for sync (debounced).
    func queueSubscriptionDelete(channelID: String, scope: SourceScope) {
        guard canSyncSubscriptions else { return }

        Task {
            let zone = await zoneManager.getZone()
            let recordType = SyncableRecordType.subscription(channelID: channelID, scope: scope)
            let recordID = recordType.recordID(in: zone)
            
            // Remove from saves if it was queued
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            
            // Add to deletes
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued subscription delete: \(channelID)")
            
            scheduleDebounceSync()
        }
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
        
        // Convert all to CKRecords and add to pending queue
        for subscription in subscriptions {
            let record = await recordMapper.toCKRecord(subscription: subscription)
            
            // Check if already queued
            if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                pendingSaves.append(record)
            }
        }
        
        LoggingService.shared.logCloudKit("Queued \(subscriptions.count) existing subscriptions for initial upload")
        
        // Trigger immediate sync (no debounce for initial upload)
        await sync()
    }
    
    // MARK: - WatchEntry Sync Operations
    
    /// Queue a watch entry for sync (debounced).
    func queueWatchEntrySave(_ watchEntry: WatchEntry) {
        guard canSyncPlaybackHistory else { return }
        
        Task {
            let record = await recordMapper.toCKRecord(watchEntry: watchEntry)
            
            // Remove from deletes if it was queued for deletion
            pendingDeletes.removeAll { $0.recordName == record.recordID.recordName }
            
            // Add/update in saves
            pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
            pendingSaves.append(record)
            
            LoggingService.shared.logCloudKit("Queued watch entry save: \(watchEntry.videoID)")
            
            scheduleDebounceSync()
        }
    }
    
    /// Queue a watch entry deletion for sync (debounced).
    func queueWatchEntryDelete(videoID: String, scope: SourceScope) {
        guard canSyncPlaybackHistory else { return }

        Task {
            let zone = await zoneManager.getZone()
            let recordType = SyncableRecordType.watchEntry(videoID: videoID, scope: scope)
            let recordID = recordType.recordID(in: zone)
            
            // Remove from saves if it was queued
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            
            // Add to deletes
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued watch entry delete: \(videoID)")
            
            scheduleDebounceSync()
        }
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
        
        guard !watchHistory.isEmpty else {
            LoggingService.shared.logCloudKit("No local watch history to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += watchHistory.count
        
        // Convert all to CKRecords and add to pending queue
        for entry in watchHistory {
            let record = await recordMapper.toCKRecord(watchEntry: entry)
            
            // Check if already queued
            if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                pendingSaves.append(record)
            }
        }
        
        LoggingService.shared.logCloudKit("Queued \(watchHistory.count) existing watch entries for initial upload")
        
        // Trigger immediate sync (no debounce for initial upload)
        await sync()
    }
    
    // MARK: - Bookmark Sync Operations
    
    /// Queue a bookmark for sync (debounced).
    func queueBookmarkSave(_ bookmark: Bookmark) {
        guard canSyncBookmarks else { return }
        
        Task {
            let record = await recordMapper.toCKRecord(bookmark: bookmark)
            
            // Remove from deletes if it was queued for deletion
            pendingDeletes.removeAll { $0.recordName == record.recordID.recordName }
            
            // Add/update in saves
            pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
            pendingSaves.append(record)
            
            LoggingService.shared.logCloudKit("Queued bookmark save: \(bookmark.videoID)")
            
            scheduleDebounceSync()
        }
    }
    
    /// Queue a bookmark deletion for sync (debounced).
    func queueBookmarkDelete(videoID: String, scope: SourceScope) {
        guard canSyncBookmarks else { return }

        Task {
            let zone = await zoneManager.getZone()
            let recordType = SyncableRecordType.bookmark(videoID: videoID, scope: scope)
            let recordID = recordType.recordID(in: zone)
            
            // Remove from saves if it was queued
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            
            // Add to deletes
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued bookmark delete: \(videoID)")
            
            scheduleDebounceSync()
        }
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
        
        // Convert all to CKRecords and add to pending queue
        for bookmark in bookmarks {
            let record = await recordMapper.toCKRecord(bookmark: bookmark)
            
            // Check if already queued
            if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                pendingSaves.append(record)
            }
        }
        
        LoggingService.shared.logCloudKit("Queued \(bookmarks.count) existing bookmarks for initial upload")
        
        // Trigger immediate sync (no debounce for initial upload)
        await sync()
    }
    
    // MARK: - Playlist Sync Operations
    
    /// Queue a playlist for sync (debounced).
    func queuePlaylistSave(_ playlist: LocalPlaylist) {
        guard canSyncPlaylists else { return }
        
        Task {
            let record = await recordMapper.toCKRecord(playlist: playlist)
            pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
            pendingSaves.append(record)
            
            // Also queue all items
            for item in playlist.items ?? [] {
                let itemRecord = await recordMapper.toCKRecord(playlistItem: item)
                pendingSaves.removeAll { $0.recordID.recordName == itemRecord.recordID.recordName }
                pendingSaves.append(itemRecord)
            }
            
            LoggingService.shared.logCloudKit("Queued playlist save: \(playlist.title)")
            scheduleDebounceSync()
        }
    }
    
    /// Queue a playlist deletion for sync (debounced).
    func queuePlaylistDelete(playlistID: UUID) {
        guard canSyncPlaylists else { return }
        
        Task {
            let zone = await zoneManager.getZone()
            let recordID = SyncableRecordType.localPlaylist(id: playlistID).recordID(in: zone)
            
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued playlist delete: \(playlistID)")
            scheduleDebounceSync()
        }
    }
    
    /// Queue a playlist item deletion for sync (debounced).
    func queuePlaylistItemDelete(itemID: UUID) {
        guard canSyncPlaylists else { return }
        
        Task {
            let zone = await zoneManager.getZone()
            let recordType = SyncableRecordType.localPlaylistItem(id: itemID)
            let recordID = recordType.recordID(in: zone)
            
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued playlist item delete: \(itemID)")
            scheduleDebounceSync()
        }
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
        
        // Convert all playlists and their items to CKRecords
        for playlist in playlists {
            let record = await recordMapper.toCKRecord(playlist: playlist)
            if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                pendingSaves.append(record)
            }
            
            // Add all items
            for item in playlist.items ?? [] {
                let itemRecord = await recordMapper.toCKRecord(playlistItem: item)
                if !pendingSaves.contains(where: { $0.recordID.recordName == itemRecord.recordID.recordName }) {
                    pendingSaves.append(itemRecord)
                }
            }
        }
        
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
        
        Task {
            let record = await recordMapper.toCKRecord(searchHistory: searchHistory)
            
            pendingDeletes.removeAll { $0.recordName == record.recordID.recordName }
            pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
            pendingSaves.append(record)
            
            LoggingService.shared.logCloudKit("Queued search history save: \(searchHistory.query)")
            scheduleDebounceSync()
        }
    }
    
    /// Queue a search history entry deletion for sync (debounced).
    func queueSearchHistoryDelete(id: UUID) {
        guard canSyncSearchHistory else { return }
        
        Task {
            let zone = await zoneManager.getZone()
            let recordID = SyncableRecordType.searchHistory(id: id).recordID(in: zone)
            
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued search history delete: \(id)")
            scheduleDebounceSync()
        }
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
        
        for entry in searchHistory {
            let record = await recordMapper.toCKRecord(searchHistory: entry)
            if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                pendingSaves.append(record)
            }
        }
        
        LoggingService.shared.logCloudKit("Queued \(searchHistory.count) search history entries for initial upload")
        await sync()
    }
    
    // MARK: - RecentChannel Sync Operations
    
    /// Queue a recent channel for sync (debounced).
    func queueRecentChannelSave(_ recentChannel: RecentChannel) {
        guard canSyncSearchHistory else { return }
        
        Task {
            let record = await recordMapper.toCKRecord(recentChannel: recentChannel)
            
            pendingDeletes.removeAll { $0.recordName == record.recordID.recordName }
            pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
            pendingSaves.append(record)
            
            LoggingService.shared.logCloudKit("Queued recent channel save: \(recentChannel.channelID)")
            scheduleDebounceSync()
        }
    }
    
    /// Queue a recent channel deletion for sync (debounced).
    func queueRecentChannelDelete(channelID: String, scope: SourceScope) {
        guard canSyncSearchHistory else { return }

        Task {
            let zone = await zoneManager.getZone()
            let recordID = SyncableRecordType.recentChannel(channelID: channelID, scope: scope).recordID(in: zone)
            
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued recent channel delete: \(channelID)")
            scheduleDebounceSync()
        }
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
        
        for channel in recentChannels {
            let record = await recordMapper.toCKRecord(recentChannel: channel)
            if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                pendingSaves.append(record)
            }
        }
        
        LoggingService.shared.logCloudKit("Queued \(recentChannels.count) recent channels for initial upload")
        await sync()
    }
    
    // MARK: - RecentPlaylist Sync Operations
    
    /// Queue a recent playlist for sync (debounced).
    func queueRecentPlaylistSave(_ recentPlaylist: RecentPlaylist) {
        guard canSyncSearchHistory else { return }
        
        Task {
            let record = await recordMapper.toCKRecord(recentPlaylist: recentPlaylist)
            
            pendingDeletes.removeAll { $0.recordName == record.recordID.recordName }
            pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
            pendingSaves.append(record)
            
            LoggingService.shared.logCloudKit("Queued recent playlist save: \(recentPlaylist.playlistID)")
            scheduleDebounceSync()
        }
    }
    
    /// Queue a recent playlist deletion for sync (debounced).
    func queueRecentPlaylistDelete(playlistID: String, scope: SourceScope) {
        guard canSyncSearchHistory else { return }

        Task {
            let zone = await zoneManager.getZone()
            let recordID = SyncableRecordType.recentPlaylist(playlistID: playlistID, scope: scope).recordID(in: zone)
            
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued recent playlist delete: \(playlistID)")
            scheduleDebounceSync()
        }
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
        
        for playlist in recentPlaylists {
            let record = await recordMapper.toCKRecord(recentPlaylist: playlist)
            if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                pendingSaves.append(record)
            }
        }
        
        LoggingService.shared.logCloudKit("Queued \(recentPlaylists.count) recent playlists for initial upload")
        await sync()
    }
    
    // MARK: - ChannelNotificationSettings Sync Operations
    
    /// Queue channel notification settings for sync (debounced).
    func queueChannelNotificationSettingsSave(_ settings: ChannelNotificationSettings) {
        guard canSyncSubscriptions else { return }
        
        Task {
            let record = await recordMapper.toCKRecord(channelNotificationSettings: settings)
            
            // Remove from deletes if it was queued for deletion
            pendingDeletes.removeAll { $0.recordName == record.recordID.recordName }
            
            // Add/update in saves
            pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
            pendingSaves.append(record)
            
            LoggingService.shared.logCloudKit("Queued channel notification settings save: \(settings.channelID)")
            
            scheduleDebounceSync()
        }
    }
    
    /// Queue channel notification settings deletion for sync (debounced).
    func queueChannelNotificationSettingsDelete(channelID: String, scope: SourceScope) {
        guard canSyncSubscriptions else { return }

        Task {
            let zone = await zoneManager.getZone()
            let recordType = SyncableRecordType.channelNotificationSettings(channelID: channelID, scope: scope)
            let recordID = recordType.recordID(in: zone)
            
            // Remove from saves if it was queued
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            
            // Add to deletes
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued channel notification settings delete: \(channelID)")
            
            scheduleDebounceSync()
        }
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
        
        for settings in allSettings {
            let record = await recordMapper.toCKRecord(channelNotificationSettings: settings)
            if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                pendingSaves.append(record)
            }
        }
        
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
        
        let layoutService = PlayerControlsLayoutService()
        let presets = await layoutService.presetsForSync()
        
        guard !presets.isEmpty else {
            LoggingService.shared.logCloudKit("No controls presets to upload")
            return
        }
        
        // Track total operations
        uploadProgress?.totalOperations += presets.count
        
        for preset in presets {
            do {
                let record = try await recordMapper.toCKRecord(preset: preset)
                if !pendingSaves.contains(where: { $0.recordID.recordName == record.recordID.recordName }) {
                    pendingSaves.append(record)
                }
            } catch {
                LoggingService.shared.logCloudKitError("Failed to encode preset for upload: \(preset.name)", error: error)
            }
        }
        
        LoggingService.shared.logCloudKit("Queued \(presets.count) controls presets for upload")
        await sync()
    }
    
    /// Queue a controls preset for sync (debounced).
    func queueControlsPresetSave(_ preset: LayoutPreset) {
        guard canSyncControlsPresets else { return }
        
        // Only sync non-built-in presets for current device class
        guard !preset.isBuiltIn, preset.deviceClass == .current else { return }
        
        Task {
            do {
                let record = try await recordMapper.toCKRecord(preset: preset)
                
                pendingDeletes.removeAll { $0.recordName == record.recordID.recordName }
                pendingSaves.removeAll { $0.recordID.recordName == record.recordID.recordName }
                pendingSaves.append(record)
                
                LoggingService.shared.logCloudKit("Queued controls preset save: \(preset.name)")
                scheduleDebounceSync()
            } catch {
                LoggingService.shared.logCloudKitError("Failed to encode controls preset for sync", error: error)
            }
        }
    }
    
    /// Queue a controls preset deletion for sync (debounced).
    func queueControlsPresetDelete(id: UUID) {
        guard canSyncControlsPresets else { return }
        
        Task {
            let zone = await zoneManager.getZone()
            let recordID = SyncableRecordType.controlsPreset(id: id).recordID(in: zone)
            
            pendingSaves.removeAll { $0.recordID.recordName == recordID.recordName }
            if !pendingDeletes.contains(where: { $0.recordName == recordID.recordName }) {
                pendingDeletes.append(recordID)
            }
            
            LoggingService.shared.logCloudKit("Queued controls preset delete: \(id)")
            scheduleDebounceSync()
        }
    }
    
    /// Schedule a debounced sync after changes.
    private func scheduleDebounceSync() {
        // Persist pending record names for crash recovery
        persistPendingRecordNames()
        
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
        
        guard !pendingSaves.isEmpty || !pendingDeletes.isEmpty else { return }
        
        LoggingService.shared.logCloudKit("Flushing \(pendingSaves.count) saves, \(pendingDeletes.count) deletes before background")
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

    /// Persist pending record names to UserDefaults for crash recovery.
    /// Called after queuing changes so they survive app termination.
    private func persistPendingRecordNames() {
        let saveNames = pendingSaves.map { $0.recordID.recordName }
        let deleteNames = pendingDeletes.map { $0.recordName }
        UserDefaults.standard.set(saveNames, forKey: pendingSaveRecordNamesKey)
        UserDefaults.standard.set(deleteNames, forKey: pendingDeleteRecordNamesKey)
    }
    
    /// Clear persisted pending record names after successful sync.
    private func clearPersistedPendingRecordNames() {
        UserDefaults.standard.removeObject(forKey: pendingSaveRecordNamesKey)
        UserDefaults.standard.removeObject(forKey: pendingDeleteRecordNamesKey)
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
            let (item, _) = try await recordMapper.toLocalPlaylistItem(from: record)
            item.playlist = playlist
            dataManager.insertPlaylistItem(item)
            LoggingService.shared.logCloudKit("Attached item \(item.id) to playlist \(playlist.id)")
        } catch {
            LoggingService.shared.logCloudKitError("Failed to attach item to playlist", error: error)
        }
    }

    /// Check for persisted pending changes from a previous session and trigger sync if needed.
    /// Call this during setup to recover from app termination during debounce period.
    private func recoverPersistedPendingChanges() {
        let saveNames = UserDefaults.standard.stringArray(forKey: pendingSaveRecordNamesKey) ?? []
        let deleteNames = UserDefaults.standard.stringArray(forKey: pendingDeleteRecordNamesKey) ?? []

        // Also check for deferred playlist items
        loadDeferredItems()
        let hasDeferredItems = !deferredPlaylistItems.isEmpty

        if !saveNames.isEmpty || !deleteNames.isEmpty || hasDeferredItems {
            LoggingService.shared.logCloudKit("Recovered \(saveNames.count) pending saves, \(deleteNames.count) pending deletes, \(deferredPlaylistItems.count) deferred items from previous session")
            // Trigger immediate sync to process any recovered changes
            // The actual records will be recreated from local data during sync
            Task {
                await sync()
            }
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
        clearPersistedPendingRecordNames()

        // Tear down existing engine
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingSaves.removeAll()
        pendingDeletes.removeAll()
        retryCount.removeAll()
        syncEngine = nil

        // Reinitialize with nil state serialization (forces fresh fetch)
        await setupSyncEngine()

        LoggingService.shared.logCloudKit("Refresh sync completed")
    }

    /// Clear all sync state and reset. For testing/debugging only.
    func resetSync() async throws {
        // Delete zone (and all records)
        try await zoneManager.deleteZone()

        // Clear pending changes
        pendingSaves.removeAll()
        pendingDeletes.removeAll()

        // Clear sync state
        UserDefaults.standard.removeObject(forKey: syncStateKey)
        clearPersistedPendingRecordNames()
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
            await MainActor.run {
                LoggingService.shared.logCloudKit("Sent \(changes.savedRecords.count) saves, \(changes.deletedRecordIDs.count) deletions")
                clearSentRecords(changes)
            }
            await handlePartialFailures(changes)

        default:
            await MainActor.run {
                switch event {
                case .stateUpdate(let update):
                    let encoder = PropertyListEncoder()
                    let stateSize = (try? encoder.encode(update.stateSerialization))?.count ?? 0
                    LoggingService.shared.logCloudKit("Sync state updated and saved (\(stateSize) bytes)")
                    saveSyncState(update.stateSerialization)

                case .accountChange:
                    LoggingService.shared.logCloudKit("iCloud account change event received - reinitializing sync engine")
                    Task.detached { [weak self] in
                        await self?.setupSyncEngine()
                    }

                case .fetchedDatabaseChanges:
                    LoggingService.shared.logCloudKit("Fetched database changes")

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
        await MainActor.run {
            guard !pendingSaves.isEmpty || !pendingDeletes.isEmpty else {
                return nil
            }

            // Batch size limit - CloudKit allows max 400 per request, we use 350 for safety.
            // CKSyncEngine will call this method repeatedly until we return nil.
            let savesToSend = Array(pendingSaves.prefix(cloudKitBatchSize))
            let deletesToSend = Array(pendingDeletes.prefix(cloudKitBatchSize - savesToSend.count))

            let remainingSaves = pendingSaves.count - savesToSend.count
            let remainingDeletes = pendingDeletes.count - deletesToSend.count
            LoggingService.shared.logCloudKit("Preparing batch: \(savesToSend.count) saves, \(deletesToSend.count) deletes (remaining: \(remainingSaves) saves, \(remainingDeletes) deletes)")

            return CKSyncEngine.RecordZoneChangeBatch(
                recordsToSave: savesToSend,
                recordIDsToDelete: deletesToSend,
                atomicByZone: false
            )
        }
    }
    
    /// Clear successfully sent records from pending queues.
    private func clearSentRecords(_ changes: CKSyncEngine.Event.SentRecordZoneChanges) {
        let savedIDs = Set(changes.savedRecords.map { $0.recordID.recordName })
        let deletedIDs = Set(changes.deletedRecordIDs.map { $0.recordName })
        
        pendingSaves.removeAll { savedIDs.contains($0.recordID.recordName) }
        pendingDeletes.removeAll { deletedIDs.contains($0.recordName) }
        
        LoggingService.shared.logCloudKit("Cleared \(savedIDs.count) saves and \(deletedIDs.count) deletes from pending queue")
    }
    
    /// Handle partial failures from CloudKit sync.
    /// Applies conflict resolution and retries with exponential backoff.
    private func handlePartialFailures(_ changes: CKSyncEngine.Event.SentRecordZoneChanges) async {
        guard let dataManager else { return }
        
        // Check for failed saves
        for failedSave in changes.failedRecordSaves {
            let recordID = failedSave.record.recordID
            let recordName = recordID.recordName
            let saveError = failedSave.error as NSError
            
            LoggingService.shared.logCloudKitError("Failed to save record \(recordName)", error: saveError)
            
            // Check if this is a conflict error (serverRecordChanged = 14)
            if saveError.code == CKError.serverRecordChanged.rawValue {
                await handleConflict(recordID: recordID, error: saveError, dataManager: dataManager)
            } else if saveError.code == CKError.batchRequestFailed.rawValue {
                // Batch failed - check partial errors
                if let partialErrors = saveError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                    for (_, partialError) in partialErrors {
                        let partialCKError = partialError as NSError
                        if partialCKError.code == CKError.serverRecordChanged.rawValue {
                            await handleConflict(recordID: recordID, error: partialCKError, dataManager: dataManager)
                        } else {
                            // Other errors - remove from queue and log
                            removeFromPendingQueue(recordName: recordName)
                            LoggingService.shared.logCloudKitError("Unrecoverable error for \(recordName), removed from queue", error: partialError)
                        }
                    }
                }
            } else {
                // Other errors - remove from queue and log
                removeFromPendingQueue(recordName: recordName)
                LoggingService.shared.logCloudKitError("Unrecoverable error for \(recordName), removed from queue", error: saveError)
            }
        }
    }
    
    /// Handle a conflict error by fetching server record, resolving, and retrying.
    private func handleConflict(recordID: CKRecord.ID, error: NSError, dataManager: DataManager) async {
        let recordName = recordID.recordName
        
        // Extract server record from error
        guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
            LoggingService.shared.logCloudKitError("No server record in conflict error for \(recordName)", error: error)
            removeFromPendingQueue(recordName: recordName)
            return
        }
        
        LoggingService.shared.logCloudKit("Resolving conflict for \(recordName)")
        
        // Find our local pending record
        guard let localRecord = pendingSaves.first(where: { $0.recordID.recordName == recordName }) else {
            LoggingService.shared.logCloudKit("Local record not found in pending queue for \(recordName)")
            return
        }
        
        // Apply conflict resolution based on record type
        let resolved: CKRecord
        
        switch serverRecord.recordType {
        case RecordType.subscription:
            resolved = await conflictResolver.resolveSubscriptionConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved subscription conflict for \(recordName)")
            
        case RecordType.watchEntry:
            resolved = await conflictResolver.resolveWatchEntryConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved watch entry conflict for \(recordName)")
            
        case RecordType.bookmark:
            resolved = await conflictResolver.resolveBookmarkConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved bookmark conflict for \(recordName)")
            
        case RecordType.localPlaylist:
            resolved = await conflictResolver.resolveLocalPlaylistConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved playlist conflict for \(recordName)")
            
        case RecordType.localPlaylistItem:
            resolved = await conflictResolver.resolveLocalPlaylistItemConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved playlist item conflict for \(recordName)")
            
        case RecordType.searchHistory:
            resolved = await conflictResolver.resolveSearchHistoryConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved search history conflict for \(recordName)")
            
        case RecordType.recentChannel:
            resolved = await conflictResolver.resolveRecentChannelConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved recent channel conflict for \(recordName)")
            
        case RecordType.recentPlaylist:
            resolved = await conflictResolver.resolveRecentPlaylistConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved recent playlist conflict for \(recordName)")
            
        case RecordType.controlsPreset:
            resolved = await conflictResolver.resolveLayoutPresetConflict(local: localRecord, server: serverRecord)
            LoggingService.shared.logCloudKit("Resolved controls preset conflict for \(recordName)")
            
        default:
            // Unknown type - use server version (safe fallback)
            LoggingService.shared.logCloudKit("Unknown record type \(serverRecord.recordType), using server version")
            resolved = serverRecord
        }
        
        // Update pending queue with resolved record
        pendingSaves.removeAll { $0.recordID.recordName == recordName }
        pendingSaves.append(resolved)
        
        // Track retry and schedule with exponential backoff
        let currentRetries = retryCount[recordName] ?? 0

        // Check if we've exceeded max retries
        if currentRetries >= maxRetryAttempts {
            LoggingService.shared.logCloudKitError(
                "Record \(recordName) failed after \(maxRetryAttempts) conflict resolution attempts, giving up",
                error: error
            )
            removeFromPendingQueue(recordName: recordName)
            return
        }

        retryCount[recordName] = currentRetries + 1
        
        let delay = min(pow(2.0, Double(currentRetries)) * debounceDelay, maxRetryDelay)
        LoggingService.shared.logCloudKit("Scheduling retry for \(recordName) in \(delay)s (attempt \(currentRetries + 1))")
        
        // Use detached task to avoid calling back into CKSyncEngine from delegate
        Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.sync()
        }
    }
    
    /// Remove a record from pending queue by record name.
    private func removeFromPendingQueue(recordName: String) {
        pendingSaves.removeAll { $0.recordID.recordName == recordName }
        pendingDeletes.removeAll { $0.recordName == recordName }
        retryCount.removeValue(forKey: recordName)
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
        do {
            switch record.recordType {
            case RecordType.subscription:
                guard canSyncSubscriptions else { return .success }
                let subscription = try await recordMapper.toSubscription(from: record)
                
                // Check if exists locally
                if let existing = dataManager.subscription(for: subscription.channelID) {
                    // Conflict - resolve it
                    let localRecord = await recordMapper.toCKRecord(subscription: existing)
                    let resolved = await conflictResolver.resolveSubscriptionConflict(local: localRecord, server: record)
                    let resolvedSubscription = try await recordMapper.toSubscription(from: resolved)
                    
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
                let watchEntry = try await recordMapper.toWatchEntry(from: record)
                
                // Check if exists locally
                if let existing = dataManager.watchEntry(for: watchEntry.videoID) {
                    // Conflict - resolve it
                    let localRecord = await recordMapper.toCKRecord(watchEntry: existing)
                    let resolved = await conflictResolver.resolveWatchEntryConflict(local: localRecord, server: record)
                    let resolvedEntry = try await recordMapper.toWatchEntry(from: resolved)
                    
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
                } else {
                    // New watch entry from iCloud
                    dataManager.insertWatchEntry(watchEntry)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added watch entry from iCloud: \(watchEntry.videoID)")
                }
                
            case RecordType.bookmark:
                guard canSyncBookmarks else { return .success }
                let bookmark = try await recordMapper.toBookmark(from: record)
                
                // Check if exists locally
                if let existing = dataManager.bookmark(for: bookmark.videoID) {
                    // Conflict - resolve it
                    let localRecord = await recordMapper.toCKRecord(bookmark: existing)
                    let resolved = await conflictResolver.resolveBookmarkConflict(local: localRecord, server: record)
                    let resolvedBookmark = try await recordMapper.toBookmark(from: resolved)
                    
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
                } else {
                    // New bookmark from iCloud
                    dataManager.insertBookmark(bookmark)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added bookmark from iCloud: \(bookmark.videoID)")
                }
                
            case RecordType.localPlaylist:
                guard canSyncPlaylists else { return .success }
                let playlist = try await recordMapper.toLocalPlaylist(from: record)

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
                        // Conflict - resolve it
                        let localRecord = await recordMapper.toCKRecord(playlist: existing)
                        let resolved = await conflictResolver.resolveLocalPlaylistConflict(local: localRecord, server: record)
                        let resolvedPlaylist = try await recordMapper.toLocalPlaylist(from: resolved)

                        // Update existing playlist with resolved data
                        existing.title = resolvedPlaylist.title
                        existing.playlistDescription = resolvedPlaylist.playlistDescription
                        existing.updatedAt = resolvedPlaylist.updatedAt

                        dataManager.save()

                        // Post notification for UI updates
                        NotificationCenter.default.post(name: .playlistsDidChange, object: nil)

                        LoggingService.shared.logCloudKit("Merged playlist from iCloud (conflict resolved): \(playlist.title)")
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
                let (item, playlistID) = try await recordMapper.toLocalPlaylistItem(from: record)
                
                // Check if exists locally
                if let existing = dataManager.playlistItem(forID: item.id) {
                    // Conflict - resolve it
                    let localRecord = await recordMapper.toCKRecord(playlistItem: existing)
                    let resolved = await conflictResolver.resolveLocalPlaylistItemConflict(local: localRecord, server: record)
                    let (resolvedItem, _) = try await recordMapper.toLocalPlaylistItem(from: resolved)
                    
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
                let searchHistory = try await recordMapper.toSearchHistory(from: record)
                
                // Check if exists locally
                if let existing = dataManager.searchHistoryEntry(forID: searchHistory.id) {
                    // Conflict - resolve it
                    let localRecord = await recordMapper.toCKRecord(searchHistory: existing)
                    let resolved = await conflictResolver.resolveSearchHistoryConflict(local: localRecord, server: record)
                    let resolvedHistory = try await recordMapper.toSearchHistory(from: resolved)
                    
                    // Update existing search history with resolved data
                    existing.query = resolvedHistory.query
                    existing.searchedAt = resolvedHistory.searchedAt
                    
                    dataManager.save()
                    
                    // Post notification for UI updates
                    NotificationCenter.default.post(name: .searchHistoryDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Merged search history from iCloud (conflict resolved): \(searchHistory.query)")
                } else {
                    // New search history from iCloud
                    dataManager.insertSearchHistory(searchHistory)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .searchHistoryDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added search history from iCloud: \(searchHistory.query)")
                }
                
            case RecordType.recentChannel:
                guard canSyncSearchHistory else { return .success }
                let recentChannel = try await recordMapper.toRecentChannel(from: record)
                
                // Check if exists locally
                if let existing = dataManager.recentChannelEntry(forChannelID: recentChannel.channelID) {
                    // Conflict - resolve it
                    let localRecord = await recordMapper.toCKRecord(recentChannel: existing)
                    let resolved = await conflictResolver.resolveRecentChannelConflict(local: localRecord, server: record)
                    let resolvedChannel = try await recordMapper.toRecentChannel(from: resolved)
                    
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
                } else {
                    // New recent channel from iCloud
                    dataManager.insertRecentChannel(recentChannel)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .recentChannelsDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added recent channel from iCloud: \(recentChannel.channelID)")
                }
                
            case RecordType.recentPlaylist:
                guard canSyncSearchHistory else { return .success }
                let recentPlaylist = try await recordMapper.toRecentPlaylist(from: record)
                
                // Check if exists locally
                if let existing = dataManager.recentPlaylistEntry(forPlaylistID: recentPlaylist.playlistID) {
                    // Conflict - resolve it
                    let localRecord = await recordMapper.toCKRecord(recentPlaylist: existing)
                    let resolved = await conflictResolver.resolveRecentPlaylistConflict(local: localRecord, server: record)
                    let resolvedPlaylist = try await recordMapper.toRecentPlaylist(from: resolved)
                    
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
                } else {
                    // New recent playlist from iCloud
                    dataManager.insertRecentPlaylist(recentPlaylist)
                    
                    // Post notification to update UI
                    NotificationCenter.default.post(name: .recentPlaylistsDidChange, object: nil)
                    
                    LoggingService.shared.logCloudKit("Added recent playlist from iCloud: \(recentPlaylist.playlistID)")
                }
                
            case RecordType.channelNotificationSettings:
                guard canSyncSubscriptions else { return .success }
                let settings = try await recordMapper.toChannelNotificationSettings(from: record)
                
                // Use upsert which handles conflict resolution based on updatedAt
                dataManager.upsertChannelNotificationSettings(settings)
                
                LoggingService.shared.logCloudKit("Applied channel notification settings from iCloud: \(settings.channelID)")
                
            case RecordType.controlsPreset:
                guard canSyncControlsPresets else { return .success }
                let preset = try await recordMapper.toLayoutPreset(from: record)

                // Only import if device class matches current device
                guard preset.deviceClass == .current else {
                    LoggingService.shared.logCloudKit("Skipping controls preset - wrong device class: \(preset.deviceClass)")
                    return .success
                }

                // Use shared layout service if available, fallback to new instance
                let layoutService = playerControlsLayoutService ?? PlayerControlsLayoutService()
                try await layoutService.importPreset(preset)

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
    private func applyRemoteDeletion(_ recordID: CKRecord.ID, to dataManager: DataManager) async {
        let recordName = recordID.recordName

        // Parse record type from record name and strip scope suffix for bare ID lookup
        if recordName.hasPrefix("sub-") {
            guard canSyncSubscriptions else { return }
            let rest = String(recordName.dropFirst(4))
            let channelID = SyncableRecordType.extractBareID(from: rest)
            dataManager.unsubscribe(from: channelID)
            LoggingService.shared.logCloudKit("Deleted subscription from iCloud: \(channelID)")
        } else if recordName.hasPrefix("watch-") {
            guard canSyncPlaybackHistory else { return }
            let rest = String(recordName.dropFirst(6))
            let videoID = SyncableRecordType.extractBareID(from: rest)
            dataManager.removeFromHistory(videoID: videoID)
            LoggingService.shared.logCloudKit("Deleted watch entry from iCloud: \(videoID)")
        } else if recordName.hasPrefix("bookmark-") {
            guard canSyncBookmarks else { return }
            let rest = String(recordName.dropFirst(9))
            let videoID = SyncableRecordType.extractBareID(from: rest)
            dataManager.removeBookmark(for: videoID)
            LoggingService.shared.logCloudKit("Deleted bookmark from iCloud: \(videoID)")
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
            let rest = String(recordName.dropFirst(15))
            let channelID = SyncableRecordType.extractBareID(from: rest)
            if let recentChannel = dataManager.recentChannelEntry(forChannelID: channelID) {
                dataManager.deleteRecentChannel(recentChannel)
                LoggingService.shared.logCloudKit("Deleted recent channel from iCloud: \(channelID)")
            }
        } else if recordName.hasPrefix("recent-playlist-") {
            guard canSyncSearchHistory else { return }
            let rest = String(recordName.dropFirst(16))
            let playlistID = SyncableRecordType.extractBareID(from: rest)
            if let recentPlaylist = dataManager.recentPlaylistEntry(forPlaylistID: playlistID) {
                dataManager.deleteRecentPlaylist(recentPlaylist)
                LoggingService.shared.logCloudKit("Deleted recent playlist from iCloud: \(playlistID)")
            }
        } else if recordName.hasPrefix("channel-notif-") {
            guard canSyncSubscriptions else { return }
            let rest = String(recordName.dropFirst(14))
            let channelID = SyncableRecordType.extractBareID(from: rest)
            dataManager.deleteNotificationSettings(for: channelID)
            LoggingService.shared.logCloudKit("Deleted channel notification settings from iCloud: \(channelID)")
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
