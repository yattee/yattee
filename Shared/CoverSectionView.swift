import SwiftUI

struct CoverSectionView<Content: View>: View {
    let title: String?

    let actionsView: Content
    let divider: Bool
    let inline: Bool

    init(_ title: String? = nil, divider: Bool = true, inline: Bool = false, @ViewBuilder actionsView: @escaping () -> Content) {
        self.title = title
        self.divider = divider
        self.inline = inline
        self.actionsView = actionsView()
    }

    var body: some View {
        VStack(alignment: .leading) {
            if inline {
                HStack {
                    if title != nil {
                        sectionTitle
                    }

                    Spacer()
                    actionsView
                }
            } else if title != nil {
                sectionTitle
            }

            if !inline {
                actionsView
            }
        }

        if divider {
            Divider()
                .padding(.vertical)
        }
    }

    var sectionTitle: some View {
        Text(title ?? "")

            .font(.title2)
        #if os(macOS)
            .bold()
        #endif
        .padding(.bottom)
    }
}
