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

    static var channelDetailsStackSpacing: Double {
        #if os(tvOS)
            12
        #else
            6
        #endif
    }
}
