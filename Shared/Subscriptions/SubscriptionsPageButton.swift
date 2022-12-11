import Defaults
import SwiftUI

struct SubscriptionsPageButton: View {
    @Default(.subscriptionsViewPage) private var subscriptionsViewPage

    var body: some View {
        Button {
            subscriptionsViewPage = subscriptionsViewPage.next()
        } label: {
            Text(subscriptionsViewPage.rawValue.capitalized)
                .frame(maxWidth: .infinity)
                .font(.caption2)
        }
    }
}

struct SubscriptionsPageButton_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionsPageButton()
    }
}
