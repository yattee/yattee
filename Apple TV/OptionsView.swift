import Defaults
import SwiftUI

struct OptionsView: View {
    @Environment(\.dismiss) private var dismiss

    @Default(.layout) private var layout
    @Default(.tabSelection) private var tabSelection

    var body: some View {
        HStack {
            VStack {
                HStack {
                    Spacer()

                    VStack(alignment: .leading) {
                        Spacer()

                        tabSelectionOptions

                        CoverSectionView("View Options") {
                            CoverSectionRowView("Show videos as") { nextLayoutButton }
                        }

                        CoverSectionView(divider: false) {
                            CoverSectionRowView("Close View Options") { Button("Close") { dismiss() } }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: 800)

                    Spacer()
                }

                Spacer()
            }
        }
        .background(.thinMaterial)
    }

    var tabSelectionOptions: some View {
        VStack {
            switch tabSelection {
            case .search:
                SearchOptionsView()

            default:
                EmptyView()
            }
        }
    }

    var nextLayoutButton: some View {
        Button(layout.name) {
            self.layout = layout.next()
        }
        .contextMenu {
            ForEach(ListingLayout.allCases) { layout in
                Button(layout.name) {
                    Defaults[.layout] = layout
                }
            }
        }
    }
}

struct OptionsView_Previews: PreviewProvider {
    static var previews: some View {
        OptionsView()
    }
}
