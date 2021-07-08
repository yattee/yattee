import Siesta
import SwiftUI

struct PlaylistsView: View {
    @ObservedObject private var store = Store<[Playlist]>()

    @State private var selectedPlaylist: Playlist?

    @State private var showingNewPlaylist = false
    @State private var createdPlaylist: Playlist?

    var resource: Resource {
        InvidiousAPI.shared.playlists
    }

    init() {
        resource.addObserver(store)
    }

    var body: some View {
        Section {
            VStack(alignment: .center, spacing: 2) {
                HStack {
                    selectPlaylistButton

                    newPlaylistButton
                }
                .scaleEffect(0.85)

                if currentPlaylist != nil {
                    VideosView(videos: currentPlaylist!.videos)
                } else {
                    Spacer()
                }
            }
        }
        .fullScreenCover(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
            NewPlaylistView(createdPlaylist: $createdPlaylist)
        }
        .onAppear {
            resource.loadIfNeeded()
        }
    }

    func selectCreatedPlaylist() {
        guard createdPlaylist != nil else {
            return
        }

        resource.load().onSuccess { _ in
            self.selectedPlaylist = store.collection.first { $0 == createdPlaylist }
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

    var newPlaylistButton: some View {
        Button(action: { self.showingNewPlaylist = true }) {
            Image(systemName: "plus")
        }
    }
}
