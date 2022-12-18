import Foundation
import SwiftUI

struct Constants {
    static let yatteeProtocol = "yattee://"
    static let overlayAnimation = Animation.linear(duration: 0.2)
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

    static var descriptionVisibility: Bool {
        #if os(iOS)
            false
        #else
            true
        #endif
    }

    static var nextSystemImage: String {
        if #available(iOS 16, macOS 13, tvOS 16, *) {
            return "film.stack"
        } else {
            return "list.and.film"
        }
    }
}
