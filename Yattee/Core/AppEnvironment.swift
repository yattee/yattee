//
//  AppEnvironment.swift
//  Yattee
//
//  Dependency injection container for the application.
//

import Foundation
import SwiftUI
import SwiftData

/// Main dependency injection container that holds all app services.
/// Passed through the SwiftUI environment to provide dependencies to views.
@MainActor
@Observable
final class AppEnvironment {
    // MARK: - Services

    let settingsManager: SettingsManager
    let instancesManager: InstancesManager
    let contentService: ContentService
    let instanceDetector: InstanceDetector
    let dataManager: DataManager
    let subscriptionService: SubscriptionService
    let navigationCoordinator: NavigationCoordinator
    let downloadManager: DownloadManager
    let downloadSettings: DownloadSettings
    let playerService: PlayerService
    let queueManager: QueueManager
    let cloudKitSync: CloudKitSyncEngine
    let deArrowBrandingProvider: DeArrowBrandingProvider
    let notificationManager: NotificationManager
    let backgroundRefreshManager: BackgroundRefreshManager
    let mediaSourcesManager: MediaSourcesManager
    let webDAVClient: WebDAVClient
    let webDAVClientFactory: WebDAVClientFactory
    let smbClient: SMBClient
    let localFileClient: LocalFileClient
    let urlSessionFactory: URLSessionFactory
    let httpClientFactory: HTTPClientFactory
    let localNetworkService: LocalNetworkService
    let remoteControlCoordinator: RemoteControlCoordinator
    let networkShareDiscoveryService: NetworkShareDiscoveryService
    let connectivityMonitor: ConnectivityMonitor
    let httpClient: HTTPClient
    let toastManager: ToastManager
    let handoffManager: HandoffManager
    let invidiousCredentialsManager: InvidiousCredentialsManager
    let pipedCredentialsManager: PipedCredentialsManager
    let basicAuthCredentialsManager: BasicAuthCredentialsManager
    /// Shared by both account credential managers so a single CloudKit lookup
    /// resolves the scope for all of them.
    let credentialIdentityScope: CredentialIdentityScope
    let accountsManager: AccountsManager
    let accountSyncCoordinator: AccountSyncCoordinator
    let homeInstanceCache: HomeInstanceCache
    let invidiousAPI: InvidiousAPI
    let pipedAPI: PipedAPI
    let subscriptionAccountValidator: SubscriptionAccountValidator
    let dataContextValidator: DataContextValidator
    let playerControlsLayoutService: PlayerControlsLayoutService
    let legacyMigrationService: LegacyDataMigrationService
    let sourcesSettings: SourcesSettings

    /// Center-section settings of the active player controls preset, cached for
    /// synchronous access. Menu bar commands read seek durations from here since
    /// they cannot await the layout service actor.
    private(set) var activeControlsCenterSettings: CenterSectionSettings = .default

    @ObservationIgnored private var controlsSettingsObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var contextMirrorObservers: [NSObjectProtocol] = []

    /// The context the account-scoped caches currently hold data for.
    @ObservationIgnored private var lastCachedContext: DataContext = .local

    /// A digest of each account's stored credential, so a replacement arriving
    /// over iCloud Keychain can be told from the same secret being re-read.
    @ObservationIgnored private var credentialFingerprints: [UUID: String] = [:]

    /// Re-reads the Keychain for a while after an account turns up without one.
    @ObservationIgnored private var credentialArrivalTask: Task<Void, Never>?

    // MARK: - Shared Instance

    /// The single, process-wide app environment.
    ///
    /// SwiftUI may evaluate a `@State` property's default-value autoclosure more
    /// than once (it keeps only the first result but still runs the side effects
    /// of the discarded instances). Constructing `AppEnvironment` more than once
    /// would create multiple `DownloadManager`s — and therefore multiple
    /// background `URLSession`s registered under the same identifier — causing
    /// download-completion delegate callbacks to be delivered to an instance
    /// whose `activeDownloads` is empty (the finished file is then dropped).
    /// Referencing this `static let` from the App's `@State` guarantees exactly
    /// one instance for the lifetime of the process.
    static let shared = AppEnvironment()

    // MARK: - Initialization

    init(
        httpClient: HTTPClient? = nil,
        settingsManager: SettingsManager? = nil,
        instancesManager: InstancesManager? = nil,
        dataManager: DataManager? = nil,
        navigationCoordinator: NavigationCoordinator? = nil,
        downloadManager: DownloadManager? = nil
    ) {
        let client = httpClient ?? HTTPClient()
        self.httpClient = client

        let settings = settingsManager ?? SettingsManager()
        self.settingsManager = settings

        // Configure HTTP client with custom User-Agent
        Task {
            await client.setUserAgent(settings.customUserAgent)
            await client.setRandomizeUserAgentPerRequest(settings.randomizeUserAgentPerRequest)
        }

        let instances = instancesManager ?? InstancesManager(settingsManager: settings)
        instances.setSettingsManager(settings)
        self.instancesManager = instances

        // Initialize Basic Auth Credentials Manager early (needed for ContentService)
        let basicAuthCreds = BasicAuthCredentialsManager()
        basicAuthCreds.settingsManager = settings
        self.basicAuthCredentialsManager = basicAuthCreds

        let contentSvc = ContentService(httpClient: client, basicAuthCredentialsManager: basicAuthCreds)
        self.contentService = contentSvc
        self.instanceDetector = InstanceDetector(httpClient: client)
        self.navigationCoordinator = navigationCoordinator ?? NavigationCoordinator()
        self.downloadManager = downloadManager ?? DownloadManager()
        self.downloadSettings = DownloadSettings()

        // Initialize DataManager, falling back to in-memory for failures
        let dm: DataManager
        if let manager = dataManager {
            dm = manager
        } else {
            do {
                dm = try DataManager(iCloudSyncEnabled: settings.iCloudSyncEnabled)
            } catch {
                // Fall back to in-memory storage if persistent storage fails
                dm = try! DataManager(inMemory: true)
            }
        }
        self.dataManager = dm

        // Resolve which Apple account owns this device's credentials before the
        // managers that key items by it are built. Cached scopes restore
        // synchronously here; a first-ever resolution needs the network and is
        // kicked off below.
        let identityScope = CredentialIdentityScope()
        self.credentialIdentityScope = identityScope

        // Initialize Invidious Credentials Manager (needed for SubscriptionService)
        let invidiousCreds = InvidiousCredentialsManager(identityScope: identityScope)
        invidiousCreds.settingsManager = settings
        self.invidiousCredentialsManager = invidiousCreds

        // Initialize Piped Credentials Manager
        let pipedCreds = PipedCredentialsManager(identityScope: identityScope)
        pipedCreds.settingsManager = settings
        self.pipedCredentialsManager = pipedCreds

        // Accounts share the credential identity namespace: the account list and
        // the credentials it points at must always describe the same Apple account
        let accounts = AccountsManager(identityScope: identityScope, instancesManager: instances)
        self.accountsManager = accounts

        // Initialize Invidious API (used by SubscriptionService and SubscriptionFeedCache)
        let invidiousAPI = InvidiousAPI(httpClient: client)
        self.invidiousAPI = invidiousAPI

        // Initialize Piped API (used by SubscriptionService and SubscriptionFeedCache)
        let pipedAPI = PipedAPI(httpClient: client)
        self.pipedAPI = pipedAPI

        // Initialize SubscriptionService with all required dependencies
        self.subscriptionService = SubscriptionService(
            dataManager: dm,
            settingsManager: settings,
            instancesManager: instances,
            invidiousCredentialsManager: invidiousCreds,
            pipedCredentialsManager: pipedCreds,
            invidiousAPI: invidiousAPI,
            pipedAPI: pipedAPI
        )
        subscriptionService.setAccountsManager(accounts)

        // Initialize CloudKit Sync Engine
        let cloudKit = CloudKitSyncEngine(
            dataManager: dm,
            settingsManager: settings,
            instancesManager: instances
        )
        self.cloudKitSync = cloudKit
        dm.cloudKitSync = cloudKit

        // Accounts sync as CloudKit records rather than through KVS: they need
        // per-record conflict resolution and durable deletions, neither of
        // which a single overwritten key-value document can provide.
        let accountSync = AccountSyncCoordinator(
            accountsManager: accounts,
            identityScope: identityScope,
            isCategoryEnabled: { [weak cloudKit] in cloudKit?.canSyncAccounts ?? false }
        )
        self.accountSyncCoordinator = accountSync
        cloudKit.accountSync = accountSync

        // Initialize DeArrow with low-priority networking
        let lowPrioritySession = URLSessionFactory.shared.lowPrioritySession()
        let deArrowHTTPClient = HTTPClient(session: lowPrioritySession)
        let deArrowAPI = DeArrowAPI(httpClient: deArrowHTTPClient, urlSession: lowPrioritySession)
        let deArrowProvider = DeArrowBrandingProvider(api: deArrowAPI)
        deArrowProvider.setSettingsManager(settings)
        self.deArrowBrandingProvider = deArrowProvider

        // Initialize PlayerService
        let downloads = self.downloadManager
        let player = PlayerService(
            httpClient: client,
            contentService: contentSvc,
            dataManager: dm
        )
        player.setInstancesManager(instances)
        player.setSettingsManager(settings)
        player.setDownloadManager(downloads)
        player.setNavigationCoordinator(self.navigationCoordinator)
        player.setDeArrowBrandingProvider(deArrowProvider)
        self.playerService = player

        // Initialize QueueManager
        let queue = QueueManager(contentService: contentSvc)
        queue.setPlayerState(player.state)
        queue.setPlayerService(player)
        queue.setSettingsManager(settings)
        queue.setInstancesManager(instances)
        queue.setDownloadManager(downloads)
        player.setQueueManager(queue)
        self.queueManager = queue

        // Initialize Notification & Background Refresh managers
        let notifManager = NotificationManager()
        #if !os(tvOS)
        notifManager.registerNotificationCategories()
        #endif
        self.notificationManager = notifManager

        let bgRefreshManager = BackgroundRefreshManager(notificationManager: notifManager)
        self.backgroundRefreshManager = bgRefreshManager

        // Initialize URL Session and Client Factories
        let sessionFactory = URLSessionFactory.shared
        self.urlSessionFactory = sessionFactory
        self.httpClientFactory = HTTPClientFactory(sessionFactory: sessionFactory)
        self.webDAVClientFactory = WebDAVClientFactory(sessionFactory: sessionFactory)

        // Initialize Media Sources components
        let mediaSources = MediaSourcesManager(settingsManager: settings)
        self.mediaSourcesManager = mediaSources
        mediaSources.setDataManager(dm)
        
        // Initialize media clients
        self.webDAVClient = WebDAVClient()
        self.smbClient = SMBClient()
        self.localFileClient = LocalFileClient()
        
        // Wire up media services to player
        player.setMediaSourcesManager(mediaSources)
        self.navigationCoordinator.setMediaSourcesManager(mediaSources)
        player.setSMBClient(self.smbClient)
        player.setWebDAVClient(self.webDAVClient)
        player.setLocalFileClient(self.localFileClient)
        
        // Wire up SMB client to check if SMB playback is active
        // This prevents crashes from concurrent libsmbclient usage
        let smbClientRef = self.smbClient
        Task { [weak player] in
            await smbClientRef.setPlaybackActiveCallback { [weak player] in
                player?.state.isSMBPlaybackActive ?? false
            }
        }

        // Initialize Remote Control components
        let networkService = LocalNetworkService()
        self.localNetworkService = networkService
        self.networkShareDiscoveryService = NetworkShareDiscoveryService()
        let remoteControl = RemoteControlCoordinator(networkService: networkService)
        remoteControl.setPlayerService(player)
        remoteControl.setContentService(contentSvc)
        remoteControl.setInstancesManager(instances)
        remoteControl.setNavigationCoordinator(self.navigationCoordinator)
        remoteControl.setMediaSourcesManager(mediaSources)
        remoteControl.setSettingsManager(settings)
        self.remoteControlCoordinator = remoteControl

        // Restore remote control enabled state (after all services are set up)
        remoteControl.restoreEnabledState()

        // Initialize Connectivity Monitor for network-aware quality selection
        let connectivity = ConnectivityMonitor()
        self.connectivityMonitor = connectivity
        player.setConnectivityMonitor(connectivity)

        // Initialize Toast Manager
        let toast = ToastManager()
        self.toastManager = toast
        toast.setNavigationCoordinator(self.navigationCoordinator)
        remoteControl.setToastManager(toast)
        self.downloadManager.setToastManager(toast)
        self.downloadManager.setDownloadSettings(self.downloadSettings)

        // Initialize Handoff Manager
        let handoff = HandoffManager()
        handoff.setPlayerState(player.state)
        handoff.setSettingsManager(settings)
        self.handoffManager = handoff
        self.navigationCoordinator.setHandoffManager(handoff)
        player.setHandoffManager(handoff)

        // Initialize Home Instance Cache
        self.homeInstanceCache = .shared

        // Initialize Subscription Account Validator
        self.subscriptionAccountValidator = SubscriptionAccountValidator(
            settingsManager: settings,
            instancesManager: instances,
            invidiousCredentialsManager: invidiousCreds,
            pipedCredentialsManager: pipedCreds,
            toastManager: toast,
            feedCache: .shared
        )

        // Validates the account-based data context. Unlike the validator above
        // it never corrects a selection it merely cannot verify yet
        self.dataContextValidator = DataContextValidator(
            accountsManager: accounts,
            instancesManager: instances,
            toastManager: toast
        )

        // Initialize Player Controls Layout Service
        let layoutService = PlayerControlsLayoutService()
        self.playerControlsLayoutService = layoutService

        // Initialize Legacy Migration Service
        self.legacyMigrationService = LegacyDataMigrationService(
            instancesManager: instances,
            basicAuthCredentialsManager: basicAuthCreds,
            invidiousCredentialsManager: invidiousCreds,
            pipedCredentialsManager: pipedCreds,
            invidiousAPI: invidiousAPI,
            pipedAPI: pipedAPI
        )

        // Initialize Sources Settings
        self.sourcesSettings = SourcesSettings()

        // Wire up CloudKit sync to player controls layout service (bidirectional)
        cloudKit.playerControlsLayoutService = layoutService
        Task {
            await layoutService.setCloudKitSync(cloudKit)
        }

        // Wire up player controls layout service to player service (for preset-based settings)
        player.setPlayerControlsLayoutService(layoutService)

        // Cache active preset's center settings and keep them in sync
        Task { await self.refreshActiveControlsSettings() }
        for name: Notification.Name in [.playerControlsActivePresetDidChange, .playerControlsPresetsDidChange] {
            controlsSettingsObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        await self?.refreshActiveControlsSettings()
                    }
                }
            )
        }

        // Set up circular dependencies after all properties are initialized
        bgRefreshManager.setAppEnvironment(self)

        // Backfill credential flags for instances created before the flags
        // existed, so existing setups publish them to iCloud without a re-login
        backfillCredentialFlags()

        dataContextValidator.setAppEnvironment(self)
        subscriptionService.setContextValidator(dataContextValidator)
        subscriptionAccountValidator.setAccountsManager(accounts)

        // The context can now change without anyone touching this device — a
        // choice made on another one, or an account deleted there. The legacy
        // setting several views still read has to follow it, and the feed cache
        // is global rather than account-keyed, so it would otherwise keep
        // serving the previous account's videos.
        //
        // A deletion that arrives from another device takes the credential with
        // it. Only a deletion does this — an account merely missing from a
        // fetch keeps everything, because a fetch is not an enumeration.
        accountSync.onAccountDeleted = { [weak self] accountID, account in
            guard let self else { return }

            // The backend is unknown whenever the account itself never arrived
            // here, and equally when its instance is already gone — an instance
            // deletion can reach this device before the tombstone does. The
            // scoped key is the account ID either way, so both managers are
            // asked to drop it; at most one of them holds anything. The
            // unscoped legacy item is left alone in that case: deleting it
            // needs the instance, and its ownership check is bound to one.
            // The provider holds this account's subscriptions in memory and may
            // have a fetch in flight; without dropping it, the deleted
            // account's channels can still arrive and be shown.
            self.subscriptionService.discardProvider(for: accountID)

            guard let account, let credentials = self.accountCredentialsManager(for: account) else {
                self.invidiousCredentialsManager.deleteCredential(forAccountID: accountID)
                self.pipedCredentialsManager.deleteCredential(forAccountID: accountID)
                return
            }

            credentials.deleteCredential(for: account)
            credentials.deleteLegacyCredentialIfOwned(for: account)
        }

        // Statuses are cleared whenever the identity namespace reloads, so they
        // have to be recomputed once the new scope's Keychain is readable —
        // otherwise a synced account shows "sign in required" until relaunch.
        NotificationCenter.default.addObserver(
            forName: .credentialIdentityScopeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Deferred rather than run inline: AccountsManager observes the same
            // notification to reload its namespace and clear statuses, and
            // relying on observer registration order to land after it would be
            // silently fragile.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshAccountStatuses()

                // Compared against the recorded owner rather than cleared
                // outright: a scope that merely dropped to unresolved and came
                // back is the same Apple account, and with iCloud Drive off
                // that happens on every activation.
                self.discardCachesFromAnotherIdentityIfNeeded()
                self.mirrorContextToLegacySelection(resetWhenUnresolvable: true)
            }
        }

        discardCachesFromAnotherIdentityIfNeeded(atLaunch: true)

        // Turn any pre-revamp single-instance logins into accounts. Repeatable:
        // it runs again whenever instances arrive from iCloud.
        accounts.reconcileLegacyAccounts()
        accounts.migrateLegacyContextIfNeeded()
        refreshAccountStatuses()

        // Seeded once the statuses it depends on are known, so launching does
        // not look like a change and throw away caches that are still right.
        lastCachedContext = dataContextValidator.effectiveContext

        // Accounts and instances arriving are triggers too, not redundant ones:
        // a context naming an account that has not synced yet — or one whose
        // instance has not — cannot be mapped onto the legacy shape, and these
        // are what restore the mapping once it can be made rather than leaving
        // that moment permanent. The same arrivals are what make a synced
        // account's credential findable, so statuses are recomputed with them:
        // an account that appears mid-session would otherwise sit at "sign in
        // required" until the app was relaunched.
        // A status change is deliberately not one of the refresh triggers: the
        // refresher reads the Keychain, which cannot know what a server said,
        // so reacting to a status by recomputing it would erase every verdict
        // the API layer records. It still runs the mirror, because a credential
        // arriving or being rejected moves the effective context.
        for name: Notification.Name in [
            .dataContextDidChange, .accountsDidChange, .instancesDidChange,
            .accountStatusesDidChange, .connectivityDidReturn
        ] {
            contextMirrorObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if name != .dataContextDidChange, name != .accountStatusesDidChange {
                            self.refreshAccountStatuses()
                        }
                        self.mirrorContextToLegacySelection()
                    }
                }
            )
        }

        // Resolve the credential identity scope if this Apple account has never
        // been seen on this device. Until it lands, account credentials report
        // "can't tell yet" rather than "signed out".
        Task {
            let scopeBefore = identityScope.current
            await identityScope.resolve()

            // Accounts are stored per identity, so a scope that only just
            // resolved (or moved) means the in-memory list is the wrong
            // namespace's.
            if identityScope.current != scopeBefore {
                accounts.reloadForCurrentIdentity()
            }
            self.refreshAccountStatuses()
        }

        // Log device capabilities on startup for debugging
        HardwareCapabilities.shared.logCapabilities()

        // Clean up any leftover subtitle temp files from previous sessions
        cleanupAllTempSubtitles()

        // Run orphan diagnostics on startup to help debug storage issues
        #if !os(tvOS)
        Task {
            self.downloadManager.logOrphanDiagnostics()
        }
        #endif
    }
    
    /// Cleans up all temporary subtitle files from previous sessions.
    /// Call this on app launch to ensure temp directory doesn't accumulate old files.
    private func cleanupAllTempSubtitles() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yattee-subtitles", isDirectory: true)
        
        do {
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.removeItem(at: tempDir)
                LoggingService.shared.debug("Cleaned up all temp subtitle files on launch", category: .general)
            }
        } catch {
            // Log but don't fail - this is just cleanup
            LoggingService.shared.debug(
                "Failed to clean up temp subtitles on launch: \(error.localizedDescription)",
                category: .general
            )
        }
    }

    // MARK: - Configuration

    /// Refreshes the cached center-section settings from the active player controls preset.
    func refreshActiveControlsSettings() async {
        let layout = await playerControlsLayoutService.activeLayout()
        activeControlsCenterSettings = layout.centerSettings
    }

    /// Updates the HTTP client's User-Agent configuration from current settings.
    /// Call this after changing User-Agent related settings.
    func updateUserAgent() {
        let userAgent = settingsManager.customUserAgent
        let randomizePerRequest = settingsManager.randomizeUserAgentPerRequest
        Task {
            await httpClient.setUserAgent(userAgent)
            await httpClient.setRandomizeUserAgentPerRequest(randomizePerRequest)
        }
    }

    // MARK: - Notifications

    /// Ensures the notification infrastructure is enabled (system permission + master toggle + background refresh).
    /// Call this before enabling per-channel notifications.
    /// - Returns: `true` if notifications are fully enabled, `false` if the user denied permission.
    func ensureNotificationsEnabled() async -> Bool {
        if settingsManager.backgroundNotificationsEnabled {
            return true
        }

        let granted = await notificationManager.requestAuthorization()
        if granted {
            settingsManager.backgroundNotificationsEnabled = true
            backgroundRefreshManager.handleNotificationsEnabledChanged(true)
            return true
        }

        return false
    }

    // MARK: - Accounts

    /// Keeps the pre-revamp `subscriptionAccount` selection, and the feed cache
    /// keyed to it, in step with the current data context.
    ///
    /// The two stores are written together everywhere the user changes the
    /// context by hand; this covers the changes nobody on this device made — a
    /// selection synced from another device, or the selected account being
    /// deleted there. Phase 3's switcher removes the last readers of the legacy
    /// setting and this mirror with them.
    /// - Parameter resetWhenUnresolvable: whether a context that cannot be
    ///   mapped should fall back to `.local` instead of leaving the previous
    ///   value in place. True only when the Apple account changed: keeping the
    ///   previous identity's selection is worse than losing a mapping, and the
    ///   correct value returns as soon as the new namespace's accounts arrive.
    private func mirrorContextToLegacySelection(resetWhenUnresolvable: Bool = false) {
        // Cached data is invalidated on the *effective* context — the one whose
        // data is actually on screen. Not on the legacy value, because two
        // logins on the same instance collapse onto the same one; and not on
        // the stored context, because that does not move when a credential
        // arrives or disappears and the app falls back to local and back again.
        let effective = dataContextValidator.effectiveContext
        if effective != lastCachedContext {
            lastCachedContext = effective
            clearAccountScopedCaches()
        }

        let legacy: SubscriptionAccount

        switch accountsManager.currentContext {
        case .local:
            legacy = .local

        case let .account(id):
            // An account whose instance has not arrived yet cannot be mapped
            // onto the legacy shape. Leaving the old value alone is right: the
            // context is preserved, and the validator reports it unavailable
            // rather than pointing the UI at something else. A later arrival
            // runs this again and restores the mapping.
            guard let account = accountsManager.account(id: id),
                  let instance = accountsManager.instance(for: account) else {
                if resetWhenUnresolvable, settingsManager.subscriptionAccount != .local {
                    settingsManager.subscriptionAccount = .local
                }
                return
            }

            switch instance.type {
            case .invidious: legacy = .invidious(instance.id)
            case .piped: legacy = .piped(instance.id)
            default: return
            }
        }

        guard settingsManager.subscriptionAccount != legacy else { return }

        settingsManager.subscriptionAccount = legacy

        LoggingService.shared.info(
            "Data context changed — updated the legacy subscription selection",
            category: .general
        )
    }

    /// Discards everything cached under an account's previous credential.
    ///
    /// Signing in again keeps the account ID and the selected context, so
    /// nothing about the *context* changes — but the login behind it may be a
    /// different person entirely, and their subscriptions and feed would
    /// otherwise stay on screen.
    func accountCredentialDidChange(for account: Account) {
        invalidateCaches(for: account)
        refreshAccountStatuses()
    }

    /// Drops everything cached under an account's previous credential.
    private func invalidateCaches(for account: Account) {
        subscriptionService.discardProvider(for: account.id)
        HomeInstanceCache.shared.clear(instanceID: account.instanceID, contentType: .feed)

        if accountsManager.currentContext == .account(account.id) {
            SubscriptionFeedCache.shared.handleAccountChange()
        }
    }

    /// Drops everything cached for whichever account was being shown.
    ///
    /// Neither cache is keyed by account: the subscriptions feed is a single
    /// global list, and home feeds are keyed by instance alone. Both would
    /// otherwise keep serving one login's private videos to another.
    private func clearAccountScopedCaches() {
        SubscriptionFeedCache.shared.handleAccountChange()
        HomeInstanceCache.shared.clearAllFeeds()
    }

    private static let cacheOwnerKey = "accountScopedCacheOwner"

    /// Discards cached private data left behind by a different Apple account.
    ///
    /// The identity-change notification cannot cover this: a scope this device
    /// has seen before resolves synchronously while `CredentialIdentityScope` is
    /// being constructed, which is before any observer here exists. So an Apple
    /// account switched while the app was closed would otherwise reach the new
    /// user with the previous one's feeds still on disk.
    /// - Parameter atLaunch: whether this is the startup check. It decides what
    ///   an *unresolved* identity means. At launch it means the cached data's
    ///   owner cannot be confirmed at all — which is exactly the state a switch
    ///   to an unseen Apple account while offline produces — so the safe answer
    ///   is to discard. Mid-session it is a transient: with iCloud Drive off the
    ///   scope drops to unresolved and re-resolves on every activation, and
    ///   clearing on that would throw the caches away several times a day.
    private func discardCachesFromAnotherIdentityIfNeeded(atLaunch: Bool = false) {
        let defaults = UserDefaults.standard

        guard let owner = credentialIdentityScope.current else {
            // No recorded owner is not the same as "nothing to protect": the
            // first launch after upgrading finds caches written before anyone
            // recorded whose they are, which is exactly the case that must not
            // be adopted.
            guard atLaunch else { return }

            clearAccountScopedCaches()
            defaults.removeObject(forKey: Self.cacheOwnerKey)
            LoggingService.shared.info(
                "Cannot confirm who the cached account data belongs to — discarded it",
                category: .general
            )
            return
        }

        let previous = defaults.string(forKey: Self.cacheOwnerKey)
        defaults.set(owner, forKey: Self.cacheOwnerKey)

        guard previous != owner else { return }

        // A missing owner is not the same as "ours". The first launch after
        // upgrading finds caches written before anyone recorded who they belong
        // to, and the Apple account may have changed since. Adopting them would
        // be a guess with someone's private feed as the stake.
        clearAccountScopedCaches()
        LoggingService.shared.info(
            previous == nil
                ? "Cached account data predates knowing who it belongs to — discarded it"
                : "Apple account changed — discarded the previous account's cached data",
            category: .general
        )
    }

    /// Deletes an instance together with the accounts that live on it.
    ///
    /// The cascade has to happen here, while the instance is still resolvable:
    /// once it is gone, an account's credential manager cannot be determined
    /// from its type, and the credential would be stranded with no way to reach
    /// it. Only an explicit deletion cascades — an instance disappearing from
    /// iCloud leaves its accounts orphaned rather than deleted, because absence
    /// is not a deletion.
    func removeInstance(_ instance: Instance) {
        for account in accountsManager.accounts(forInstance: instance.id) {
            let credentials = accountCredentialsManager(for: account)
            credentials?.deleteCredential(for: account)
            credentials?.deleteLegacyCredentialIfOwned(for: account)
            subscriptionService.discardProvider(for: account.id)
            accountsManager.removeAccount(account.id)
        }

        instancesManager.remove(instance)
    }

    /// The account-keyed credentials manager for an account's instance.
    /// `nil` when the instance is unknown or its type has no account concept.
    func accountCredentialsManager(for account: Account) -> (any AccountCredentialsManager)? {
        guard let instance = accountsManager.instance(for: account) else { return nil }
        switch instance.type {
        case .invidious: return invidiousCredentialsManager
        case .piped: return pipedCredentialsManager
        default: return nil
        }
    }

    /// The account whose credential should be used when talking to an instance.
    ///
    /// Prefers the account the user has selected as their context; otherwise any
    /// signed-in account on that instance. Call sites that think in instances
    /// rather than accounts — imports, feed fetches, browse — go through here
    /// instead of the pre-revamp instance-keyed Keychain lookup, which a new
    /// login no longer writes.
    func account(forInstance instance: Instance) -> Account? {
        // The selected account is preferred only when it can actually answer.
        // Returning a credential-less one would report the whole instance as
        // signed out while a sibling login sits right there, usable.
        if case let .account(id) = accountsManager.currentContext,
           let account = accountsManager.account(id: id),
           account.instanceID == instance.id,
           accountCredentialsManager(for: account)?.isLoggedIn(for: account) == true {
            return account
        }

        return accountsManager.accounts(forInstance: instance.id).first {
            accountCredentialsManager(for: $0)?.isLoggedIn(for: $0) == true
        }
    }

    /// Which feed implementation a context needs.
    ///
    /// `.local` covers both the local data set and any account whose instance
    /// or type cannot supply a feed — those fall back rather than failing.
    enum FeedBackend { case local, invidious, piped }

    func feedBackend(for context: DataContext) -> FeedBackend {
        guard case let .account(id) = context,
              let account = accountsManager.account(id: id),
              let instance = accountsManager.instance(for: account)
        else { return .local }

        switch instance.type {
        case .invidious: return .invidious
        case .piped: return .piped
        default: return .local
        }
    }

    /// The selected context's account, when it lives on an instance of the
    /// given type. Used by paths that still need to know which backend they are
    /// talking to before they can build a request.
    func account(forSelectedContext type: InstanceType) -> Account? {
        guard case let .account(id) = accountsManager.currentContext,
              let account = accountsManager.account(id: id),
              accountsManager.instance(for: account)?.type == type
        else { return nil }
        return account
    }

    /// The stored credential for an instance, resolved through its accounts.
    func credential(forInstance instance: Instance) -> String? {
        guard let account = account(forInstance: instance) else { return nil }
        return accountCredentialsManager(for: account)?.credential(for: account)
    }

    /// Whether any account on this instance is signed in.
    func isSignedIn(to instance: Instance) -> Bool {
        credential(forInstance: instance) != nil
    }

    /// Recomputes each account's status from the Keychain.
    ///
    /// Only ever reports `credentialMissing` versus `signedIn` — a rejected
    /// credential is something only the server can tell us, so that state is set
    /// by the API layer when a request actually fails.
    func refreshAccountStatuses() {
        for account in accountsManager.accounts {
            guard let credentials = accountCredentialsManager(for: account) else { continue }

            // An unresolved identity scope means "cannot tell yet", not
            // "signed out" — leave any known status alone rather than
            // downgrading a working account to sign-in-required.
            guard credentials.isScopeResolved else { continue }

            credentials.refreshLoginStatus(for: account)

            guard credentials.isLoggedIn(for: account) else {
                accountsManager.setStatus(.credentialMissing, for: account.id)
                continue
            }

            // A credential the server rejected is still a credential: the
            // Keychain cannot tell that it stopped working, so this must not
            // report "signed in" over it. What it *can* tell is whether the
            // credential is still the same one — signing in again on another
            // device replaces it under the same key — and a rejection only
            // applies to the secret that earned it.
            //
            // `unreachable` is deliberately not preserved here. It is transient,
            // and it stops reads from reaching the server at all, so keeping it
            // would strand the account: nothing would call out to discover that
            // the server came back.
            // The secret itself is watched, not just the account: iCloud
            // Keychain can replace it under the same key when the user signs in
            // again elsewhere. The account ID, the context and the status all
            // stay put, so nothing else would notice that the data on screen
            // now belongs to a different backend user.
            let fingerprint = credentials.credential(for: account)
                .map { CloudKitIdentity.shortDigest(of: Data($0.utf8)) }
            let previousFingerprint = credentialFingerprints[account.id]
            let didReplaceCredential = previousFingerprint != nil && previousFingerprint != fingerprint
            credentialFingerprints[account.id] = fingerprint

            if didReplaceCredential {
                LoggingService.shared.info(
                    "The stored credential was replaced — discarding what it had cached",
                    category: .keychain,
                    details: "accountID=\(account.id)"
                )
                invalidateCaches(for: account)
            }

            // A rejection belongs to the credential that earned it. A
            // replacement has not been rejected by anyone.
            if accountsManager.status(for: account.id) == .credentialRejected, !didReplaceCredential {
                continue
            }

            accountsManager.setStatus(.signedIn, for: account.id)
        }

        waitForArrivingCredentialsIfNeeded()
    }

    /// Re-reads the Keychain for a couple of minutes while any account is
    /// missing its credential.
    ///
    /// iCloud Keychain delivers on its own schedule and announces nothing when
    /// it does, so an account that syncs ahead of its credential — the ordinary
    /// case on a new device — would sit at "sign in required", with reads
    /// falling back to local, until something unrelated happened to recompute
    /// statuses. Stops as soon as nothing is waiting, and gives up rather than
    /// polling forever: on tvOS, where app Keychain items never sync at all,
    /// the wait is permanent by design.
    private func waitForArrivingCredentialsIfNeeded() {
        let isWaiting = accountsManager.accounts.contains { accountsManager.status(for: $0.id) == .credentialMissing }

        guard isWaiting else {
            credentialArrivalTask?.cancel()
            credentialArrivalTask = nil
            return
        }

        guard credentialArrivalTask == nil else { return }

        credentialArrivalTask = Task { [weak self] in
            for _ in 0 ..< 8 {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }

                let stillWaiting = self.accountsManager.accounts.contains {
                    self.accountsManager.status(for: $0.id) == .credentialMissing
                }
                guard stillWaiting else { break }

                for account in self.accountsManager.accounts
                where self.accountsManager.status(for: account.id) == .credentialMissing {
                    guard let credentials = self.accountCredentialsManager(for: account),
                          credentials.isScopeResolved else { continue }

                    credentials.refreshLoginStatus(for: account)
                    if credentials.isLoggedIn(for: account) {
                        self.accountsManager.setStatus(.signedIn, for: account.id)
                    }
                }
            }

            self?.credentialArrivalTask = nil
        }
    }

    // MARK: - Credentials Management

    /// Returns the appropriate credentials manager for an instance type.
    /// - Parameter instance: The instance to get a credentials manager for
    /// - Returns: The credentials manager, or nil if the instance type doesn't support authentication
    func credentialsManager(for instance: Instance) -> (any InstanceCredentialsManager)? {
        switch instance.type {
        case .invidious:
            return invidiousCredentialsManager
        case .piped:
            return pipedCredentialsManager
        case .yatteeServer:
            return basicAuthCredentialsManager
        default:
            return nil
        }
    }

    /// Backfills `usesBasicAuth`/`usesAccountLogin` on instances that were created
    /// before these flags existed, based on credentials currently in the Keychain.
    /// Only ever sets the flags — a missing Keychain entry (e.g. right after a
    /// reinstall) must not clear a previously recorded flag.
    private func backfillCredentialFlags() {
        for instance in instancesManager.instances {
            if !instance.usesBasicAuth,
               instance.supportsHTTPBasicAuthProxy,
               basicAuthCredentialsManager.hasCredentials(for: instance) {
                instancesManager.setUsesBasicAuth(true, for: instance)
            }

            if !instance.usesAccountLogin,
               instance.supportsAuthentication,
               let manager = credentialsManager(for: instance),
               manager.isLoggedIn(for: instance) {
                instancesManager.setUsesAccountLogin(true, for: instance)
            }
        }
    }

    /// Whether an instance is known to require credentials that are missing from
    /// the Keychain (e.g. after reinstalling the app and importing sources from iCloud).
    /// - Yattee Server always requires basic auth; other types require it when
    ///   `usesBasicAuth` was recorded.
    /// - Invidious/Piped account logins are checked when `usesAccountLogin` was recorded.
    func needsCredentials(for instance: Instance) -> Bool {
        if instance.type == .yatteeServer || instance.usesBasicAuth,
           !basicAuthCredentialsManager.hasCredentials(for: instance) {
            return true
        }

        // Accounts describe the logins on an instance once there are any, so the
        // pre-revamp flag is consulted only for instances that have none —
        // fresh logins deliberately no longer set it.
        let accounts = accountsManager.accounts(forInstance: instance.id)
        if !accounts.isEmpty {
            // An unresolved identity scope means "cannot tell yet". Reporting a
            // missing credential on it would badge every account on every
            // launch until the scope lands.
            guard credentialIdentityScope.isResolved else { return false }

            return !accounts.contains { account in
                accountCredentialsManager(for: account)?.isLoggedIn(for: account) ?? false
            }
        }

        if instance.usesAccountLogin,
           let manager = credentialsManager(for: instance),
           !manager.isLoggedIn(for: instance) {
            return true
        }

        return false
    }

    // MARK: - Preview/Testing Support

    @MainActor
    static var preview: AppEnvironment {
        let dataManager = try? DataManager.preview()
        return AppEnvironment(dataManager: dataManager)
    }
}

// MARK: - Environment Key

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}

extension View {
    func appEnvironment(_ environment: AppEnvironment) -> some View {
        self.environment(\.appEnvironment, environment)
    }
}

// MARK: - Video Queue Context Environment

private struct VideoQueueContextKey: EnvironmentKey {
    static let defaultValue: VideoQueueContext? = nil
}

extension EnvironmentValues {
    var videoQueueContext: VideoQueueContext? {
        get { self[VideoQueueContextKey.self] }
        set { self[VideoQueueContextKey.self] = newValue }
    }
}

extension View {
    func videoQueueContext(_ context: VideoQueueContext?) -> some View {
        self.environment(\.videoQueueContext, context)
    }
}
