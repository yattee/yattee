import Defaults
import SwiftUI

struct SearchOptionsView: View {
    @Default(.searchSortOrder) private var searchSortOrder
    @Default(.searchDate) private var searchDate
    @Default(.searchDuration) private var searchDuration

    var body: some View {
        OptionsSectionView("Search Options") {
            OptionRowView("Sort By") { searchSortOrderButton }
            OptionRowView("Upload date") { searchDateButton }
            OptionRowView("Duration") { searchDurationButton }
        }
    }

    var searchSortOrderButton: some View {
        Button(self.searchSortOrder.name) {
            self.searchSortOrder = self.searchSortOrder.next()
        }
        .contextMenu {
            ForEach(SearchSortOrder.allCases) { sortOrder in
                Button(sortOrder.name) {
                    self.searchSortOrder = sortOrder
                }
            }
        }
    }

    var searchDateButton: some View {
        Button(self.searchDate?.name ?? "All") {
            self.searchDate = self.searchDate == nil ? SearchDate.allCases.first : self.searchDate!.next(nilAtEnd: true)
        }

        .contextMenu {
            ForEach(SearchDate.allCases) { searchDate in
                Button(searchDate.name) {
                    self.searchDate = searchDate
                }
            }

            Button("Reset") {
                self.searchDate = nil
            }
        }
    }

    var searchDurationButton: some View {
        Button(self.searchDuration?.name ?? "All") {
            let duration = Defaults[.searchDuration]

            Defaults[.searchDuration] = duration == nil ? SearchDuration.allCases.first : duration!.next(nilAtEnd: true)
        }
        .contextMenu {
            ForEach(SearchDuration.allCases) { searchDuration in
                Button(searchDuration.name) {
                    Defaults[.searchDuration] = searchDuration
                }
            }

            Button("Reset") {
                Defaults.reset(.searchDuration)
            }
        }
    }
}
