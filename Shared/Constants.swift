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
}
