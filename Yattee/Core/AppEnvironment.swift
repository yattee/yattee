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
    let homeInstanceCache: HomeInstanceCache
    let invidiousAPI: InvidiousAPI
    let pipedAPI: PipedAPI
    let subscriptionAccountValidator: SubscriptionAccountValidator
    let playerControlsLayoutService: PlayerControlsLayoutService
    let legacyMigrationService: LegacyDataMigrationService
    let sourcesSettings: SourcesSettings

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

        // Initialize Invidious Credentials Manager (needed for SubscriptionService)
        let invidiousCreds = InvidiousCredentialsManager()
        invidiousCreds.settingsManager = settings
        self.invidiousCredentialsManager = invidiousCreds

        // Initialize Piped Credentials Manager
        let pipedCreds = PipedCredentialsManager()
        pipedCreds.settingsManager = settings
        self.pipedCredentialsManager = pipedCreds

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

        // Initialize CloudKit Sync Engine
        let cloudKit = CloudKitSyncEngine(
            dataManager: dm,
            settingsManager: settings,
            instancesManager: instances
        )
        self.cloudKitSync = cloudKit
        dm.cloudKitSync = cloudKit

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
        Task {
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

        // Initialize Player Controls Layout Service
        let layoutService = PlayerControlsLayoutService()
        self.playerControlsLayoutService = layoutService

        // Initialize Legacy Migration Service
        self.legacyMigrationService = LegacyDataMigrationService(
            instancesManager: instances,
            basicAuthCredentialsManager: basicAuthCreds,
            httpClient: client
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

        // Set up circular dependencies after all properties are initialized
        bgRefreshManager.setAppEnvironment(self)

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
