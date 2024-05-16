import Foundation
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var orientationLock = UIInterfaceOrientationMask.all

    private(set) static var instance: AppDelegate!

    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        orientationLock
    }

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { // swiftlint:disable:this discouraged_optional_collection
        Self.instance = self
        #if os(iOS)
            UIViewController.swizzleHomeIndicatorProperty()

            OrientationTracker.shared.startDeviceOrientationTracking()
        #endif
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if url.scheme == "yattee" {
            OpenURLHandler.handle(url)
            return true
        }
        return false
    }
}
