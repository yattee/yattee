//
//  PlayerBrightness.swift
//  Yattee
//
//  Screen brightness for the player's brightness controls. On iPhone Duo the
//  interior and exterior are separate screens, so `UIScreen.main` can name a
//  display other than the one the player is on: brightness must go to the
//  screen of the window hosting the controls.
//

#if os(iOS)

import UIKit

@MainActor
enum PlayerBrightness {
    /// The screen to control: the host window's screen, else the foreground
    /// scene's, else `UIScreen.main`.
    static func screen(for hostScreen: UIScreen?) -> UIScreen {
        if let hostScreen { return hostScreen }
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return activeScene?.screen ?? UIScreen.main
    }

    static func value(for hostScreen: UIScreen?) -> Double {
        screen(for: hostScreen).brightness
    }

    static func set(_ value: Double, for hostScreen: UIScreen?) {
        screen(for: hostScreen).brightness = value
    }
}

#endif
