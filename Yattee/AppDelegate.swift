//
//  AppDelegate.swift
//  Yattee
//
//  Platform-specific app delegates for orientation locking (iOS) and Handoff (macOS).
//

import Foundation

#if os(iOS)

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Open the SwiftData stores (TipKit's and the app's) here rather than in
        // `YatteeApp.init()`, which also runs during prewarm launches that iOS
        // suspends before `UIApplicationMain` (0xdead10cc if an SQLite lock is
        // held). The assertion keeps a background launch running until the
        // opens, including any WAL recovery, have finished and released locks.
        DataManager.didFinishLaunching = true
        var storeTask: UIBackgroundTaskIdentifier = .invalid
        storeTask = application.beginBackgroundTask(withName: "OpenDataStore") {
            LoggingService.shared.warning("Background task OpenDataStore expired", category: .diagnostics)
            if storeTask != .invalid {
                application.endBackgroundTask(storeTask)
                storeTask = .invalid
            }
        }
        LoggingService.shared.info(
            "didFinishLaunching",
            category: .diagnostics,
            details: "applicationState: \(application.applicationState.rawValue), "
                + "prewarm: \(ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"), "
                + "launchOptions: \(launchOptions?.keys.map(\.rawValue).sorted() ?? []), "
                // `.invalid` means iOS granted no background time. The stores
                // are opened anyway — deferring would only move the same
                // unprotected open to the first caller (e.g. a silent-push
                // sync) — but the log makes that launch identifiable.
                + "assertion: \(storeTask != .invalid)"
        )
        YatteeApp.configureTips()
        AppEnvironment.shared.dataManager.openStore(trigger: "didFinishLaunching")
        if storeTask != .invalid {
            application.endBackgroundTask(storeTask)
            storeTask = .invalid
        }

        // Required for CKSyncEngine to receive silent push notifications for remote changes.
        // The remote-notification background mode is already in Info.plist.
        LoggingService.shared.logCloudKit("Requesting remote notification registration...")
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        LoggingService.shared.logCloudKit("Registered for remote notifications (token: \(deviceToken.count) bytes)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        LoggingService.shared.logCloudKitError("Failed to register for remote notifications", error: error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        LoggingService.shared.logCloudKit("Received remote notification (keys: \(Array(userInfo.keys)))")
        CloudKitSyncEngine.current?.handleRemoteNotification()
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return OrientationManager.shared.supportedOrientations
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        LoggingService.shared.debug("[Handoff] iOS AppDelegate received activity: \(userActivity.activityType)", category: .general)
        NotificationCenter.default.post(name: .continueUserActivity, object: userActivity)
        return true
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        LoggingService.shared.debug("[Memory] Received memory warning - draining backend pool", category: .general)
        NotificationCenter.default.post(name: .memoryWarning, object: nil)
    }
}

#elseif os(macOS)

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LoggingService.shared.logCloudKit("Requesting remote notification registration...")
        NSApplication.shared.registerForRemoteNotifications()

        if let rawValue = UserDefaults.standard.string(forKey: "appIcon"),
           let icon = AppIcon(rawValue: rawValue) {
            SettingsManager.applyMacAppIcon(icon)
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        LoggingService.shared.logCloudKit("Registered for remote notifications (token: \(deviceToken.count) bytes)")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LoggingService.shared.logCloudKitError("Failed to register for remote notifications", error: error)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        LoggingService.shared.logCloudKit("Received remote notification (keys: \(Array(userInfo.keys)))")
        CloudKitSyncEngine.current?.handleRemoteNotification()
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        LoggingService.shared.debug("[Handoff] macOS AppDelegate received activity: \(userActivity.activityType)", category: .general)
        NotificationCenter.default.post(name: .continueUserActivity, object: userActivity)
        return true
    }
}

#endif

// MARK: - Notification Name

extension Notification.Name {
    static let continueUserActivity = Notification.Name("continueUserActivity")
    static let memoryWarning = Notification.Name("memoryWarning")
}
