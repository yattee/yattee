//
//  DeviceRotationManager.swift
//  Yattee
//
//  Monitors device rotation using accelerometer to detect landscape orientation
//  even when screen rotation is locked.
//

#if os(iOS)
import CoreMotion
import SwiftUI

@Observable
@MainActor
final class DeviceRotationManager {
    static let shared = DeviceRotationManager()

    private let motionManager = CMMotionManager()
    private(set) var isMonitoring = false

    /// Whether monitoring was active before going to background
    private var wasMonitoringBeforeBackground = false

    /// Current scene phase - used to prevent orientation changes while in background
    private var currentScenePhase: ScenePhase = .active

    /// Timestamp of last rotation callback to prevent rapid-fire orientation changes
    private var lastRotationCallbackTime: Date?

    /// Cooldown period in seconds before allowing next rotation callback
    /// This prevents triggering callbacks while previous animation is still in progress
    private let rotationCooldown: TimeInterval = 0.6

    /// Pending rotation check task - used to defer rotation until animation completes
    private var pendingRotationTask: Task<Void, Never>?

    /// Current detected orientation based on accelerometer
    private(set) var detectedOrientation: UIDeviceOrientation = .portrait

    /// Callback when device is rotated to landscape (from portrait)
    var onLandscapeDetected: (() -> Void)?

    /// Callback when device is rotated to portrait
    var onPortraitDetected: (() -> Void)?

    /// Callback when device is rotated between landscape orientations (left <-> right)
    var onLandscapeOrientationChanged: ((UIDeviceOrientation) -> Void)?

    /// Callback to check if in-app orientation lock is enabled.
    /// When this returns true, rotation callbacks are suppressed.
    /// Set by ExpandedPlayerSheet when visible, cleared when dismissed.
    var isOrientationLocked: (() -> Bool)?

    private init() {}

    /// Start monitoring device orientation via accelerometer
    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable else { return }

        // Sync detected orientation with current screen orientation
        syncWithScreenOrientation()

        // If already monitoring, just return (callbacks may have been updated)
        guard !isMonitoring else { return }

        isMonitoring = true
        motionManager.accelerometerUpdateInterval = 0.2 // 5 times per second

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self, let data else { return }

            Task { @MainActor in
                self.processAccelerometerData(data)
            }
        }
    }

    /// Sync detected orientation with current screen orientation
    /// Call this when entering fullscreen to ensure portrait detection works
    func syncWithScreenOrientation() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let screenBounds = windowScene.screen.bounds
        if screenBounds.width > screenBounds.height {
            // Screen is in landscape - set detected to landscape so portrait detection works
            if detectedOrientation != .landscapeLeft && detectedOrientation != .landscapeRight {
                detectedOrientation = .landscapeLeft
            }
        } else {
            // Screen is in portrait
            if detectedOrientation != .portrait && detectedOrientation != .portraitUpsideDown {
                detectedOrientation = .portrait
            }
        }
    }

    /// Stop monitoring device orientation
    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        motionManager.stopAccelerometerUpdates()
        pendingRotationTask?.cancel()
        pendingRotationTask = nil
    }

    /// Handle scene phase changes - stops monitoring in background to prevent
    /// fullscreen entry while app is not visible
    func handleScenePhase(_ phase: ScenePhase) {
        let previousPhase = currentScenePhase
        currentScenePhase = phase

        switch phase {
        case .background, .inactive:
            // Stop accelerometer when going to background
            if isMonitoring {
                wasMonitoringBeforeBackground = true
                motionManager.stopAccelerometerUpdates()
                isMonitoring = false
            }

        case .active:
            // Restart monitoring if it was active before backgrounding
            if wasMonitoringBeforeBackground && previousPhase != .active {
                wasMonitoringBeforeBackground = false
                // Sync orientation with current screen state before restarting
                syncWithScreenOrientation()
                startMonitoring()
            }

        @unknown default:
            break
        }
    }

    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // If in-app orientation lock is enabled, don't process rotation callbacks
        if isOrientationLocked?() == true {
            return
        }

        let x = data.acceleration.x
        let y = data.acceleration.y

        // Determine orientation based on gravity direction
        // Threshold to avoid triggering on slight tilts
        let threshold = 0.6

        let newOrientation: UIDeviceOrientation

        if abs(x) > abs(y) {
            // Landscape orientation
            if x > threshold {
                newOrientation = .landscapeRight
            } else if x < -threshold {
                newOrientation = .landscapeLeft
            } else {
                return // Not tilted enough
            }
        } else {
            // Portrait orientation
            if y < -threshold {
                newOrientation = .portrait
            } else if y > threshold {
                newOrientation = .portraitUpsideDown
            } else {
                return // Not tilted enough
            }
        }

        // Only trigger if orientation changed
        guard newOrientation != detectedOrientation else { return }

        let previousOrientation = detectedOrientation
        detectedOrientation = newOrientation

        // Only trigger callbacks when app is active - prevents fullscreen entry
        // while app is in background (e.g., when rotating device during audio-only playback)
        guard currentScenePhase == .active else { return }

        // Trigger callbacks
        let wasPortrait = previousOrientation == .portrait || previousOrientation == .portraitUpsideDown
        let wasLandscape = previousOrientation == .landscapeLeft || previousOrientation == .landscapeRight
        let isLandscape = newOrientation == .landscapeLeft || newOrientation == .landscapeRight
        let isPortrait = newOrientation == .portrait

        // Check cooldown - if previous animation still in progress, schedule deferred check
        if let lastTime = lastRotationCallbackTime,
           Date().timeIntervalSince(lastTime) < rotationCooldown {
            scheduleDeferredRotationCheck(remainingCooldown: rotationCooldown - Date().timeIntervalSince(lastTime))
            return
        }

        if wasPortrait && isLandscape {
            lastRotationCallbackTime = Date()
            onLandscapeDetected?()
        } else if isPortrait && !wasPortrait {
            lastRotationCallbackTime = Date()
            onPortraitDetected?()
        } else if wasLandscape && isLandscape && previousOrientation != newOrientation {
            // Landscape to landscape rotation (left <-> right)
            // No cooldown for this - it's just updating the orientation, not a full screen transition
            onLandscapeOrientationChanged?(newOrientation)
        }
    }

    /// Schedule a deferred rotation check after cooldown expires
    /// This ensures we don't miss a rotation that happened during animation
    private func scheduleDeferredRotationCheck(remainingCooldown: TimeInterval) {
        // Cancel any existing pending check
        pendingRotationTask?.cancel()

        pendingRotationTask = Task { @MainActor [weak self] in
            // Wait for remaining cooldown
            try? await Task.sleep(nanoseconds: UInt64(remainingCooldown * 1_000_000_000))

            guard !Task.isCancelled, let self else { return }

            // Check current orientation and trigger callback if needed
            self.performDeferredRotationCheck()
        }
    }

    /// Perform deferred rotation check - called after cooldown expires
    private func performDeferredRotationCheck() {
        guard currentScenePhase == .active else { return }

        // Get current screen orientation to compare against detected orientation
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let screenBounds = windowScene.screen.bounds
        let screenIsLandscape = screenBounds.width > screenBounds.height

        let detectedIsLandscape = detectedOrientation == .landscapeLeft || detectedOrientation == .landscapeRight
        let detectedIsPortrait = detectedOrientation == .portrait || detectedOrientation == .portraitUpsideDown

        // If device orientation differs from screen orientation, trigger the appropriate callback
        if detectedIsLandscape && !screenIsLandscape {
            // Device is in landscape but screen is portrait - enter fullscreen
            lastRotationCallbackTime = Date()
            onLandscapeDetected?()
        } else if detectedIsPortrait && screenIsLandscape {
            // Device is in portrait but screen is landscape - exit fullscreen
            lastRotationCallbackTime = Date()
            onPortraitDetected?()
        }
    }

    /// Check if device is currently in landscape orientation
    var isLandscape: Bool {
        detectedOrientation == .landscapeLeft || detectedOrientation == .landscapeRight
    }

    /// Check if device is currently in portrait orientation
    var isPortrait: Bool {
        detectedOrientation == .portrait || detectedOrientation == .portraitUpsideDown
    }
}
#endif
