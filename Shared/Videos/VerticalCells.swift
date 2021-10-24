import Defaults
import SwiftUI

struct VerticalCells: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var items = [ContentItem]()

    var body: some View {
        ScrollView(.vertical, showsIndicators: scrollViewShowsIndicators) {
            LazyVGrid(columns: columns, alignment: .center) {
                ForEach(items.sorted { $0 < $1 }) { item in
                    ContentItemView(item: item)
                }
            }
            .padding()
        }
        .edgesIgnoringSafeArea(.horizontal)
        #if os(macOS)
            .background()
            .frame(minWidth: 360)
        #endif
    }

    var columns: [GridItem] {
        #if os(tvOS)
            items.count < 3 ? Array(repeating: GridItem(.fixed(540)), count: [items.count, 1].max()!) : adaptiveItem
        #else
            adaptiveItem
        #endif
    }

    var adaptiveItem: [GridItem] {
        [GridItem(.adaptive(minimum: adaptiveGridItemMinimumSize))]
    }

    var adaptiveGridItemMinimumSize: Double {
        #if os(iOS)
            return verticalSizeClass == .regular ? 320 : 800
        #elseif os(tvOS)
            return 540
        #else
            return 320
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
        VerticalCells(items: ContentItem.array(of: Video.allFixtures))
            .injectFixtureEnvironmentObjects()
    }
}
