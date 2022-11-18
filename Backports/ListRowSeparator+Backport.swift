import Foundation
import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func listRowSeparator(_ visible: Bool) -> some View {
        if #available(iOS 15, macOS 12, tvOS 15, *) {
            content.listRowSeparator(visible ? .visible : .hidden)
        } else {
            content
        }
    }
}
