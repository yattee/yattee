import Defaults
import SwiftUI

struct PlaceholderListItem: View {
    var body: some View {
        VideoBanner(id: UUID().uuidString, video: .fixture)
            .redacted(reason: .placeholder)
    }
}

struct PlaceholderListItem_Previews: PreviewProvider {
    static var previews: some View {
        PlaceholderListItem()
    }
}
