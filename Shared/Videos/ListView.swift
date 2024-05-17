import SwiftUI

struct ListView: View {
    var items: [ContentItem]
    var limit: Int?

    var body: some View {
        LazyVStack(alignment: .leading) {
            ForEach(limitedItems) { item in
                ContentItemView(item: item)
                    .environment(\.listingStyle, .list)
                    .environment(\.noListingDividers, limit == 1)
                    .transition(.opacity)
            }
        }
    }

    var limitedItems: [ContentItem] {
        Array(items.prefix(limit ?? items.count))
    }
}

struct ListView_Previews: PreviewProvider {
    static var previews: some View {
        ListView(items: [.init(video: .fixture)], limit: 10)
    }
}
