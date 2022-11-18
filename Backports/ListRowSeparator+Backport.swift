import Foundation
import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func listRowSeparator(_ visible: Bool) -> some View {
        if #available(iOS 15, macOS 13, *) {
            content
            #if !os(tvOS)
            .listRowSeparator(visible ? .visible : .hidden)
            #endif
        } else {
            content
        }
    }
}
