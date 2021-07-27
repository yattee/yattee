import Siesta
import SwiftUI

struct PopularView: View {
    @ObservedObject private var store = Store<[Video]>()

    var resource = InvidiousAPI.shared.popular

    init() {
        resource.addObserver(store)
    }

    var body: some View {
        VideosView(videos: store.collection)
        #if !os(tvOS)
            .navigationTitle("Popular")
        #endif
        .onAppear {
            resource.loadIfNeeded()
        }
    }
}
