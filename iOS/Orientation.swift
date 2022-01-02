import CoreMotion
import Defaults
import Logging
import UIKit

struct Orientation {
    static var logger = Logger(label: "stream.yattee.orientation")

    static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
        if let delegate = AppDelegate.instance {
            delegate.orientationLock = orientation

            let orientationString = orientation == .portrait ? "portrait" : orientation == .landscapeLeft ? "landscapeLeft" :
                orientation == .landscapeRight ? "landscapeRight" : orientation == .portraitUpsideDown ? "portraitUpsideDown" :
                orientation == .landscape ? "landscape" : orientation == .all ? "all" : "allButUpsideDown"

            logger.info("locking \(orientationString)")
        }
    }

    static func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation: UIInterfaceOrientation? = nil) {
        lockOrientation(orientation)

        guard !rotateOrientation.isNil else {
            return
        }

        UIDevice.current.setValue(rotateOrientation!.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }
}
