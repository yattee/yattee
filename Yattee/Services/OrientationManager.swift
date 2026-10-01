//
//  OrientationManager.swift
//  Yattee
//
//  Provides supported interface orientations for the app.
//  Supports in-app orientation locking when the player is visible.
//

#if os(iOS)

import Observation
import UIKit

/// Provides supported interface orientations.
/// Supports in-app orientation locking to the current orientation.
@MainActor
@Observable
final class OrientationManager {
    static let shared = OrientationManager()

    private init() {}

    /// Whether `requestGeometryUpdate(.iOS(interfaceOrientations:))` is honored
    /// in the current windowing mode. False on the iPhone Duo interior display,
    /// where the system refuses programmatic rotation (`UISceneErrorDomain` 101)
    /// the same way it does for iPad multitasking. Set from the hinge state and
    /// cleared when a request is refused, so the player falls back to the
    /// iPad-style details toggle instead of doing nothing.
    /// While false, the in-app orientation lock is suspended as well: the
    /// system decides the orientation there, so pinning `supportedOrientations`
    /// only fights the user's physical rotation (Duo hinge open, simulator
    /// forced tabletop).
    var canRotateProgrammatically = true {
        didSet {
            if !canRotateProgrammatically && isLocked {
                unlock()
            }
        }
    }

    /// `UISceneErrorDomain` code returned when the windowing mode forbids
    /// programmatic interface orientation changes.
    static let orientationChangeForbiddenErrorCode = 101

    /// Records a refused rotation request; returns true when the error is the
    /// windowing-mode refusal (as opposed to a transient failure).
    @discardableResult
    func noteGeometryUpdateFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == UISceneErrorDomain,
              nsError.code == Self.orientationChangeForbiddenErrorCode else { return false }
        canRotateProgrammatically = false
        return true
    }

    /// The orientation to lock to when `isLocked` is true.
    /// Updated when orientation lock is enabled to capture current orientation.
    private var lockedOrientation: UIInterfaceOrientationMask?

    /// Whether orientation is currently locked.
    private(set) var isLocked: Bool = false

    /// Lock orientation to the current orientation
    func lock() {
        guard !isLocked, canRotateProgrammatically else { return }
        lockedOrientation = currentInterfaceOrientationMask
        isLocked = true
        notifyOrientationChange()
    }

    /// Lock to a specific orientation
    func lock(to orientation: UIInterfaceOrientationMask) {
        guard canRotateProgrammatically else { return }
        lockedOrientation = orientation
        isLocked = true
        notifyOrientationChange()
    }

    /// Re-lock to the current orientation (updates locked orientation even if already locked)
    func lockToCurrentOrientation() {
        guard canRotateProgrammatically else { return }
        lockedOrientation = currentInterfaceOrientationMask
        isLocked = true
        notifyOrientationChange()
    }

    /// Unlock orientation to allow all rotations again
    func unlock() {
        guard isLocked else { return }
        isLocked = false
        lockedOrientation = nil
        notifyOrientationChange()
    }

    // TODO: Modernization - Consider adopting `prefersInterfaceOrientationLocked` (iOS 26+)
    // as the modern replacement for orientation locking via `supportedInterfaceOrientations`.
    /// Returns the supported interface orientations.
    /// When locked, returns only the locked orientation.
    /// Otherwise: iPhone = all except upside-down, iPad = all
    var supportedOrientations: UIInterfaceOrientationMask {
        if isLocked, let locked = lockedOrientation {
            return locked
        }

        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    /// Notify the system that supported orientations have changed
    private func notifyOrientationChange() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        // Tell all view controllers to re-query supported orientations
        for window in windowScene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    /// Get the current interface orientation as a mask
    var currentInterfaceOrientationMask: UIInterfaceOrientationMask {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return .allButUpsideDown
        }

        let screenBounds = windowScene.screen.bounds
        if screenBounds.width > screenBounds.height {
            // Currently landscape - determine which side based on interface orientation
            let interfaceOrientation = windowScene.interfaceOrientation
            switch interfaceOrientation {
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            default:
                return .landscape
            }
        } else {
            return .portrait
        }
    }
}

#endif
