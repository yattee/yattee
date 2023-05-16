import Foundation
import SwiftUI

extension Backport where Content: View {
    @ViewBuilder func playbackSettingsPresentationDetents() -> some View {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            content
                .presentationDetents([.height(400), .large])
        } else {
            content
        }
    }
}
