//
//  SleepPreventionService.swift
//  Yattee
//
//  Service to prevent system sleep during video playback.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
import IOKit.pwr_mgt
#endif

/// Service that manages system sleep prevention during video playback.
/// Prevents the display from sleeping while video is actively playing.
@MainActor
final class SleepPreventionService {
    /// Whether sleep prevention is currently active.
    private var isPreventingSleep = false

    #if os(macOS)
    /// The IOKit power assertion ID for macOS.
    private var assertionID: IOPMAssertionID = 0
    #endif

    /// Prevents the system from sleeping.
    /// Call this when video playback starts or resumes.
    func preventSleep() {
        guard !isPreventingSleep else { return }
        isPreventingSleep = true

        #if os(iOS) || os(tvOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #elseif os(macOS)
        let reason = "Yattee video playback" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        #endif
    }

    /// Allows the system to sleep normally.
    /// Call this when video playback pauses or stops.
    func allowSleep() {
        guard isPreventingSleep else { return }
        isPreventingSleep = false

        #if os(iOS) || os(tvOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #elseif os(macOS)
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        #endif
    }
}
