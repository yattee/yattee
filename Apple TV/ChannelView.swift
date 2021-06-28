import Siesta
import SwiftUI

struct ChannelView: View {
    @ObservedObject private var store = Store<[Video]>()

    var id: String

    var resource: Resource {
        InvidiousAPI.shared.channelVideos(id)
    }

    init(id: String) {
        self.id = id
        resource.addObserver(store)
    }

    var body: some View {
        VideosListView(videos: store.collection)
            .onAppear {
                resource.loadIfNeeded()
            }
    }
}
