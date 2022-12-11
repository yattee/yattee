import Defaults
import SwiftUI

struct PlaceholderCell: View {
    var body: some View {
        VideoCell(id: UUID().uuidString, video: .fixture)
            .redacted(reason: .placeholder)
    }
}

struct PlaceholderCell_Previews: PreviewProvider {
    static var previews: some View {
        PlaceholderCell()
            .injectFixtureEnvironmentObjects()
    }
}
