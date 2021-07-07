import Siesta
import SwiftUI

struct PlaylistsView: View {
    @ObservedObject private var store = Store<[Playlist]>()

    @State private var selectedPlaylist: Playlist?

    var resource: Resource {
        InvidiousAPI.shared.playlists
    }

    init() {
        resource.addObserver(store)
    }

    var body: some View {
        Section {
            VStack(alignment: .center, spacing: 2) {
                selectPlaylistButton
                    .scaleEffect(0.85)

                if currentPlaylist != nil {
                    VideosView(videos: currentPlaylist!.videos)
                } else {
                    Spacer()
                }
            }
        }
        .onAppear {
            resource.loadIfNeeded()
        }
    }

    var currentPlaylist: Playlist? {
        selectedPlaylist ?? store.collection.first
    }

    var selectPlaylistButton: some View {
        Button(currentPlaylist?.title ?? "Select playlist") {
            guard currentPlaylist != nil else {
                return
            }

            selectedPlaylist = store.collection.next(after: currentPlaylist!)
        }
        .contextMenu {
            ForEach(store.collection) { playlist in
                Button(playlist.title) {
                    selectedPlaylist = playlist
                }
            }
        }
    }
}
