import SwiftUI

struct OptionRowView<Content: View>: View {
    let label: String
    let controlView: Content

    init(_ label: String, @ViewBuilder controlView: @escaping () -> Content) {
        self.label = label
        self.controlView = controlView()
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            controlView
        }
    }
}
