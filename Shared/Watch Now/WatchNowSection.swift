import Siesta
import SwiftUI

struct WatchNowSection: View {
    @ObservedObject private var store = Store<[Video]>()

    let resource: Resource
    let label: String

    init(resource: Resource, label: String) {
        self.resource = resource
        self.label = label

        self.resource.addObserver(store)
    }

    var body: some View {
        WatchNowSectionBody(label: label, videos: store.collection)
            .onAppear {
                resource.loadIfNeeded()
            }
    }
}
