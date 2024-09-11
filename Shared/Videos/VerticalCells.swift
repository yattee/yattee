import Defaults
import SwiftUI

struct VerticalCells<Header: View>: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @Environment(\.loadMoreContentHandler) private var loadMoreContentHandler
    @Environment(\.listingStyle) private var listingStyle

    var items = [ContentItem]()
    var allowEmpty = false
    var edgesIgnoringSafeArea = Edge.Set.horizontal

    let header: Header?

    @State private var gridSize = CGSize.zero

    init(
        items: [ContentItem],
        allowEmpty: Bool = false,
        edgesIgnoringSafeArea: Edge.Set = .horizontal,
        @ViewBuilder header: @escaping () -> Header? = { nil }
    ) {
        self.items = items
        self.allowEmpty = allowEmpty
        self.edgesIgnoringSafeArea = edgesIgnoringSafeArea
        self.header = header()
    }

    init(
        items: [ContentItem],
        allowEmpty: Bool = false
    ) where Header == EmptyView {
        self.init(items: items, allowEmpty: allowEmpty) { EmptyView() }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: scrollViewShowsIndicators) {
            LazyVGrid(columns: adaptiveItem, alignment: .center) {
                Section(header: header) {
                    ForEach(contentItems) { item in
                        ContentItemView(item: item)
                            .onAppear { loadMoreContentItemsIfNeeded(current: item) }
                    }
                }
            }
            .padding()
        }
        .animation(nil)
        .edgesIgnoringSafeArea(edgesIgnoringSafeArea)
        #if os(macOS)
            .background(Color.secondaryBackground)
            .frame(minWidth: Constants.contentViewMinWidth)
        #endif
    }

    var contentItems: [ContentItem] {
        items.isEmpty ? (allowEmpty ? items : ContentItem.placeholders) : items.sorted { $0 < $1 }
    }

    func loadMoreContentItemsIfNeeded(current item: ContentItem) {
        let thresholdIndex = items.index(items.endIndex, offsetBy: -5)
        if items.firstIndex(where: { $0.id == item.id }) == thresholdIndex {
            loadMoreContentHandler()
        }
    }

    var adaptiveItem: [GridItem] {
        if listingStyle == .list {
            return [.init(.flexible())]
        }

        return [GridItem(.adaptive(minimum: adaptiveGridItemMinimumSize, maximum: adaptiveGridItemMaximumSize))]
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
