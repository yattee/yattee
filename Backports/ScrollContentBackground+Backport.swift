import Foundation
import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func scrollContentBackground(_ visibility: Bool) -> some View {
        // swiftlint:disable:next deployment_target
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            content.scrollContentBackground(visibility ? .visible : .hidden)
        } else {
            content
        }
    }
}
