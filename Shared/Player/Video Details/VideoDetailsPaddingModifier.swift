import Foundation
import SwiftUI

struct VideoDetailsPaddingModifier: ViewModifier {
    static var defaultAdditionalDetailsPadding = 0.0

    let playerSize: CGSize
    let additionalPadding: Double
    let fullScreen: Bool

    init(
        playerSize: CGSize,
        additionalPadding: Double? = nil,
        fullScreen: Bool = false
    ) {
        self.playerSize = playerSize
        self.additionalPadding = additionalPadding ?? Self.defaultAdditionalDetailsPadding
        self.fullScreen = fullScreen
    }

    var playerHeight: Double {
        playerSize.height
    }

    var topPadding: Double {
        fullScreen ? 0 : (playerHeight + additionalPadding)
    }

    func body(content: Content) -> some View {
        content
            .padding(.top, topPadding)
    }
}
