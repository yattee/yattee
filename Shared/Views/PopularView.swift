import Siesta
import SwiftUI

struct PopularView: View {
    @StateObject private var store = Store<[Video]>()

    @EnvironmentObject<InvidiousAPI> private var api

    var resource: Resource {
        api.popular
    }

    var body: some View {
        VideosView(videos: store.collection)
            .onAppear {
                resource.addObserver(store)
                resource.loadIfNeeded()
            }
        #if !os(tvOS)
            .navigationTitle("Popular")
        #endif
    }
}
