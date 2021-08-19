import SwiftUI

struct CoverSectionRowView<ControlContent: View>: View {
    let label: String?
    let controlView: ControlContent

    init(_ label: String? = nil, @ViewBuilder controlView: @escaping () -> ControlContent) {
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
