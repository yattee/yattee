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
        HStack {
            Spacer()

            VStack {
                Spacer()
                VideosView(videos: store.collection)
                    .onAppear {
                        resource.loadIfNeeded()
                    }
                Spacer()
            }

            Spacer()
        }
        .edgesIgnoringSafeArea(.all)
        .background(.ultraThickMaterial)
    }
}
