import CoreMotion
import Defaults
import Logging
import UIKit

enum Orientation {
    static var logger = Logger(label: "stream.yattee.orientation")

    static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
        if let delegate = AppDelegate.instance {
            delegate.orientationLock = orientation

            let orientationString = orientationString(for: orientation)
            logger.info("Locking orientation to \(orientationString)")
        }
    }

    static func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation: UIInterfaceOrientation? = nil) {
        if Defaults[.lockPortraitWhenBrowsing] {
            // Lock orientation to portrait when browsing
            lockOrientation(.portrait)
            return
        }

        lockOrientation(orientation)

        guard let rotateOrientation else { return }

        let orientationString = orientationString(for: rotateOrientation)
        logger.info("Rotating to \(orientationString)")

        if #available(iOS 16, *) {
            guard let windowScene = Self.scene else { return }
            let rotateOrientationMask = orientationMask(for: rotateOrientation)

            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: rotateOrientationMask)) { error in
                logger.warning("Denied rotation: \(error)")
            }
        } else {
            UIDevice.current.setValue(rotateOrientation.rawValue, forKey: "orientation")
        }

        UINavigationController.attemptRotationToDeviceOrientation()
    }

    private static func orientationString(for orientation: UIInterfaceOrientationMask) -> String {
        switch orientation {
        case .portrait:
            return "portrait"
        case .landscapeLeft:
            return "landscapeLeft"
        case .landscapeRight:
            return "landscapeRight"
        case .portraitUpsideDown:
            return "portraitUpsideDown"
        case .landscape:
            return "landscape"
        case .all:
            return "all"
        case .allButUpsideDown:
            return "allButUpsideDown"
        default:
            return "unknown"
        }
    }

    private static func orientationString(for orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait:
            return "portrait"
        case .landscapeLeft:
            return "landscapeLeft"
        case .landscapeRight:
            return "landscapeRight"
        case .portraitUpsideDown:
            return "portraitUpsideDown"
        default:
            return "unknown"
        }
    }

    private static func orientationMask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait:
            return .portrait
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .allButUpsideDown
        }
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first
    }
}
