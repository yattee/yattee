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
    /// Hands accounts added while signed out to whichever identity signs in.
    let localNamespaceImporter: LocalNamespaceImporter
    let homeInstanceCache: HomeInstanceCache
    let invidiousAPI: InvidiousAPI
    let pipedAPI: PipedAPI
    let credentialProbeService: CredentialProbeService
    let accountService: AccountService
    let remotePlaylistsCache: RemotePlaylistsCache
    let dataContextValidator: DataContextValidator
    let watchHistorySync: WatchHistorySyncService
    let playerControlsLayoutService: PlayerControlsLayoutService
    let legacyMigrationService: LegacyDataMigrationService
    let sourcesSettings: SourcesSettings

    /// Center-section settings of the active player controls preset, cached for
    /// synchronous access. Menu bar commands read seek durations from here since
    /// they cannot await the layout service actor.
    private(set) var activeControlsCenterSettings: CenterSectionSettings = .default

    @ObservationIgnored private var controlsSettingsObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var contextCacheObservers: [NSObjectProtocol] = []

    /// The context the account-scoped caches currently hold data for.
    @ObservationIgnored private var lastCachedContext: DataContext = .local

    /// The selection behind `lastCachedContext`, kept to tell a move of the
    /// selection apart from a status flap under an unchanged one.
    @ObservationIgnored private var lastSelectedContext: DataContext = .local

    /// A digest of each account's stored credential, so a replacement arriving
    /// over iCloud Keychain can be told from the same secret being re-read.
    ///
    /// Persisted, because the replacement can arrive while the app is not
    /// running: the Apple account and the context are unchanged on the next
    /// launch, so nothing else would notice that the cached feed belongs to
    /// whoever was signed in before.
    @ObservationIgnored private var credentialFingerprints: [UUID: String] = [:]

    private var credentialFingerprintsKey: String {
        "accountCredentialFingerprints.\(credentialIdentityScope.current ?? "unresolved")"
    }

    private func loadCredentialFingerprints() {
        credentialFingerprints = (UserDefaults.standard
            .dictionary(forKey: credentialFingerprintsKey) as? [String: String] ?? [:])
            .reduce(into: [:]) { result, entry in
                if let id = UUID(uuidString: entry.key) { result[id] = entry.value }
            }
    }

    /// Drops the fingerprints recorded while the identity was unresolved.
    ///
    /// Nothing legitimate is written under that key — `refreshAccountStatuses`
    /// refuses to read the Keychain until the scope resolves — so anything left
    /// there is a digest of a credential read under a scope the app could not
    /// vouch for, and comparing a real credential against it would report a
    /// replacement that never happened.
    private func purgeUnresolvedCredentialFingerprints() {
        guard credentialIdentityScope.isResolved else { return }
        UserDefaults.standard.removeObject(forKey: "accountCredentialFingerprints.unresolved")
    }

    private func saveCredentialFingerprints() {
        let stored = credentialFingerprints.reduce(into: [String: String]()) { result, entry in
            result[entry.key.uuidString] = entry.value
        }
        UserDefaults.standard.set(stored, forKey: credentialFingerprintsKey)
    }

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

        // Every per-instance client is minted by a factory rather than shared,
        // and until this is recorded those clients send no User-Agent at all —
        // which instances that whitelist the `Yattee/<version>` prefix answer
        // with a 401 the shared client never earns. Set before anything that
        // builds a factory, `ContentService` included.
        UserAgentConfiguration.shared.update(
            userAgent: settings.customUserAgent,
            randomizePerRequest: settings.randomizeUserAgentPerRequest
        )

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

        // Accounts created while signed out live in the `local` namespace, and
        // nothing reads that namespace once an identity resolves. This is what
        // moves them — records, credentials and the chosen context — into the
        // Apple account that signs in.
        self.localNamespaceImporter = LocalNamespaceImporter(
            accountsManager: accounts,
            identityScope: identityScope,
            credentialStores: { [weak accounts, weak invidiousCreds, weak pipedCreds] account in
                // Same resolution as `accountCredentialsManager(for:)`, except
                // that an instance which has not synced yet is not an answer:
                // the scoped key is the account ID either way, so both stores
                // are asked and at most one of them holds anything.
                var stores: [any AccountCredentialsManager] = []

                guard let type = accounts?.instance(for: account)?.type else {
                    if let invidiousCreds { stores.append(invidiousCreds) }
                    if let pipedCreds { stores.append(pipedCreds) }
                    return stores
                }

                switch type {
                case .invidious: if let invidiousCreds { stores.append(invidiousCreds) }
                case .piped: if let pipedCreds { stores.append(pipedCreds) }
                // The slot a future account-keyed store lands in, exactly as in
                // `accountCredentialsManager(for:)`.
                default: break
                }
                return stores
            }
        )

        // Initialize Invidious API (used by SubscriptionService and SubscriptionFeedCache)
        let invidiousAPI = InvidiousAPI(httpClient: client)
        self.invidiousAPI = invidiousAPI

        // Initialize Piped API (used by SubscriptionService and SubscriptionFeedCache)
        let pipedAPI = PipedAPI(httpClient: client)
        self.pipedAPI = pipedAPI

        // A 401 or 403 from an ordinary request is never allowed to reject a
        // login on its own — it is re-asked here against an endpoint that
        // exists to be authenticated, and only that answer marks the account.
        let probeService = CredentialProbeService(
            accountsManager: accounts,
            credentialReader: { [weak accounts, weak invidiousCreds, weak pipedCreds] account in
                guard let type = accounts?.instance(for: account)?.type else { return nil }
                switch type {
                case .invidious: return invidiousCreds?.credential(for: account)
                case .piped: return pipedCreds?.credential(for: account)
                default: return nil
                }
            },
            transport: { instance, credential in
                do {
                    switch instance.type {
                    case .invidious:
                        // GET /api/v1/auth/subscriptions — the cheapest call
                        // that does nothing except require a session.
                        _ = try await invidiousAPI.subscriptions(instance: instance, sid: credential)
                    case .piped:
                        _ = try await pipedAPI.subscriptions(instance: instance, authToken: credential)
                    default:
                        return .indeterminate
                    }
                    return .authenticated
                } catch {
                    return CredentialProbeService.classify(error)
                }
            }
        )
        self.credentialProbeService = probeService

        // Weak: the manager is owned for the life of the app and the probe
        // service holds it back, so a strong capture here would be a cycle.
        accounts.onSuspectedCredentialRejection = { [weak probeService] account in
            probeService?.probeSuspectedRejection(for: account)
        }

        // Server-side playlists, addressed by account. The same credential
        // lookup the probe service uses — one account, one secret, whichever
        // backend it belongs to — so neither can read a login the other cannot.
        let accountSvc = AccountService(
            accountsManager: accounts,
            credentialReader: { [weak accounts, weak invidiousCreds, weak pipedCreds] account in
                guard let type = accounts?.instance(for: account)?.type else { return nil }
                switch type {
                case .invidious: return invidiousCreds?.credential(for: account)
                case .piped: return pipedCreds?.credential(for: account)
                default: return nil
                }
            },
            transport: contentSvc,
            historyTransport: contentSvc
        )
        self.accountService = accountSvc
        self.remotePlaylistsCache = RemotePlaylistsCache(accountService: accountSvc)

        // Initialize SubscriptionService with all required dependencies
        self.subscriptionService = SubscriptionService(
            dataManager: dm,
            providerFactory: DefaultSubscriptionProviderFactory(
                invidiousAPI: invidiousAPI,
                pipedAPI: pipedAPI,
                invidiousCredentialsManager: invidiousCreds,
                pipedCredentialsManager: pipedCreds,
                settingsManager: settings
            )
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

        // Validates the account-based data context. Corrections are restricted
        // to deletions: a selection that merely cannot be verified yet is kept
        self.dataContextValidator = DataContextValidator(
            accountsManager: accounts,
            instancesManager: instances,
            toastManager: toast
        )

        // Mirrors what is played here into the active account's server-side
        // history. Reads the *effective* context, so it has to be built after
        // the validator that decides it.
        let watchHistory = WatchHistorySyncService(
            accountsManager: accounts,
            accountService: accountSvc,
            contextValidator: self.dataContextValidator
        )
        self.watchHistorySync = watchHistory
        player.setWatchHistorySyncService(watchHistory)

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

        // The context can now change without anyone touching this device — a
        // choice made on another one, or an account deleted there. The feed
        // cache is global rather than account-keyed, so it would otherwise keep
        // serving the previous account's videos.
        //
        // A deletion that arrives from another device takes the credential with
        // it. Only a deletion does this — an account merely missing from a
        // fetch keeps everything, because a fetch is not an enumeration.
        // A context repair reads statuses and commits — there is no second
        // chance at it once the selection no longer names the deleted account —
        // and the deletion that triggers one can arrive at any moment: a silent
        // push handled in the background, long after anything last recomputed
        // them. Foreground activation sequences the refresh ahead of the repair
        // for exactly this reason; wiring it into the repair itself closes every
        // other entry point too, instead of each fetch trigger having to
        // remember the order.
        accounts.refreshStatusesForRepair = { [weak self] in
            self?.refreshAccountStatuses()
        }

        // Every activation of an identity namespace sweeps the signed-out one.
        // A hook rather than another observer of the scope change: the sweep
        // must run after the manager has reloaded, and observer registration
        // order is not something to depend on for that. Statuses are recomputed
        // only when something moved — a credential that just arrived under this
        // identity is what decides whether its account reads as signed in.
        accounts.onNamespaceActivated = { [weak self] in
            guard let self, self.localNamespaceImporter.sweepIfNeeded() else { return }
            self.refreshAccountStatuses()
        }

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
            // account's channels can still arrive and be shown. Its playlists
            // are held the same way, and go the same way.
            self.discardAccountData(for: accountID)

            guard let account, let credentials = self.accountCredentialsManager(for: account) else {
                self.invidiousCredentialsManager.deleteCredential(forAccountID: accountID)
                self.pipedCredentialsManager.deleteCredential(forAccountID: accountID)

                // The unscoped legacy item needs the instance to be identified,
                // but not to be *checked*: the adoption marker is specific to
                // service, account, scope and the exact secret, so asking both
                // managers retires it if either owns it and does nothing
                // otherwise. Worth asking — this account was explicitly deleted,
                // and the instance may simply have gone first.
                if let account {
                    self.invidiousCredentialsManager.deleteLegacyCredentialIfOwned(for: account)
                    self.pipedCredentialsManager.deleteLegacyCredentialIfOwned(for: account)
                }
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
            object: identityScope,
            queue: .main
        ) { [weak self] _ in
            // Deferred rather than run inline: AccountsManager observes the same
            // notification to reload its namespace and clear statuses, and
            // relying on observer registration order to land after it would be
            // silently fragile.
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Fingerprints are recorded per identity, like everything else
                // keyed to one.
                self.loadCredentialFingerprints()
                self.purgeUnresolvedCredentialFingerprints()
                self.refreshAccountStatuses()

                // Compared against the recorded owner rather than cleared
                // outright: a scope that merely dropped to unresolved and came
                // back is the same Apple account, and with iCloud Drive off
                // that happens on every activation.
                self.discardCachesFromAnotherIdentityIfNeeded()
                self.refreshCachesForEffectiveContext()
            }
        }

        loadCredentialFingerprints()
        purgeUnresolvedCredentialFingerprints()
        discardCachesFromAnotherIdentityIfNeeded(atLaunch: true)

        // Turn any pre-revamp single-instance logins into accounts. Repeatable:
        // it runs again whenever instances arrive from iCloud.
        accounts.reconcileLegacyAccounts()
        accounts.migrateLegacyContextIfNeeded()

        // A launch that restores its identity scope from cache resolves inside
        // the initializer above, so no scope change will ever be announced for
        // it and `onNamespaceActivated` never fires. Invoked once here so that
        // path sweeps too; the sweep is idempotent, so an identity that does
        // arrive later simply finds nothing left.
        localNamespaceImporter.sweepIfNeeded()

        refreshAccountStatuses()

        // Seeded once the statuses it depends on are known, so launching does
        // not look like a change and throw away caches that are still right.
        lastCachedContext = dataContextValidator.effectiveContext
        lastSelectedContext = accountsManager.currentContext

        // Accounts and instances arriving are triggers too, not redundant ones:
        // a context naming an account that has not synced yet — or one whose
        // instance has not — reads as unavailable, and these arrivals are what
        // move the effective context back onto it. They are also what make a
        // synced account's credential findable, so statuses are recomputed with
        // them: an account that appears mid-session would otherwise sit at
        // "sign in required" until the app was relaunched.
        // A status change is deliberately not one of the refresh triggers: the
        // refresher reads the Keychain, which cannot know what a server said,
        // so reacting to a status by recomputing it would erase every verdict
        // the API layer records. It still re-examines the caches, because a
        // credential arriving or being rejected moves the effective context.
        for name: Notification.Name in [
            .dataContextDidChange, .accountsDidChange, .instancesDidChange,
            .accountStatusesDidChange, .connectivityDidReturn
        ] {
            contextCacheObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if name != .dataContextDidChange, name != .accountStatusesDidChange {
                            self.refreshAccountStatuses()
                        }
                        self.refreshCachesForEffectiveContext()
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
        // Clients built from here on; the ones already handed out are updated
        // through their own setters, and only the shared one is long-lived.
        UserAgentConfiguration.shared.update(userAgent: userAgent, randomizePerRequest: randomizePerRequest)
        Task {
            await httpClient.setUserAgent(userAgent)
            await httpClient.setRandomizeUserAgentPerRequest(randomizePerRequest)
        }
    }

    // MARK: - Sharing

    /// URL for sharing a video, honoring the privacy-frontend sharing setting.
    ///
    /// When enabled, YouTube videos are shared as links to the active
    /// instance's web watch page. Videos the active instance doesn't serve
    /// (PeerTube, extracted sources) and instances without a web frontend
    /// keep the video's original share URL.
    func shareURL(for video: Video) -> URL {
        guard settingsManager.privacyFrontendSharingEnabled,
              case .global(let provider) = video.id.source,
              provider == ContentSource.youtubeProvider,
              let base = instancesManager.activeInstance?.watchPageBaseURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else {
            return video.shareURL
        }
        components.path += "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: video.id.videoID)]
        return components.url ?? video.shareURL
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

    /// Switches the data context, from wherever in the app the user asked.
    ///
    /// The one entry point, so every switcher behaves identically: the cache
    /// the feed is served from is global rather than account-keyed, and a
    /// switch that skipped this would leave the previous account's videos on
    /// screen under the new account's name.
    func switchDataContext(to context: DataContext) {
        guard context != accountsManager.currentContext else { return }

        accountsManager.setContext(context)
        SubscriptionFeedCache.shared.handleAccountChange()

        LoggingService.shared.info(
            "Data context switched by the user",
            category: .general,
            details: "context=\(context)"
        )
    }

    /// Drops the account-scoped caches when the context whose data they hold
    /// has moved.
    ///
    /// Covers the moves nobody on this device made — a selection synced from
    /// another device, an account deleted there, a credential arriving or being
    /// rejected. The switcher calls `switchDataContext(to:)` instead, which
    /// clears the feed itself rather than waiting for a notification to make
    /// the round trip.
    private func refreshCachesForEffectiveContext() {
        // Cached data is invalidated on the *effective* context — the one whose
        // data is actually on screen. Not on the legacy value, because two
        // logins on the same instance collapse onto the same one; and not on
        // the stored context, because that does not move when a credential
        // arrives or disappears and the app falls back to local and back again.
        // Never while the identity is unresolved. With iCloud Drive off the
        // scope drops to unresolved on every activation and comes back
        // unchanged; the context reads as local in between, and treating that
        // as a move would throw the caches away several times a day. "Cannot
        // tell yet" is not grounds for anything destructive.
        let effective = dataContextValidator.effectiveContext
        guard credentialIdentityScope.isResolved else { return }

        let selected = accountsManager.currentContext
        if effective != lastCachedContext {
            lastCachedContext = effective
            if selected == lastSelectedContext {
                // The selection is where it was; only the *reads* moved — a
                // status flap, an unreachable fallback, a credential arriving.
                // The data on screen still belongs to the same choice of
                // account, so it is fenced rather than thrown away: an outage
                // that flips the status every minute must not leave the user
                // staring at an empty feed they had cached seconds ago.
                SubscriptionFeedCache.shared.handleEffectiveContextChange()
                HomeInstanceCache.shared.clearAllFeeds()
                remotePlaylistsCache.clearAll()
            } else {
                clearAccountScopedCaches()
            }
        }
        lastSelectedContext = selected
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
        discardAccountData(for: account.id)
        HomeInstanceCache.shared.clear(instanceID: account.instanceID, contentType: .feed)

        // Reached by both ways a credential is replaced — the user signing in
        // again here, and a replacement arriving over iCloud Keychain that the
        // fingerprint digest spots — so the probe service's per-account dedup
        // is retired here rather than at either call site. A verdict earned by
        // the old secret must never delay asking about the new one.
        credentialProbeService.credentialDidChange(for: account.id)

        if accountsManager.currentContext == .account(account.id) {
            SubscriptionFeedCache.shared.handleAccountChange()
        }

        // Views hold their own copies of this account's data, and signing in
        // again as somebody else changes neither the account ID, the context,
        // nor usually the status — so nothing they observe would move. Told
        // explicitly instead.
        NotificationCenter.default.post(name: .accountCredentialDidChange, object: nil)
    }

    /// Drops the in-memory data an account left behind, and disowns whatever is
    /// still being fetched for it.
    ///
    /// One call for every way an account stops being usable — signed out,
    /// deleted here, deleted on another device, or its instance removed — so a
    /// new place that has to be cleared is added once rather than four times.
    func discardAccountData(for accountID: UUID) {
        subscriptionService.discardProvider(for: accountID)
        remotePlaylistsCache.clear(accountID: accountID)
        watchHistorySync.cancelPending(for: accountID)
    }

    /// Drops everything cached for whichever account was being shown.
    ///
    /// Neither cache is keyed by account: the subscriptions feed is a single
    /// global list, and home feeds are keyed by instance alone. Both would
    /// otherwise keep serving one login's private videos to another.
    private func clearAccountScopedCaches() {
        SubscriptionFeedCache.shared.handleAccountChange()
        HomeInstanceCache.shared.clearAllFeeds()
        // Keyed by account, so nothing here is shared between two logins — but
        // an Apple account switch replaces the whole account list, and results
        // still in flight for the previous one have to be disowned.
        remotePlaylistsCache.clearAll()
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
        // Recorded first: the accounts on this instance may not have arrived
        // yet, and one turning up afterwards has to be deleted rather than
        // left as an orphan.
        accountsManager.recordInstanceDeletion(instance.id)

        for account in accountsManager.accounts(forInstance: instance.id) {
            // Resolved while the instance is still registered — it is removed
            // below — and the account's own deletion recorded before its secret
            // is touched, so a crash in between cannot leave a signed-out
            // account behind with no deletion owed to anybody.
            let credentials = accountCredentialsManager(for: account)
            accountsManager.removeAccount(account.id)
            credentials?.deleteCredential(for: account)
            credentials?.deleteLegacyCredentialIfOwned(for: account)
            discardAccountData(for: account.id)
        }

        instancesManager.remove(instance)
    }

    /// Signs an account out and removes it, with everything keyed to it.
    ///
    /// The one cascade behind every by-hand sign-out, so a place that has to be
    /// cleared is added here rather than in each screen that lists accounts.
    func signOutAndRemoveAccount(_ account: Account) {
        let instance = accountsManager.instance(for: account)
        // Resolved before the account is removed, though nothing about the
        // lookup needs it to still be there: the store is chosen by the
        // instance's type, and the instance is not going anywhere here.
        let credentials = accountCredentialsManager(for: account)

        // The tombstone and its outbox entry go first. A crash after the
        // credential was deleted but before the deletion was recorded would
        // otherwise leave the account standing on the next launch — signed out,
        // and with nothing owed to the devices that still have it.
        accountsManager.removeAccount(account.id)

        // Deleting the account is what authorizes removing the legacy item, and
        // only when this device adopted it and it still holds that same secret.
        credentials?.deleteCredential(for: account)
        credentials?.deleteLegacyCredentialIfOwned(for: account)
        // Drop what the account had in memory too, or its subscriptions and
        // playlists would keep answering for an account that no longer exists.
        discardAccountData(for: account.id)

        // Lowering the pre-revamp flag once nothing is left signed in on the
        // instance. Migration-only state (see `Instance.usesAccountLogin`):
        // left raised, it is what `needsCredentials(for:)` would keep reporting
        // a missing credential from.
        if let instance, accountsManager.accounts(forInstance: instance.id).isEmpty {
            instancesManager.setUsesAccountLogin(false, for: instance)
        }
    }

    /// Removes an account whose instance is gone.
    ///
    /// Separate from `signOutAndRemoveAccount(_:)` because none of the lookups
    /// that cascade depends on can resolve without an instance.
    func removeOrphanedAccount(_ accountID: UUID) {
        AccountRemoval.removeOrphan(
            accountID,
            stores: [invidiousCredentialsManager, pipedCredentialsManager],
            accountsManager: accountsManager,
            discardData: { discardAccountData(for: $0) }
        )
    }

    /// The account-keyed credentials manager for an account's instance.
    /// `nil` when the instance is unknown or its type has no account concept.
    func accountCredentialsManager(for account: Account) -> (any AccountCredentialsManager)? {
        guard let instance = accountsManager.instance(for: account) else { return nil }
        switch instance.type {
        case .invidious: return invidiousCredentialsManager
        case .piped: return pipedCredentialsManager
        // The slot a future account-keyed store lands in. What a backend's
        // accounts can do is `InstanceType.accountCapabilities`; which store
        // holds their secrets is this switch, and the two move together.
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
    /// - Parameter preservingUnreachable: leaves an account the server failed to
    ///   answer for alone. Only the credential-arrival poll passes this: it runs
    ///   every 15 seconds on behalf of a *different* account, and lifting the
    ///   outage fallback as a side effect of that would retry a down server four
    ///   times a minute instead of once, for as long as anything was waiting.
    ///   Everything else keeps the default, so a real signal — connectivity
    ///   returning, an account list changing — still lifts it at once.
    func refreshAccountStatuses(preservingUnreachable: Bool = false) {
        var didChangeFingerprints = false
        defer { if didChangeFingerprints { saveCredentialFingerprints() } }

        for account in accountsManager.accounts {
            guard let credentials = accountCredentialsManager(for: account) else { continue }

            // An unresolved identity scope means "cannot tell yet", not
            // "signed out" — leave any known status alone rather than
            // downgrading a working account to sign-in-required.
            guard credentials.isScopeResolved else { continue }

            credentials.refreshLoginStatus(for: account)

            // An account migrated from a pre-revamp login has its credential
            // under the old unscoped key. Move it across before concluding
            // anything: the upgrade is not something to ask the user about —
            // the previous release already served that item to whoever held the
            // device, and the copy made here stays on it.
            if !credentials.isLoggedIn(for: account),
               credentials.hasAdoptableLegacyCredential(for: account),
               credentials.adoptLegacyCredential(for: account) {
                credentials.refreshLoginStatus(for: account)
            }

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
            // `unreachable` is normally not preserved here. It is transient, and
            // it stops reads from reaching the server at all, so keeping it
            // would strand the account: nothing would call out to discover that
            // the server came back. The credential-arrival poll is the one
            // caller that has to leave it standing — see the parameter.
            // The secret itself is watched, not just the account: iCloud
            // Keychain can replace it under the same key when the user signs in
            // again elsewhere. The account ID, the context and the status all
            // stay put, so nothing else would notice that the data on screen
            // now belongs to a different backend user.
            let fingerprint = credentials.credential(for: account)
                .map { CloudKitIdentity.shortDigest(of: Data($0.utf8)) }
            let previousFingerprint = credentialFingerprints[account.id]
            let didReplaceCredential = previousFingerprint != nil && previousFingerprint != fingerprint

            // Written only when it actually moved: the arrival poll comes
            // through here every 15 seconds, and a secret that has not changed
            // should not cost a defaults write each time.
            if previousFingerprint != fingerprint {
                credentialFingerprints[account.id] = fingerprint
                didChangeFingerprints = true
            }

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
            let status = accountsManager.status(for: account.id)
            if Self.statusOutlivesKeychainRefresh(
                status,
                credentialWasReplaced: didReplaceCredential,
                preservingUnreachable: preservingUnreachable
            ) {
                continue
            }

            if status == .credentialRejected {
                LoggingService.shared.info(
                    "The rejected login was replaced — letting the account try again",
                    category: .keychain,
                    details: "accountID=\(account.id)"
                )
            }

            accountsManager.setStatus(.signedIn, for: account.id)
        }

        waitForArrivingCredentialsIfNeeded()
    }

    /// Whether a status the Keychain has nothing to say about should stand.
    ///
    /// Both verdicts this preserves came from the server, and neither can be
    /// re-derived from a stored secret — but a secret that was *replaced* voids
    /// both of them, because whatever the server said, it said it about the
    /// credential that is no longer there.
    static func statusOutlivesKeychainRefresh(
        _ status: AccountStatus,
        credentialWasReplaced: Bool,
        preservingUnreachable: Bool
    ) -> Bool {
        guard !credentialWasReplaced else { return false }

        switch status {
        case .credentialRejected:
            return true
        case .unreachable:
            return preservingUnreachable
        default:
            return false
        }
    }

    /// Re-reads the Keychain for a couple of minutes while any account is
    /// waiting on one.
    ///
    /// iCloud Keychain delivers on its own schedule and announces nothing when
    /// it does, so an account that syncs ahead of its credential — the ordinary
    /// case on a new device — would sit at "sign in required", with reads
    /// falling back to local, until something unrelated happened to recompute
    /// statuses.
    ///
    /// A rejected account is waiting on the very same delivery: the user fixes
    /// the login on one device, and this one goes on holding a secret the
    /// server has already refused until the replacement lands. Nobody sitting
    /// in front of that screen can hurry it along, and without this the account
    /// stays red until something unrelated recomputes — which is how a
    /// second device was measured still saying "sign in again" 41 minutes after
    /// the login had been fixed.
    ///
    /// Only the Keychain is re-read; the server is asked nothing. A secret that
    /// has not changed therefore costs one local lookup a tick and no request.
    /// Stops as soon as nothing is waiting, and gives up rather than polling
    /// forever: on tvOS, where app Keychain items never sync at all, the wait
    /// is permanent by design.
    private func waitForArrivingCredentialsIfNeeded() {
        guard isWaitingForCredential else {
            credentialArrivalTask?.cancel()
            credentialArrivalTask = nil
            return
        }

        guard credentialArrivalTask == nil else { return }

        credentialArrivalTask = Task { [weak self] in
            for _ in 0 ..< 8 {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.isWaitingForCredential else { break }

                // The whole verdict rather than a shortened version of it: a
                // rejection lifts only when the stored secret is a different
                // one, and that comparison lives in there. Another account's
                // outage fallback is left where it is: this tick is not news
                // about that server, and cutting its minute of backoff down to
                // fifteen seconds is not something waiting on a credential
                // should do.
                self.refreshAccountStatuses(preservingUnreachable: true)
            }

            // A cancelled poll has already been succeeded — clearing the
            // reference now would orphan whatever replaced it, leaving a
            // poller nothing can stop.
            guard !Task.isCancelled else { return }
            self?.credentialArrivalTask = nil
        }
    }

    /// Whether any account is holding out for a credential iCloud Keychain has
    /// yet to deliver — either none at all, or one to replace what the server
    /// refused.
    private var isWaitingForCredential: Bool {
        accountsManager.accounts.contains {
            let status = accountsManager.status(for: $0.id)
            return status == .credentialMissing || status == .credentialRejected
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
    ///
    /// The `usesAccountLogin` half is one-way migration machinery: an upgrading
    /// install whose flag was lost (it syncs through iCloud key-value storage)
    /// but whose instance-keyed credential survived would otherwise never have
    /// its legacy account synthesized by
    /// `AccountsManager.reconcileLegacyAccounts()`. Fresh sign-ins never set
    /// the flag.
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
