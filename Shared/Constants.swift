import Defaults
import Foundation
import SwiftUI

enum Constants {
    static let overlayAnimation = Animation.linear(duration: 0.2)
    static let aspectRatio16x9 = 16.0 / 9.0
    static let aspectRatio4x3 = 4.0 / 3.0

    static var isAppleTV: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .tv
        #else
            false
        #endif
    }

    static var isMac: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .mac
        #else
            false
        #endif
    }

    static var isIPhone: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .phone
        #else
            false
        #endif
    }

    static var isIPad: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .pad
        #else
            false
        #endif
    }

    static var isTvOS: Bool {
        #if os(tvOS)
            true
        #else
            false
        #endif
    }

    static var isMacOS: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }

    static var isIOS: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    static var detailsVisibility: Bool {
        #if os(iOS)
            false
        #else
            true
        #endif
    }

    static var progressViewScale: Double {
        #if os(macOS)
            0.4
        #else
            0.6
        #endif
    }

    static var channelThumbnailSize: Double {
        #if os(tvOS)
            50
        #else
            30
        #endif
    }

    static var sidebarChannelThumbnailSize: Double {
        #if os(macOS)
            20
        #else
            30
        #endif
    }

    static var channelDetailsStackSpacing: Double {
        #if os(tvOS)
            12
        #else
            6
        #endif
    }

    static var contentViewMinWidth: Double {
        #if os(macOS)
            835
        #else
            0
        #endif
    }

    static var deviceName: String {
        #if os(macOS)
            Host().localizedName ?? "Mac"
        #else
            UIDevice.current.name
        #endif
    }

    static var platform: String {
        #if os(macOS)
            "macOS"
        #elseif os(iOS)
            "iOS"
        #elseif os(tvOS)
            "tvOS"
        #else
            "unknown"
        #endif
    }

    static var defaultNavigationStyle: NavigationStyle {
        #if os(macOS)
            return .sidebar
        #elseif os(iOS)
            if isIPad {
                return .sidebar
            }
            return .tab
        #else
            return .tab
        #endif
    }

    static func seekIcon(_ type: String, _ interval: TimeInterval) -> String {
        let interval = Int(interval)
        let allVersions = [10, 15, 30, 45, 60, 75, 90]
        let iOS15 = [5]
        let iconName = "go\(type).\(interval)"

        if #available(iOS 15, macOS 12, *) {
            if iOS15.contains(interval) {
                return iconName
            }
        }

        if allVersions.contains(interval) {
            return iconName
        }

        let sign = type == "forward" ? "plus" : "minus"

        return "go\(type).\(sign)"
    }
}
