import Defaults
import SwiftUI

struct HorizontalCells: View {
    var items = [ContentItem]()

    @Environment(\.loadMoreContentHandler) private var loadMoreContentHandler

    @Default(.channelOnThumbnail) private var channelOnThumbnail

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 20) {
                ForEach(contentItems) { item in
                    ContentItemView(item: item)
                        .environment(\.horizontalCells, true)
                        .onAppear { loadMoreContentItemsIfNeeded(current: item) }
                    #if os(tvOS)
                        .frame(width: 580)
                        .padding(.trailing, 20)
                        .padding(.bottom, 40)
                    #else
                        .frame(width: 295)
                    #endif
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            #else
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            #endif
        }
        .frame(height: cellHeight)
        .edgesIgnoringSafeArea(.horizontal)
    }

    var contentItems: [ContentItem] {
        items.isEmpty ? ContentItem.placeholders : items
    }

    func loadMoreContentItemsIfNeeded(current item: ContentItem) {
        let thresholdIndex = items.index(items.endIndex, offsetBy: -5)
        if items.firstIndex(where: { $0.id == item.id }) == thresholdIndex {
            loadMoreContentHandler()
        }
    }

    var cellHeight: Double {
        #if os(tvOS)
            560
        #else
            290 - (channelOnThumbnail ? 23 : 0)
        #endif
    }
}

struct HorizontalCells_Previews: PreviewProvider {
    static var previews: some View {
        HorizontalCells(items: ContentItem.array(of: Video.allFixtures))
            .injectFixtureEnvironmentObjects()
    }
}
