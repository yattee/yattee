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
        return true
    }
}
