import Siesta
import SwiftUI

struct WatchNowPlaylistSection: View {
    @ObservedObject private var store = Store<Playlist>()

    let id: String

    var resource: Resource {
        InvidiousAPI.shared.playlist(id)
    }

    init(id: String) {
        self.id = id

        resource.addObserver(store)
    }

    var body: some View {
        WatchNowSectionBody(label: store.item?.title ?? "Loading", videos: store.item?.videos ?? [])
            .onAppear {
                resource.loadIfNeeded()
            }
    }
}
