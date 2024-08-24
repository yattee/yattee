import CoreMotion
import UIKit

public class OrientationTracker {
    public static let shared = OrientationTracker()

    public static let deviceOrientationChangedNotification = NSNotification.Name("DeviceOrientationChangedNotification")

    public var currentDeviceOrientation: UIDeviceOrientation = .portrait

    public var currentInterfaceOrientation: UIInterfaceOrientation {
        switch currentDeviceOrientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }

    public var currentInterfaceOrientationMask: UIInterfaceOrientationMask {
        switch currentInterfaceOrientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }

    public var affineTransform: CGAffineTransform {
        var angleRadians: Double
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

    public func startDeviceOrientationTracking() {
        motionManager.startAccelerometerUpdates(to: queue) { accelerometerData, error in
            guard error == nil else { return }
            guard let accelerometerData else { return }

            let newDeviceOrientation = self.deviceOrientation(forAccelerometerData: accelerometerData)
            guard newDeviceOrientation != self.currentDeviceOrientation else { return }
            self.currentDeviceOrientation = newDeviceOrientation

            NotificationCenter.default.post(
                name: Self.deviceOrientationChangedNotification,
                object: nil,
                userInfo: nil
            )
        }
    }

    public func stopDeviceOrientationTracking() {
        motionManager.stopAccelerometerUpdates()
    }

    private func deviceOrientation(forAccelerometerData accelerometerData: CMAccelerometerData) -> UIDeviceOrientation {
        let threshold = 0.55
        if accelerometerData.acceleration.x >= threshold {
            return .landscapeLeft
        }
        if accelerometerData.acceleration.x <= -threshold {
            return .landscapeRight
        }
        if accelerometerData.acceleration.y <= -threshold {
            return .portrait
        }

        if UIDevice.current.userInterfaceIdiom == .pad && accelerometerData.acceleration.y >= threshold {
            return .portraitUpsideDown
        }

        return currentDeviceOrientation
    }
}
