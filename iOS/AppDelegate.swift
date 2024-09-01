import AVFoundation
import Defaults
import Foundation
import Logging
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var orientationLock = UIInterfaceOrientationMask.portrait // Start locked to portrait

    private var logger = Logger(label: "stream.yattee.app.delegate")
    private(set) static var instance: AppDelegate!

    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { // swiftlint:disable:this discouraged_optional_collection
        Self.instance = self

        #if !os(macOS)
            UIViewController.swizzleHomeIndicatorProperty()
            OrientationTracker.shared.startDeviceOrientationTracking()
            OrientationModel.shared.startOrientationUpdates()

            // Force lock orientation to portrait if lockPortraitWhenBrowsing is true
            if Defaults[.lockPortraitWhenBrowsing] {
                Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
            }

            // Configure the audio session for playback
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            } catch {
                logger.error("Failed to set audio session category: \(error)")
            }

            // Begin receiving remote control events
            UIApplication.shared.beginReceivingRemoteControlEvents()

            // Allow all orientations after a brief delay to ensure the app starts in portrait
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.orientationLock = .all
            }
        #endif

        return true
    }

    func application(_: UIApplication, open url: URL, options _: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme == "yattee" {
            OpenURLHandler(navigationStyle: Constants.defaultNavigationStyle).handle(url)
            return true
        }
        return false
    }
}
