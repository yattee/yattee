import Defaults
import SwiftUI

struct SearchOptionsView: View {
    @Default(.searchSortOrder) private var searchSortOrder
    @Default(.searchDate) private var searchDate
    @Default(.searchDuration) private var searchDuration

    var body: some View {
        CoverSectionView("Search Options") {
            CoverSectionRowView("Sort By") { searchSortOrderButton }
            CoverSectionRowView("Upload date") { searchDateButton }
            CoverSectionRowView("Duration") { searchDurationButton }
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
            self.searchDuration = self.searchDuration == nil ? SearchDuration.allCases.first : self.searchDuration!.next(nilAtEnd: true)
        }
        .contextMenu {
            ForEach(SearchDuration.allCases) { searchDuration in
                Button(searchDuration.name) {
                    self.searchDuration = searchDuration
                }
            }

            Button("Reset") {
                self.searchDuration = nil
            }
        }
    }
}
