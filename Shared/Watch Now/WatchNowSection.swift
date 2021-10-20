import Defaults
import Siesta
import SwiftUI

struct WatchNowSection: View {
    let resource: Resource?
    let label: String

    @StateObject private var store = Store<[Video]>()

    @EnvironmentObject<AccountsModel> private var accounts

    init(resource: Resource?, label: String) {
        self.resource = resource
        self.label = label
    }

    var body: some View {
        WatchNowSectionBody(label: label, videos: store.collection)
            .onAppear {
                resource?.addObserver(store)
                resource?.loadIfNeeded()
            }
            .onChange(of: accounts.current) { _ in
                resource?.load()
            }
    }
}
