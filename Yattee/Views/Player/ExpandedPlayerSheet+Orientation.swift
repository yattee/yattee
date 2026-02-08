//
//  ExpandedPlayerSheet+Orientation.swift
//  Yattee
//
//  iOS-specific orientation, fullscreen, and ambient glow functionality.
//

import SwiftUI

#if os(iOS)
import UIKit

extension ExpandedPlayerSheet {
    // MARK: - Safe Area Helpers

    /// Get safe area insets from the window.
    var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first?
            .safeAreaInsets ?? .zero
    }

    // MARK: - Orientation Lock

    /// Set up in-app orientation lock callback.
    func setupOrientationLockCallback() {
        DeviceRotationManager.shared.isOrientationLocked = { [weak appEnvironment] in
            appEnvironment?.settingsManager.inAppOrientationLock ?? false
        }
    }

    // MARK: - Fullscreen Toggle

    /// Toggle fullscreen by rotating between portrait and landscape.
    /// When orientation lock is enabled, locks to the target orientation before rotating
    /// (keeps orientation restricted the entire time, just changes which orientation is allowed).
    func toggleFullscreen() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        let screenBounds = windowScene.screen.bounds
        let isCurrentlyLandscape = screenBounds.width > screenBounds.height
        let orientationManager = OrientationManager.shared
        let isOrientationLocked = appEnvironment?.settingsManager.inAppOrientationLock ?? false

        MPVLogging.logTransition("toggleFullscreen",
            fromSize: screenBounds.size,
            toSize: isCurrentlyLandscape ? CGSize(width: screenBounds.height, height: screenBounds.width) : nil)

        if isCurrentlyLandscape {
            // Exit fullscreen → rotate to portrait
            MPVLogging.log("toggleFullscreen: exiting to portrait")
            // Lock to portrait first (if lock enabled) so system allows only portrait rotation
            if isOrientationLocked {
                orientationManager.lock(to: .portrait)
            }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        } else {
            // Enter fullscreen → rotate to landscape
            let targetOrientation = Self.currentLandscapeInterfaceOrientation()
            MPVLogging.log("toggleFullscreen: entering landscape")
            // Lock to landscape first (if lock enabled) so system allows landscape rotation
            // Use .landscape to allow both directions initially
            if isOrientationLocked {
                orientationManager.lock(to: .landscape)
            }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: targetOrientation)) { _ in }
            // After rotation completes, re-lock to the specific landscape orientation
            // Use a delay since completion handler isn't reliable for waiting for rotation
            if isOrientationLocked {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                    orientationManager.lockToCurrentOrientation()
                }
            }
        }
    }

    // MARK: - Rotation Monitoring

    /// Simplified rotation monitoring - handles layout transitions via accelerometer.
    func setupRotationMonitoring() {
        guard let appEnvironment else { return }

        MPVLogging.log("setupRotationMonitoring: starting")
        let rotationManager = DeviceRotationManager.shared

        // Set up callback for landscape detection (request landscape rotation)
        rotationManager.onLandscapeDetected = { [weak appEnvironment] in
            Task { @MainActor in
                guard let appEnvironment else { return }
                guard !appEnvironment.settingsManager.inAppOrientationLock else { return }

                let playerState = appEnvironment.playerService.state

                // Only rotate if we have a video playing
                guard playerState.currentVideo != nil,
                      playerState.pipState != .active else { return }

                // Request landscape rotation
                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }) else { return }

                let screenBounds = windowScene.screen.bounds
                if screenBounds.height > screenBounds.width {
                    let targetOrientation = Self.currentLandscapeInterfaceOrientation()
                    MPVLogging.logTransition("onLandscapeDetected: requesting landscape",
                        fromSize: screenBounds.size, toSize: nil)
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: targetOrientation)) { _ in }
                }
            }
        }

        // Set up callback for portrait detection (request portrait rotation)
        rotationManager.onPortraitDetected = { [weak appEnvironment] in
            Task { @MainActor in
                guard let appEnvironment else { return }
                guard !appEnvironment.settingsManager.inAppOrientationLock else { return }

                // Request portrait rotation
                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }) else { return }

                let screenBounds = windowScene.screen.bounds
                if screenBounds.width > screenBounds.height {
                    MPVLogging.logTransition("onPortraitDetected: requesting portrait",
                        fromSize: screenBounds.size, toSize: nil)
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                }
            }
        }

        // Set up callback for landscape-to-landscape rotation (rotate between left and right)
        rotationManager.onLandscapeOrientationChanged = { [weak appEnvironment] newOrientation in
            Task { @MainActor in
                guard let appEnvironment else { return }
                guard !appEnvironment.settingsManager.inAppOrientationLock else { return }

                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }) else { return }

                // Device and interface orientations are inverted
                let targetOrientation: UIInterfaceOrientationMask = switch newOrientation {
                case .landscapeLeft:
                    .landscapeRight
                case .landscapeRight:
                    .landscapeLeft
                default:
                    .landscape
                }

                MPVLogging.logTransition("onLandscapeOrientationChanged: \(newOrientation.rawValue)")
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: targetOrientation)) { _ in }
            }
        }

        // Always start monitoring
        rotationManager.startMonitoring()
    }

    /// Get the interface orientation mask matching the device's current landscape orientation.
    static func currentLandscapeInterfaceOrientation() -> UIInterfaceOrientationMask {
        let deviceOrientation = DeviceRotationManager.shared.detectedOrientation
        // Device and interface orientations are inverted
        switch deviceOrientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .landscape // Fallback to any landscape
        }
    }

}

#endif
