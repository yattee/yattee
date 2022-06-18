import Foundation
import SwiftUI

struct Buffering: View {
    var reason = "Buffering stream..."
    var state: String?

    var body: some View {
        VStack(spacing: 2) {
            ProgressView()
            #if os(macOS)
                .scaleEffect(0.4)
            #else
                .scaleEffect(0.7)
            #endif
                .frame(maxHeight: 14)
                .progressViewStyle(.circular)

            Text(reason)
                .font(.caption)
            if let state = state {
                Text(state)
                    .font(.caption2.monospacedDigit())
            }
        }
        .padding(8)
        .modifier(ControlBackgroundModifier())
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .foregroundColor(.secondary)
    }
}

struct Buffering_Previews: PreviewProvider {
    static var previews: some View {
        Buffering(state: "100% (2.95s)")
    }
}
