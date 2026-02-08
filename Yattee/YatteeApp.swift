//
//  YatteeApp.swift
//  Yattee
//
//  Main application entry point.
//

import SwiftUI
import Combine
import Nuke
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

@main
struct YatteeApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    @State private var appEnvironment = AppEnvironment()
    @State private var backgroundTasksRegistered = false
    @State private var showingClipboardAlert = false
    @State private var detectedClipboardURL: URL?
    @State private var lastCheckedClipboardURL: URL?
    @Environment(\.scenePhase) private var scenePhase

    // Deep link handling state
    @State private var prefilledLinkURL: URL?
    #if !os(tvOS)
    @State private var deepLinkVideo: Video?
    @State private var deepLinkStreams: [Stream] = []
    @State private var deepLinkCaptions: [Caption] = []
    @State private var showingDeepLinkDownloadSheet = false
    #endif

    // Onboarding state
    @State private var showingOnboarding = false
    @State private var showingSettings = false
    @State private var showingOpenLinkSheet = false

    init() {
        // Configure Nuke image loading pipeline
        ImageLoadingService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appEnvironment(appEnvironment)
                .preferredColorScheme(appEnvironment.settingsManager.theme.colorScheme)
                .tint(appEnvironment.settingsManager.accentColor.color)
                #if os(macOS)
                // Required on the view to prevent new windows on URL open
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                #endif
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onContinueUserActivity(HandoffManager.activityType) { activity in
                    handleContinuedActivity(activity)
                }
                .onAppear {
                    registerBackgroundTasksIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: .continueUserActivity)) { notification in
                    if let activity = notification.object as? NSUserActivity {
                        handleContinuedActivity(activity)
                    }
                }
                #if os(iOS) || os(macOS)
                .alert(String(localized: "alert.openVideo.title"), isPresented: $showingClipboardAlert) {
                    Button(String(localized: "common.open")) {
                        if let url = detectedClipboardURL {
                            appEnvironment.navigationCoordinator.navigate(to: .externalVideo(url))
                        }
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) {}
                } message: {
                    if let url = detectedClipboardURL {
                        Text(String(localized: "alert.openVideo.message \(url.host ?? "clipboard")"))
                    }
                }
                .sheet(item: $prefilledLinkURL) { url in
                    OpenLinkSheet(prefilledURL: url)
                        .appEnvironment(appEnvironment)
                }
                #if !os(tvOS)
                .sheet(isPresented: $showingDeepLinkDownloadSheet) {
                    if let video = deepLinkVideo {
                        DownloadQualitySheet(
                            video: video,
                            streams: deepLinkStreams,
                            captions: deepLinkCaptions
                        )
                        .appEnvironment(appEnvironment)
                    }
                }
                #endif
                #endif
                // Onboarding sheet
                #if os(tvOS)
                .fullScreenCover(isPresented: $showingOnboarding) {
                    NavigationStack {
                        OnboardingSheetView()
                            .appEnvironment(appEnvironment)
                    }
                }
                #else
                .sheet(isPresented: $showingOnboarding) {
                    NavigationStack {
                        OnboardingSheetView()
                            .appEnvironment(appEnvironment)
                    }
                    .presentationDetents([.large])
                    .interactiveDismissDisabled()
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                        .appEnvironment(appEnvironment)
                }
                .sheet(isPresented: $showingOpenLinkSheet) {
                    OpenLinkSheet()
                        .appEnvironment(appEnvironment)
                }
                #endif
                .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
                    showingOnboarding = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
                    showingSettings = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .showOpenLinkSheet)) { _ in
                    appEnvironment.navigationCoordinator.isPlayerExpanded = false
                    showingOpenLinkSheet = true
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        // Handle URLs in the existing window instead of opening a new one
        .handlesExternalEvents(matching: Set(["*"]))
        #endif
        #if os(iOS) || os(macOS)
        .commands {
            FileCommands()
            PlaybackCommands(appEnvironment: appEnvironment)
            NavigationCommands(appEnvironment: appEnvironment)
        }
        #endif
        #if os(tvOS)
        .onChange(of: scenePhase) { _, newPhase in
            LoggingService.shared.logCloudKit("[ScenePhase] Transition to: \(newPhase)")

            // Handle background playback
            appEnvironment.playerService.handleScenePhase(newPhase)

            // Refresh remote control services after returning from background
            appEnvironment.remoteControlCoordinator.handleScenePhase(newPhase)

            // Handle pending notification navigation and warm cache when becoming active
            if newPhase == .active {
                // Refresh media source password status (Keychain state can change in background)
                appEnvironment.mediaSourcesManager.refreshPasswordStoredStatus()

                // Validate subscription account (auto-correct if invalid)
                appEnvironment.subscriptionAccountValidator.validateAndCorrectIfNeeded()
                SubscriptionFeedCache.shared.warmIfNeeded(using: appEnvironment)

                // Fetch remote CloudKit changes (catches missed push notifications)
                Task {
                    await appEnvironment.cloudKitSync.fetchRemoteChanges()
                }

                // Start periodic polling as fallback for missed push notifications
                appEnvironment.cloudKitSync.startForegroundPolling()
            }

            // Flush pending CloudKit changes when entering background
            if newPhase == .background {
                appEnvironment.cloudKitSync.stopForegroundPolling()
                Task {
                    await appEnvironment.cloudKitSync.flushPendingChanges()
                }
            }
        }
        #else
        .onChange(of: scenePhase) { _, newPhase in
            LoggingService.shared.logCloudKit("[ScenePhase] Transition to: \(newPhase)")

            // Handle background playback
            appEnvironment.playerService.handleScenePhase(newPhase)

            // Refresh remote control services after returning from background
            appEnvironment.remoteControlCoordinator.handleScenePhase(newPhase)

            #if os(iOS)
            // Notify rotation manager - stops monitoring in background to prevent
            // fullscreen entry while app is not visible
            DeviceRotationManager.shared.handleScenePhase(newPhase)
            #endif

            // Handle pending notification navigation and warm cache when becoming active
            if newPhase == .active {
                appEnvironment.notificationManager.handlePendingNavigation(
                    using: appEnvironment.navigationCoordinator
                )
                // Refresh media source password status (Keychain state can change in background)
                appEnvironment.mediaSourcesManager.refreshPasswordStoredStatus()

                // Validate subscription account (auto-correct if invalid)
                appEnvironment.subscriptionAccountValidator.validateAndCorrectIfNeeded()
                SubscriptionFeedCache.shared.warmIfNeeded(using: appEnvironment)

                // Check clipboard for external video URLs
                checkClipboardForExternalURL()

                // Fetch remote CloudKit changes (catches missed push notifications)
                Task {
                    await appEnvironment.cloudKitSync.fetchRemoteChanges()
                }

                // Start periodic polling as fallback for missed push notifications
                appEnvironment.cloudKitSync.startForegroundPolling()
            }

            // Flush pending CloudKit changes when entering background
            if newPhase == .background {
                appEnvironment.cloudKitSync.stopForegroundPolling()
                Task {
                    await appEnvironment.cloudKitSync.flushPendingChanges()
                }

                #if os(iOS)
                if appEnvironment.settingsManager.backgroundNotificationsEnabled {
                    appEnvironment.backgroundRefreshManager.scheduleIOSBackgroundRefresh()
                }
                #endif
            }
        }
        #endif
    }

    private func registerBackgroundTasksIfNeeded() {
        guard !backgroundTasksRegistered else { return }
        backgroundTasksRegistered = true

        // Register background tasks
        appEnvironment.backgroundRefreshManager.registerBackgroundTasks()

        // If notifications are enabled, schedule the first refresh
        #if os(iOS)
        if appEnvironment.settingsManager.backgroundNotificationsEnabled {
            appEnvironment.backgroundRefreshManager.scheduleIOSBackgroundRefresh()
        }
        #endif

        // Auto-delete old history entries based on retention setting
        performHistoryCleanup()

        // Show onboarding on first launch
        if !appEnvironment.settingsManager.onboardingCompleted {
            // Small delay to let the main UI settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingOnboarding = true
            }
        }
    }

    /// Delete old watch history entries based on the retention setting.
    private func performHistoryCleanup() {
        let retentionDays = appEnvironment.settingsManager.historyRetentionDays
        guard retentionDays > 0 else { return }

        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else {
            return
        }

        appEnvironment.dataManager.clearWatchHistory(olderThan: cutoffDate)
    }

    /// Handle incoming deep link URLs.
    private func handleDeepLink(_ url: URL) {
        let router = URLRouter()
        guard let destination = router.route(url) else { return }

        let action = appEnvironment.settingsManager.defaultLinkAction

        // Videos get special handling based on link action setting
        if case .video(let source, _) = destination, case .id(let videoID) = source {
            handleVideoDeepLink(videoID: videoID, originalURL: url, action: action)
            return
        }

        // External videos also check setting
        if case .externalVideo(let externalURL) = destination {
            handleExternalVideoDeepLink(externalURL: externalURL, action: action)
            return
        }

        // All other destinations use standard navigation
        appEnvironment.navigationCoordinator.navigate(to: destination)
    }

    /// Handle video deep link based on default link action setting.
    private func handleVideoDeepLink(videoID: VideoID, originalURL: URL, action: DefaultLinkAction) {
        switch action {
        case .open:
            // Play directly (existing behavior)
            Task {
                await playVideoFromDeepLink(videoID: videoID)
            }

        case .download:
            #if !os(tvOS)
            // Fetch video and show download sheet
            Task {
                await downloadVideoFromDeepLink(videoID: videoID)
            }
            #else
            // tvOS doesn't support downloads, fall back to open
            Task {
                await playVideoFromDeepLink(videoID: videoID)
            }
            #endif

        case .ask:
            // Show OpenLinkSheet with URL pre-filled
            showOpenLinkSheetWithURL(originalURL)
        }
    }

    /// Handle external video deep link based on default link action setting.
    private func handleExternalVideoDeepLink(externalURL: URL, action: DefaultLinkAction) {
        switch action {
        case .open:
            // Navigate to ExternalVideoView (existing behavior)
            appEnvironment.navigationCoordinator.navigate(to: .externalVideo(externalURL))

        case .download:
            #if !os(tvOS)
            // Extract and show download sheet
            Task {
                await downloadExternalVideoFromDeepLink(url: externalURL)
            }
            #else
            // tvOS doesn't support downloads, fall back to open
            appEnvironment.navigationCoordinator.navigate(to: .externalVideo(externalURL))
            #endif

        case .ask:
            // Show OpenLinkSheet with URL pre-filled
            showOpenLinkSheetWithURL(externalURL)
        }
    }

    /// Show OpenLinkSheet with a pre-filled URL.
    private func showOpenLinkSheetWithURL(_ url: URL) {
        prefilledLinkURL = url
    }

    /// Play a video from a deep link.
    private func playVideoFromDeepLink(videoID: VideoID) async {
        guard let instance = appEnvironment.instancesManager.instance(for: videoID.source) else { return }

        do {
            let video = try await appEnvironment.contentService.video(
                id: videoID.videoID,
                instance: instance
            )
            appEnvironment.playerService.openVideo(video)
        } catch {
            // If video fetch fails, fall back to navigating to the video info view
            appEnvironment.navigationCoordinator.navigate(to: .video(.id(videoID)))
        }
    }

    #if !os(tvOS)
    /// Download a video from a deep link.
    private func downloadVideoFromDeepLink(videoID: VideoID) async {
        guard let instance = appEnvironment.instancesManager.instance(for: videoID.source) else { return }

        do {
            let (video, streams, captions, _) = try await appEnvironment.contentService
                .videoWithProxyStreamsAndCaptionsAndStoryboards(
                    id: videoID.videoID,
                    instance: instance
                )

            await MainActor.run {
                deepLinkVideo = video
                deepLinkStreams = streams
                deepLinkCaptions = captions
                showingDeepLinkDownloadSheet = true
            }
        } catch {
            // Fall back to open on error
            await playVideoFromDeepLink(videoID: videoID)
        }
    }

    /// Download an external video from a deep link.
    private func downloadExternalVideoFromDeepLink(url: URL) async {
        guard let instance = appEnvironment.instancesManager.yatteeServerInstance else {
            // No Yattee Server - fall back to open
            appEnvironment.navigationCoordinator.navigate(to: .externalVideo(url))
            return
        }

        do {
            let (video, streams, captions) = try await appEnvironment.contentService
                .extractURL(url, instance: instance)

            await MainActor.run {
                deepLinkVideo = video
                deepLinkStreams = streams
                deepLinkCaptions = captions
                showingDeepLinkDownloadSheet = true
            }
        } catch {
            // Fall back to open on error
            appEnvironment.navigationCoordinator.navigate(to: .externalVideo(url))
        }
    }
    #endif

    // MARK: - Handoff

    /// Handle continued activity from Handoff.
    private func handleContinuedActivity(_ activity: NSUserActivity) {
        LoggingService.shared.debug("[Handoff] Received activity: \(activity.activityType) - title: \(activity.title ?? "none")", category: .general)
        LoggingService.shared.debug("[Handoff] UserInfo: \(activity.userInfo ?? [:])", category: .general)

        guard let (destination, playbackTime) = appEnvironment.handoffManager
            .restoreDestination(from: activity) else {
            LoggingService.shared.debug("[Handoff] Failed to restore destination from activity", category: .general)
            return
        }

        LoggingService.shared.debug("[Handoff] Restored destination: \(destination), playbackTime: \(playbackTime ?? -1)", category: .general)

        // For video destinations with playback time, play with resume
        if case .video(let source, _) = destination, case .id(let videoID) = source {
            Task {
                await playVideoFromHandoff(videoID: videoID, startTime: playbackTime)
            }
            return
        }

        // For external video with playback time
        if case .externalVideo = destination, playbackTime != nil {
            // External videos don't support resume time in the same way
            // Just navigate to the destination
            appEnvironment.navigationCoordinator.navigate(to: destination)
            return
        }

        // All other destinations use standard navigation
        appEnvironment.navigationCoordinator.navigate(to: destination)
    }

    /// Play a video from Handoff continuation.
    private func playVideoFromHandoff(videoID: VideoID, startTime: TimeInterval?) async {
        LoggingService.shared.debug("[Handoff] playVideoFromHandoff called for: \(videoID.videoID)", category: .general)

        guard let instance = appEnvironment.instancesManager.instance(for: videoID.source) else {
            LoggingService.shared.debug("[Handoff] No instance available, falling back to navigation", category: .general)
            // Fall back to navigation if no instance available
            appEnvironment.navigationCoordinator.navigate(to: .video(.id(videoID)))
            return
        }

        do {
            let video = try await appEnvironment.contentService.video(
                id: videoID.videoID,
                instance: instance
            )
            LoggingService.shared.debug("[Handoff] Video fetched, calling openVideo", category: .general)
            appEnvironment.playerService.openVideo(video, startTime: startTime)

            // Always expand player after handoff (unless PiP is active)
            // We add a small delay to ensure ContentView has set up its .onChange observers
            // (during app launch via Handoff, the trigger can fire before the view is ready)
            #if os(iOS)
            let isPiPActive = appEnvironment.playerService.state.pipState == .active
            #else
            let isPiPActive = false
            #endif
            LoggingService.shared.debug("[Handoff] isPiPActive: \(isPiPActive), isPlayerExpanded: \(appEnvironment.navigationCoordinator.isPlayerExpanded)", category: .general)
            if !isPiPActive {
                // Small delay to ensure view hierarchy is ready to observe trigger changes
                try? await Task.sleep(for: .milliseconds(100))
                LoggingService.shared.debug("[Handoff] Expanding player from handoff", category: .general)
                appEnvironment.navigationCoordinator.expandPlayer()
            }
        } catch {
            LoggingService.shared.debug("[Handoff] Failed to fetch video: \(error), falling back to navigation", category: .general)
            // If video fetch fails, fall back to navigating to the video info view
            appEnvironment.navigationCoordinator.navigate(to: .video(.id(videoID)))
        }
    }

    // MARK: - Clipboard Detection

    /// Check clipboard for external video URLs when app becomes active.
    private func checkClipboardForExternalURL() {
        #if os(iOS)
        guard appEnvironment.settingsManager.clipboardURLDetectionEnabled else { return }

        let clipboardURL: URL?
        if UIPasteboard.general.hasURLs {
            clipboardURL = UIPasteboard.general.url
        } else if let string = UIPasteboard.general.string,
                  let url = URL(string: string),
                  url.scheme == "http" || url.scheme == "https" {
            clipboardURL = url
        } else {
            clipboardURL = nil
        }

        guard let url = clipboardURL else { return }

        // Skip if we already checked this URL
        guard url != lastCheckedClipboardURL else { return }
        lastCheckedClipboardURL = url

        // Skip YouTube URLs - they're handled by regular deep links
        if isYouTubeURL(url) { return }

        // Skip known non-video sites
        if isExcludedHost(url) { return }

        // Only prompt if Yattee Server is configured
        guard appEnvironment.instancesManager.yatteeServerInstance != nil else { return }

        detectedClipboardURL = url
        showingClipboardAlert = true
        #elseif os(macOS)
        guard appEnvironment.settingsManager.clipboardURLDetectionEnabled else { return }

        guard let string = NSPasteboard.general.string(forType: .string),
              let url = URL(string: string),
              url.scheme == "http" || url.scheme == "https" else {
            return
        }

        // Skip if we already checked this URL
        guard url != lastCheckedClipboardURL else { return }
        lastCheckedClipboardURL = url

        // Skip YouTube URLs
        if isYouTubeURL(url) { return }

        // Skip known non-video sites
        if isExcludedHost(url) { return }

        // Only prompt if Yattee Server is configured
        guard appEnvironment.instancesManager.yatteeServerInstance != nil else { return }

        detectedClipboardURL = url
        showingClipboardAlert = true
        #endif
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let youtubeHosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "www.youtu.be"]
        return youtubeHosts.contains(host)
    }

    private func isExcludedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        let excludedHosts = [
            "google.com", "www.google.com",
            "bing.com", "www.bing.com",
            "duckduckgo.com",
            "apple.com", "www.apple.com",
            "github.com", "www.github.com"
        ]
        return excludedHosts.contains(host)
    }
}
