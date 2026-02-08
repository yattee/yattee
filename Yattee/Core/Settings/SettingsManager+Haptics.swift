//
//  SettingsManager+Haptics.swift
//  Yattee
//
//  Haptic feedback settings (iOS only).
//

#if os(iOS)
import CoreHaptics
import Foundation
import UIKit

extension SettingsManager {
    // MARK: - Haptic Feedback Settings

    /// Whether haptic feedback is enabled. Default is true.
    var hapticFeedbackEnabled: Bool {
        get {
            if let cached = _hapticFeedbackEnabled { return cached }
            return bool(for: .hapticFeedbackEnabled, default: true)
        }
        set {
            _hapticFeedbackEnabled = newValue
            set(newValue, for: .hapticFeedbackEnabled)
        }
    }

    /// Haptic feedback intensity. Default is light.
    var hapticFeedbackIntensity: HapticFeedbackIntensity {
        get {
            if let cached = _hapticFeedbackIntensity { return cached }
            return HapticFeedbackIntensity(rawValue: string(for: .hapticFeedbackIntensity) ?? "") ?? .light
        }
        set {
            _hapticFeedbackIntensity = newValue
            set(newValue.rawValue, for: .hapticFeedbackIntensity)
        }
    }

    /// Whether the device supports haptic feedback.
    static var deviceSupportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Triggers haptic feedback for the specified event if enabled.
    func triggerHapticFeedback(for event: HapticEvent) {
        guard Self.deviceSupportsHaptics else { return }
        guard hapticFeedbackEnabled else { return }

        // Determine style - some events override intensity
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch event {
        case .seekGestureActivation:
            style = .light // Always light for activation
        case .seekGestureBoundary:
            style = .medium // Always medium for boundary
        default:
            switch hapticFeedbackIntensity {
            case .off: return
            case .light: style = .light
            case .medium: style = .medium
            case .heavy: style = .heavy
            }
        }

        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
#endif
