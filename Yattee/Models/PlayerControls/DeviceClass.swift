//
//  DeviceClass.swift
//  Yattee
//
//  Device class for platform-specific layout sync.
//

import Foundation

/// Device class used for platform-specific layout sync.
/// Layouts only sync between devices of the same class.
enum DeviceClass: String, Codable, Hashable, Sendable {
    /// iPhone and iPad share iOS class.
    case iOS

    /// macOS devices.
    case macOS

    /// Apple TV devices.
    case tvOS

    // MARK: - Current Device

    /// The device class for the current platform.
    static var current: DeviceClass {
        #if os(iOS)
        return .iOS
        #elseif os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #endif
    }

    // MARK: - Display

    /// Localized display name for the device class.
    var displayName: String {
        switch self {
        case .iOS:
            return "iOS"
        case .macOS:
            return "macOS"
        case .tvOS:
            return "tvOS"
        }
    }
}
