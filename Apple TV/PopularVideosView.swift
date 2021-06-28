import Siesta
import SwiftUI

struct PopularVideosView: View {
    @ObservedObject private var store = Store<[Video]>()

    var resource = InvidiousAPI.shared.popular

    init() {
        resource.addObserver(store)
    }

    var body: some View {
        VideosView(videos: store.collection)
            .onAppear {
                resource.loadIfNeeded()
            }
    }
}
