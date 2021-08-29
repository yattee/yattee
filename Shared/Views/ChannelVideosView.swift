import Siesta
import SwiftUI

struct ChannelVideosView: View {
    @ObservedObject private var store = Store<[Video]>()

    let channel: Channel

    var resource: Resource {
        InvidiousAPI.shared.channelVideos(channel.id)
    }

    init(_ channel: Channel) {
        self.channel = channel
        resource.addObserver(store)
    }

    var body: some View {
        VideosView(videos: store.collection)
        #if !os(tvOS)
            .navigationTitle("\(channel.name) Channel")
        #endif
        .onAppear {
            resource.loadIfNeeded()
        }
    }
}
