//
//  SparkleUpdater.swift
//  Yattee
//
//  Sparkle-backed in-app updater for the Developer ID build.
//  Compiled in only when the `SPARKLE` Swift flag is set, which is
//  enabled for the `Release-DeveloperID` build configuration and
//  unset for `Release` (App Store / TestFlight) and `Debug`.
//
//  See AGENTS.md "Build Configurations" for the channel split.
//

#if SPARKLE

import Foundation
import SwiftUI
import Sparkle

/// Observable wrapper around `SPUStandardUpdaterController` so SwiftUI views
/// can bind enable/disable state and trigger manual update checks.
@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// Whether the "Check for Updates…" menu item should be enabled.
    /// Mirrors `SPUUpdater.canCheckForUpdates` and tracks it via KVO.
    private(set) var canCheckForUpdates = false

    /// User preference: receive prerelease (beta) updates in addition to
    /// stable ones. Persisted in UserDefaults so it survives relaunches.
    var wantsBetaChannel: Bool {
        didSet {
            guard oldValue != wantsBetaChannel else { return }
            UserDefaults.standard.set(wantsBetaChannel, forKey: Self.wantsBetaKey)
            // Trigger re-check so the delegate re-reads channels. Deferred to
            // a later main-actor turn so the feed-cache work doesn't run
            // synchronously inside this didSet (which can stutter SwiftUI
            // scrolling). Must stay on main: SPUUpdater is main-thread-only.
            Task { @MainActor in
                self.updaterController.updater.resetUpdateCycle()
            }
        }
    }

    private static let wantsBetaKey = "AppUpdater.wantsBetaChannel"

    private let delegate = AppUpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    private init() {
        // Load persisted beta preference before constructing the delegate.
        // While only beta releases exist, default to the beta channel so
        // testers receive updates without hunting for the Advanced toggle.
        // Revisit this default once the first stable release ships.
        let wantsBeta = UserDefaults.standard.object(forKey: Self.wantsBetaKey) as? Bool ?? true
        self.wantsBetaChannel = wantsBeta
        self.delegate.wantsBeta = wantsBeta

        // `startingUpdater: true` boots the scheduler automatically;
        // Info.plist `SUEnableAutomaticChecks` governs whether it polls.
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )

        // Keep delegate in sync when the toggle changes at runtime.
        self.delegate.wantsBetaProvider = { [weak self] in
            self?.wantsBetaChannel ?? false
        }

        // Observe canCheckForUpdates so menu items can enable/disable correctly.
        // KVO fires on the thread that mutated the property; hop to @MainActor
        // explicitly. Dedupe to avoid SwiftUI re-render storms if Sparkle
        // toggles it rapidly during a feed check cycle.
        self.observation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            let newValue = updater.canCheckForUpdates
            Task { @MainActor [weak self] in
                guard let self, self.canCheckForUpdates != newValue else { return }
                self.canCheckForUpdates = newValue
            }
        }
    }

    /// Triggered by the "Check for Updates…" menu command.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

/// Delegate that exposes the user's channel preference to Sparkle.
/// Sparkle calls `allowedChannels(for:)` each feed refresh.
private final class AppUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// Cached snapshot; read on the main actor by `AppUpdater`.
    var wantsBeta: Bool = false
    /// Live accessor so the delegate reflects the current toggle state.
    var wantsBetaProvider: (() -> Bool)?

    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        let beta = wantsBetaProvider?() ?? wantsBeta
        // Empty set = stable only. Adding "beta" means users get both
        // untagged (stable) items AND items tagged <sparkle:channel>beta</>.
        return beta ? ["beta"] : []
    }
}

#endif
