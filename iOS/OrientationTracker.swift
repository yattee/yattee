import CoreMotion
import UIKit

/// Singleton class to track device orientation changes using the accelerometer.
public class OrientationTracker {
    public static let shared = OrientationTracker()

    public static let deviceOrientationChangedNotification = NSNotification.Name("DeviceOrientationChangedNotification")

    /// Current device orientation.
    public private(set) var currentDeviceOrientation: UIDeviceOrientation = .portrait

    /// Current interface orientation derived from the device orientation.
    public var currentInterfaceOrientation: UIInterfaceOrientation {
        switch currentDeviceOrientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }

    /// Current interface orientation mask derived from the device orientation.
    public var currentInterfaceOrientationMask: UIInterfaceOrientationMask {
        switch currentInterfaceOrientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }

    /// Affine transform for the current device orientation.
    public var affineTransform: CGAffineTransform {
        let angleRadians: Double
        switch currentDeviceOrientation {
        case .portrait:
            angleRadians = 0
        case .landscapeLeft:
            angleRadians = -0.5 * .pi
        case .landscapeRight:
            angleRadians = 0.5 * .pi
        case .portraitUpsideDown:
            angleRadians = .pi
        default:
            return .identity
        }
        return CGAffineTransform(rotationAngle: angleRadians)
    }

    private let motionManager: CMMotionManager
    private let queue: OperationQueue

    private init() {
        motionManager = CMMotionManager()
        motionManager.accelerometerUpdateInterval = 0.1
        queue = OperationQueue()
    }

    /// Starts tracking device orientation changes.
    public func startDeviceOrientationTracking() {
        motionManager.startAccelerometerUpdates(to: queue) { [weak self] accelerometerData, error in
            guard let self else { return }
            guard error == nil, let accelerometerData else {
                // Consider logging the error
                return
            }

            let newDeviceOrientation = self.deviceOrientation(for: accelerometerData)
            guard newDeviceOrientation != self.currentDeviceOrientation else { return }

            self.currentDeviceOrientation = newDeviceOrientation
            NotificationCenter.default.post(name: Self.deviceOrientationChangedNotification, object: nil)
        }
    }

    /// Stops tracking device orientation changes.
    public func stopDeviceOrientationTracking() {
        motionManager.stopAccelerometerUpdates()
    }

    /// Determines the device orientation based on accelerometer data.
    private func deviceOrientation(for accelerometerData: CMAccelerometerData) -> UIDeviceOrientation {
        let threshold = 0.55

        if accelerometerData.acceleration.x >= threshold {
            // Landscape left
            return .landscapeLeft
        }

        if accelerometerData.acceleration.x <= -threshold {
            // Landscape right
            return .landscapeRight
        }

        if accelerometerData.acceleration.y <= -threshold {
            // Portrait
            return .portrait
        }

        if Constants.isIPad && accelerometerData.acceleration.y >= threshold {
            // iPad specific upside down portrait
            return .portraitUpsideDown
        }

        // Default to the current device orientation if none of the conditions match
        return currentDeviceOrientation
    }
}
