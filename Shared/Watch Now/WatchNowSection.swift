import Defaults
import Siesta
import SwiftUI

struct WatchNowSection: View {
    let resource: Resource
    let label: String

    @StateObject private var store = Store<[Video]>()

    @EnvironmentObject<InvidiousAPI> private var api

    init(resource: Resource, label: String) {
        self.resource = resource
        self.label = label
    }

    var body: some View {
        WatchNowSectionBody(label: label, videos: store.collection)
            .onAppear {
                resource.addObserver(store)
                resource.load()
            }
            .onChange(of: api.account) { _ in
                resource.load()
            }
    }
}
