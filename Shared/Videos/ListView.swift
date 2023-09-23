import SwiftUI

struct ListView: View {
    var items: [ContentItem]
    var limit: Int? = 10

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
        if let limit, limit >= 0 {
            return Array(items.prefix(limit))
        }

        return items
    }
}

struct ListView_Previews: PreviewProvider {
    static var previews: some View {
        ListView(items: [.init(video: .fixture)])
    }
}
