import Defaults
import SwiftUI

struct EmptyItems: View {
    @Default(.hideShorts) private var hideShorts
    @Default(.hideWatched) private var hideWatched

    var isLoading = false
    var onDisableFilters: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading) {
            Group {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Loading...")
                    }
                } else {
                    Text(emptyItemsText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.secondary)

            if hideShorts || hideWatched {
                AccentButton(text: "Disable filters", maxWidth: nil, verticalPadding: 0, minHeight: 30) {
                    hideShorts = false
                    hideWatched = false
                    onDisableFilters()
                }
            }
        }
    }

    var emptyItemsText: String {
        var filterText = ""
        if hideShorts && hideWatched {
            filterText = "(watched and shorts hidden)"
        } else if hideShorts {
            filterText = "(shorts hidden)"
        } else if hideWatched {
            filterText = "(watched hidden)"
        }

        return "No videos to show".localized() + " " + filterText.localized()
    }
}

struct EmptyItems_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            EmptyItems()
            Spacer()
            EmptyItems(isLoading: true)
            Spacer()
        }
        .padding()
    }
}
