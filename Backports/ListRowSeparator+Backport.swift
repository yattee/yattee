import Foundation
import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func listRowSeparator(_ visible: Bool) -> some View {
        #if !os(tvOS)
            // swiftlint:disable:next deployment_target
            if #available(iOS 15.0, macOS 12.0, *) {
                content
                    .listRowSeparator(visible ? .visible : .hidden)
            } else {
                content
            }
        #else
            content
        #endif
    }
}
