import Defaults
import SwiftUI

struct HorizontalCells: View {
    var items = [ContentItem]()

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
                        .frame(width: 285)
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
        #if os(tvOS)
            .frame(height: 560)
        #else
            .frame(height: 250)
        #endif

        .edgesIgnoringSafeArea(.horizontal)
    }
}

struct HorizontalCells_Previews: PreviewProvider {
    static var previews: some View {
        HorizontalCells(items: ContentItem.array(of: Video.allFixtures))
            .injectFixtureEnvironmentObjects()
    }
}
