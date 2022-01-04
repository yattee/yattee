import Defaults
import SwiftUI

struct VerticalCells: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @Environment(\.loadMoreContentHandler) private var loadMoreContentHandler

    var items = [ContentItem]()

    var body: some View {
        ScrollView(.vertical, showsIndicators: scrollViewShowsIndicators) {
            LazyVGrid(columns: columns, alignment: .center) {
                ForEach(items.sorted { $0 < $1 }) { item in
                    ContentItemView(item: item)
                        .onAppear { loadMoreContentItemsIfNeeded(current: item) }
                }
            }
            .padding()
        }
        .edgesIgnoringSafeArea(.horizontal)
        #if os(macOS)
            .background(Color.secondaryBackground)
            .frame(minWidth: 360)
        #endif
    }

    func loadMoreContentItemsIfNeeded(current item: ContentItem) {
        let thresholdIndex = items.index(items.endIndex, offsetBy: -5)
        if items.firstIndex(where: { $0.id == item.id }) == thresholdIndex {
            loadMoreContentHandler()
        }
    }

    var columns: [GridItem] {
        #if os(tvOS)
            items.count < 3 ? Array(repeating: GridItem(.fixed(500)), count: [items.count, 1].max()!) : adaptiveItem
        #else
            adaptiveItem
        #endif
    }

    var adaptiveItem: [GridItem] {
        [GridItem(.adaptive(minimum: adaptiveGridItemMinimumSize, maximum: adaptiveGridItemMaximumSize))]
    }

    var adaptiveGridItemMinimumSize: Double {
        #if os(iOS)
            return verticalSizeClass == .regular ? 320 : 800
        #elseif os(tvOS)
            return 600
        #else
            return 320
        #endif
    }

    var adaptiveGridItemMaximumSize: Double {
        #if os(tvOS)
            return 600
        #else
            return .infinity
        #endif
    }

    var scrollViewShowsIndicators: Bool {
        #if !os(tvOS)
            true
        #else
            false
        #endif
    }
}

struct VeticalCells_Previews: PreviewProvider {
    static var previews: some View {
        VerticalCells(items: ContentItem.array(of: Array(repeating: Video.fixture, count: 30)))
            .injectFixtureEnvironmentObjects()
    }
}
