//
//  BackgroundRefreshManager.swift
//  Yattee
//
//  Platform-specific background refresh orchestration.
//

import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// Manages background refresh scheduling and execution across platforms.
@MainActor
final class BackgroundRefreshManager {
    // MARK: - Constants

    static let backgroundTaskIdentifier = AppIdentifiers.backgroundFeedRefresh

    #if os(macOS)
    private var activityScheduler: NSBackgroundActivityScheduler?
    #endif

    // MARK: - Dependencies

    private weak var appEnvironment: AppEnvironment?
    private let backgroundRefresher: BackgroundFeedRefresher
    private let notificationManager: NotificationManager

    // MARK: - Initialization

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
        self.backgroundRefresher = BackgroundFeedRefresher(notificationManager: notificationManager)
    }

    func setAppEnvironment(_ environment: AppEnvironment) {
        self.appEnvironment = environment
        backgroundRefresher.setAppEnvironment(environment)
    }

    // MARK: - Registration (call at app launch)

    func registerBackgroundTasks() {
        #if os(iOS)
        guard !ProcessInfo.processInfo.isMacCatalystApp else { return }
        registerIOSBackgroundTask()
        #elseif os(macOS)
        registerMacOSBackgroundActivity()
        #endif
    }

    // MARK: - iOS Implementation

    #if os(iOS)
    private func registerIOSBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            self?.handleIOSBackgroundTask(task)
        }
        LoggingService.shared.info("Registered iOS background task", category: .notifications)
    }

    func scheduleIOSBackgroundRefresh() {
        guard !ProcessInfo.processInfo.isMacCatalystApp else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Request to run in ~15 minutes (system decides actual timing)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            LoggingService.shared.info("Scheduled iOS background refresh", category: .notifications)
        } catch {
            LoggingService.shared.logNotificationError("Failed to schedule background refresh", error: error)
        }
    }

    func cancelIOSBackgroundRefresh() {
        guard !ProcessInfo.processInfo.isMacCatalystApp else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        LoggingService.shared.debug("Cancelled iOS background refresh", category: .notifications)
    }

    private func handleIOSBackgroundTask(_ task: BGAppRefreshTask) {
        LoggingService.shared.info("iOS background task started", category: .notifications)

        // Schedule the next refresh immediately
        scheduleIOSBackgroundRefresh()

        // Create a task to perform the refresh
        let refreshTask = Task { @MainActor in
            await backgroundRefresher.performBackgroundRefresh()
        }

        // Set expiration handler
        task.expirationHandler = {
            LoggingService.shared.warning("iOS background task expired", category: .notifications)
            refreshTask.cancel()
        }

        // Wait for completion
        Task {
            _ = await refreshTask.result
            task.setTaskCompleted(success: !refreshTask.isCancelled)
            LoggingService.shared.info("iOS background task completed", category: .notifications)
        }
    }
    #endif

    // MARK: - macOS Implementation

    #if os(macOS)
    private func registerMacOSBackgroundActivity() {
        let scheduler = NSBackgroundActivityScheduler(identifier: Self.backgroundTaskIdentifier)
        scheduler.repeats = true
        #if DEBUG
        scheduler.interval = 60  // 1 minute for testing
        scheduler.tolerance = 30
        #else
        scheduler.interval = 15 * 60  // 15 minutes
        scheduler.tolerance = 5 * 60  // 5 minute tolerance
        #endif
        scheduler.qualityOfService = .utility

        scheduler.schedule { [weak self] completion in
            guard let self else {
                completion(.finished)
                return
            }

            Task { @MainActor in
                LoggingService.shared.info("macOS background activity started", category: .notifications)
                await self.backgroundRefresher.performBackgroundRefresh()
                completion(.finished)
                LoggingService.shared.info("macOS background activity completed", category: .notifications)
            }
        }

        self.activityScheduler = scheduler
        LoggingService.shared.info("Registered macOS background activity", category: .notifications)
    }

    func invalidateMacOSScheduler() {
        activityScheduler?.invalidate()
        activityScheduler = nil
        LoggingService.shared.debug("Invalidated macOS background scheduler", category: .notifications)
    }

    func restartMacOSScheduler() {
        invalidateMacOSScheduler()
        registerMacOSBackgroundActivity()
    }
    #endif

    // MARK: - Enable/Disable

    func handleNotificationsEnabledChanged(_ enabled: Bool) {
        #if os(iOS)
        guard !ProcessInfo.processInfo.isMacCatalystApp else { return }
        if enabled {
            scheduleIOSBackgroundRefresh()
        } else {
            cancelIOSBackgroundRefresh()
        }
        #elseif os(macOS)
        if enabled {
            if activityScheduler == nil {
                registerMacOSBackgroundActivity()
            }
        } else {
            invalidateMacOSScheduler()
        }
        #endif
    }
}
