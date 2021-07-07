import SwiftUI

struct OptionsSectionView<Content: View>: View {
    let title: String?

    let rowsView: Content
    let divider: Bool

    init(_ title: String? = nil, divider: Bool = true, @ViewBuilder rowsView: @escaping () -> Content) {
        self.title = title
        self.divider = divider
        self.rowsView = rowsView()
    }

    var body: some View {
        VStack(alignment: .leading) {
            if title != nil {
                sectionTitle
            }

            rowsView
        }

        if divider {
            Divider()
                .padding(.vertical)
        }
    }

    var sectionTitle: some View {
        Text(title ?? "")
            .font(.title3)
            .padding(.bottom)
    }
}
