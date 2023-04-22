import Defaults
import Foundation
import SwiftUI

struct Constants {
    static let yatteeProtocol = "yattee://"
    static let overlayAnimation = Animation.linear(duration: 0.2)
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

    static var detailsVisibility: Bool {
        #if os(iOS)
            false
        #else
            true
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
