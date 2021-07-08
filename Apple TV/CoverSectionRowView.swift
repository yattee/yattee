import SwiftUI

struct CoverSectionRowView<Content: View>: View {
    let label: String?
    let controlView: Content

    init(_ label: String? = nil, @ViewBuilder controlView: @escaping () -> Content) {
        self.label = label
        self.controlView = controlView()
    }

    var body: some View {
        HStack {
            Text(label ?? "")
            Spacer()
            controlView
        }
    }
}
