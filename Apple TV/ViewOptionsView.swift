import Defaults
import SwiftUI

struct ViewOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Default(.layout) var layout

    var body: some View {
        HStack {
            VStack {
                Spacer()

                HStack(alignment: .center) {
                    Spacer()

                    VStack {
                        nextLayoutButton

                        Button("Close") {
                            dismiss()
                        }
                    }

                    Spacer()
                }

                Spacer()
            }

            Spacer()
        }
        .background(.thinMaterial)
    }

    var nextLayoutButton: some View {
        Button(layout.next().name, action: nextLayout)
    }

    func nextLayout() {
        Defaults[.layout] = layout.next()
        dismiss()
    }
}
