//
//  DataManager.swift
//  Yattee
//
//  Central manager for all local data operations using SwiftData.
//

import Foundation
import SwiftData

/// Manages all local data persistence using SwiftData with CloudKit sync.
@MainActor
@Observable
final class DataManager {
    // MARK: - Properties

    /// The SwiftData container, opened on first access.
    ///
    /// The on-disk store lives in the app-group container. Opening it takes an
    /// SQLite lock (and runs WAL recovery after an unclean exit), and iOS kills
    /// an app suspended while holding such a lock with 0xdead10cc. `DataManager`
    /// is built from `YatteeApp.init()`, which also runs during prewarm launches
    /// that the system suspends before `UIApplicationMain`, so the store must not
    /// be opened there. On iOS `AppDelegate` opens it from
    /// `didFinishLaunching` inside a background-task assertion via `openStore`.
    var modelContainer: ModelContainer { openedStore().container }

    /// The main-actor context of `modelContainer`, opened on first access.
    var modelContext: ModelContext { openedStore().context }

    @ObservationIgnored private var store: (container: ModelContainer, context: ModelContext)?
    @ObservationIgnored private let isInMemory: Bool
    @ObservationIgnored private let launchedAt = Date()

    /// Set by `AppDelegate` once `didFinishLaunching` runs, so the open log can
    /// tell a deferred open from one that still happened during launch.
    static var didFinishLaunching = false

    /// Weak reference to settings manager for accessing search history limit.
    weak var settingsManager: SettingsManager?
    
    /// Weak reference to CloudKit sync engine.
    weak var cloudKitSync: CloudKitSyncEngine?

    /// Whether CloudKit sync is currently enabled for this instance.
    private(set) var isCloudKitEnabled: Bool = false

    /// Whether the on-disk store did not exist when this container was opened.
    ///
    /// On tvOS SwiftData keeps the store in Library/Caches, which the system
    /// purges under storage pressure. The CloudKit sync tokens live in
    /// UserDefaults and survive such a purge, so a fresh store must be reported
    /// to the sync engine — otherwise it only fetches changes made since the
    /// old tokens and records that did not change since (subscriptions,
    /// bookmarks) never come back.
    var storeWasCreated: Bool {
        _ = openedStore()
        return storeWasCreatedValue
    }

    @ObservationIgnored private var storeWasCreatedValue = false
    
    /// Cached set of bookmarked video IDs for fast O(1) lookup.
    /// Updated when bookmarks are added/removed locally or via CloudKit sync.
    var cachedBookmarkedVideoIDs: Set<String> = []

    /// Shared schema for all data models.
    static let schema = Schema([
        WatchEntry.self,
        Bookmark.self,
        LocalPlaylist.self,
        LocalPlaylistItem.self,
        Subscription.self,
        SearchHistory.self,
        RecentChannel.self,
        RecentPlaylist.self,
        ChannelNotificationSettings.self
    ])

    // MARK: - Initialization

    init(inMemory: Bool = false, iCloudSyncEnabled _: Bool = false) throws {
        self.isInMemory = inMemory
        self.isCloudKitEnabled = false

        // In-memory stores hold no file lock, so tests and previews open
        // immediately and keep the synchronous behavior they rely on.
        // macOS has no suspend-time lock kill and tvOS has no crash evidence,
        // so both keep opening at init until there is a reason to change them.
        #if os(iOS)
        if inMemory {
            openStore(trigger: "in-memory init")
        }
        #else
        openStore(trigger: "init")
        #endif

        // Listen for bookmark changes from CloudKit sync to refresh cache
        NotificationCenter.default.addObserver(
            forName: .bookmarksDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.refreshBookmarkCache()
            }
        }
    }

    // MARK: - Store Opening

    /// Opens the store if it is not open yet. Safe to call repeatedly.
    ///
    /// - Parameter trigger: Who asked, recorded in the open log so a store
    ///   opened before `didFinishLaunching` can be traced to its caller.
    func openStore(trigger: String) {
        guard store == nil else { return }

        #if DEBUG && os(iOS)
        // Enforces the lifecycle boundary in development, before SQLite takes
        // any lock: anything that touches the store from `YatteeApp.init()` /
        // `AppEnvironment.init` would reintroduce the pre-UIApplicationMain
        // open (0xdead10cc).
        if !isInMemory && !Self.didFinishLaunching {
            LoggingService.shared.warning(
                "SwiftData store opening before didFinishLaunching",
                category: .diagnostics,
                details: Thread.callStackSymbols.prefix(12).joined(separator: "\n")
            )
            assertionFailure("SwiftData store opening before didFinishLaunching (trigger: \(trigger))")
        }
        #endif

        let start = Date()
        let opened = Self.makeStore(inMemory: isInMemory)
        store = (opened.container, opened.container.mainContext)
        store?.context.autosaveEnabled = true
        storeWasCreatedValue = opened.created

        if !isInMemory {
            let duration = Date().timeIntervalSince(start)
            let sinceLaunch = start.timeIntervalSince(launchedAt)
            let prewarm = ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
            LoggingService.shared.info(
                "SwiftData store opened",
                category: .diagnostics,
                details: "trigger: \(trigger), duration: \(String(format: "%.3f", duration))s, "
                    + "afterInit: \(String(format: "%.3f", sinceLaunch))s, "
                    + "didFinishLaunching: \(Self.didFinishLaunching), prewarm: \(prewarm), "
                    + "existed: \(!opened.created), store: \(opened.url?.path ?? "in-memory")"
            )
        }

        refreshBookmarkCache()
    }

    private func openedStore() -> (container: ModelContainer, context: ModelContext) {
        if store == nil {
            openStore(trigger: "lazy access")
        }
        guard let store else { preconditionFailure("openStore always sets the store") }
        return store
    }

    /// Builds the container, falling back to in-memory storage if the
    /// persistent store cannot be opened.
    private static func makeStore(inMemory: Bool) -> (container: ModelContainer, created: Bool, url: URL?) {
        // IMPORTANT: We intentionally do NOT use SwiftData's built-in CloudKit sync.
        // SwiftData CloudKit sync uses internal UUIDs which causes duplicates when
        // the same data is created on multiple devices (each device generates different IDs).
        //
        // Instead, we use CKSyncEngine directly via CloudKitSyncEngine for iCloud sync.
        // This approach:
        // 1. Uses business identifiers (channelID, videoID) for deduplication
        // 2. Gives explicit control over sync timing and conflict resolution
        // 3. Avoids the duplicate data problem inherent in SwiftData CloudKit sync
        let memoryConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none  // Explicitly disable SwiftData CloudKit sync
        )
        if inMemory {
            // swiftlint:disable:next force_try
            let container = try! ModelContainer(for: schema, configurations: [memoryConfiguration])
            return (container, false, nil)
        }

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // Explicitly disable SwiftData CloudKit sync
        )
        let storeExisted = FileManager.default.fileExists(atPath: configuration.url.path)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            LoggingService.shared.logCloudKit(
                "SwiftData initialized with local storage (CloudKit sync via CKSyncEngine)",
                details: "store: \(configuration.url.path), existed: \(storeExisted)"
            )
            return (container, !storeExisted, configuration.url)
        } catch {
            LoggingService.shared.logCloudKitError(
                "Persistent store unavailable, falling back to in-memory storage",
                error: error
            )
            // swiftlint:disable:next force_try
            let container = try! ModelContainer(for: schema, configurations: [memoryConfiguration])
            return (container, false, nil)
        }
    }

    /// Refreshes the cached set of bookmarked video IDs.
    /// Called at init and when bookmarks change via CloudKit sync.
    private func refreshBookmarkCache() {
        let descriptor = FetchDescriptor<Bookmark>()
        do {
            let bookmarks = try modelContext.fetch(descriptor)
            cachedBookmarkedVideoIDs = Set(bookmarks.map { $0.videoID })
        } catch {
            cachedBookmarkedVideoIDs = []
            LoggingService.shared.logCloudKitError("Failed to refresh bookmark cache", error: error)
        }
    }

    /// Creates an in-memory DataManager for previews and testing.
    static func preview() throws -> DataManager {
        try DataManager(inMemory: true)
    }

    // MARK: - Utilities

    /// Forces a save of any pending changes.
    func save() {
        PerfCounter.count("data.save")
        do {
            try modelContext.save()
        } catch {
            LoggingService.shared.logCloudKitError("Failed to save data", error: error)
        }
    }

    // MARK: - Subscription Updates

    /// Updates subscriber count and verified status for a subscription by channel ID.
    /// Used to populate cached metadata from Yattee Server.
    func updateSubscriberCount(for channelID: String, count: Int, isVerified: Bool?) {
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.channelID == channelID }
        )

        do {
            if let subscription = try modelContext.fetch(descriptor).first {
                subscription.subscriberCount = count
                if let verified = isVerified {
                    subscription.isVerified = verified
                }
                subscription.lastUpdatedAt = Date()
                save()
            }
        } catch {
            LoggingService.shared.logCloudKitError("Failed to update subscriber count for \(channelID)", error: error)
        }
    }
}
