import Foundation
import Logging
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    private var logger = Logger(label: "stream.yattee.app.tvos.delegate")

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    func application(_: UIApplication, open url: URL, options _: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "yattee" {
            logger.info("handling deep link: \(url.absoluteString)")
            OpenURLHandler(navigationStyle: .tab).handle(url)
            return true
        }
        return false
    }
}
