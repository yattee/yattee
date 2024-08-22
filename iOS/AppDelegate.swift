import Defaults
import Foundation
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    // Holds the current orientation lock setting
    var orientationLock: UIInterfaceOrientationMask = .all

    // Singleton instance for access
    private(set) static var instance: AppDelegate!

    // Determine supported interface orientations
    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { // swiftlint:disable:this discouraged_optional_collection
        Self.instance = self

        #if os(iOS)
        // Perform any necessary swizzling or setup
        UIViewController.swizzleHomeIndicatorProperty()

        // Start orientation tracking
        OrientationTracker.shared.startDeviceOrientationTracking()

        // Check and apply orientation lock if necessary
        applyInitialOrientationLock()
        #endif

        return true
    }

    // Handle URLs opened by the app
    func application(_: UIApplication, open url: URL, options _: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Handle custom URL scheme
        if url.scheme == "yattee" {
            OpenURLHandler(navigationStyle: Constants.defaultNavigationStyle).handle(url)
            return true
        }
        return false
    }

    // Function to apply initial orientation lock based on Defaults
    private func applyInitialOrientationLock() {
        if Defaults[.lockPortraitWhenBrowsing] {
            orientationLock = .portrait
            Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
        } else {
            orientationLock = .all
        }
    }
}
