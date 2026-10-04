//
//  UIApplication+ForegroundScene.swift
//  Yattee
//
//  The window scene and window the user is looking at, for code that has no
//  view of its own to ask. `connectedScenes.first` is not that: on the iPhone
//  Duo it can be the other panel's scene, and it ignores which one is active.
//

#if canImport(UIKit)
import UIKit

extension UIApplication {
    /// The foreground-active scene, else a foreground-inactive one (Control
    /// Center or Notification Center open over the app), else any scene.
    var foregroundWindowScene: UIWindowScene? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    /// The key window of `foregroundWindowScene` (the expanded player's window
    /// while it is up), else its first window.
    var foregroundWindow: UIWindow? {
        let scene = foregroundWindowScene
        return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    }
}
#endif
