import Defaults
import SwiftUI

struct HorizontalCells: View {
    var items = [ContentItem]()

    @Default(.channelOnThumbnail) private var channelOnThumbnail

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 20) {
                ForEach(items) { item in
                    ContentItemView(item: item)
                        .environment(\.horizontalCells, true)
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
