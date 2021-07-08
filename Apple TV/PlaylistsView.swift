import Defaults
import Siesta
import SwiftUI

struct PlaylistsView: View {
    @ObservedObject private var store = Store<[Playlist]>()

    @Default(.selectedPlaylistID) private var selectedPlaylistID
    @State private var selectedPlaylist: Playlist?

    @State private var showingNewPlaylist = false
    @State private var createdPlaylist: Playlist?

    @State private var showingEditPlaylist = false
    @State private var editedPlaylist: Playlist?

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

                    if currentPlaylist != nil {
                        editPlaylistButton
                    }

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
            PlaylistFormView(playlist: $createdPlaylist)
        }
        .fullScreenCover(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
            PlaylistFormView(playlist: $editedPlaylist)
        }
        .onAppear {
            resource.loadIfNeeded()?.onSuccess { _ in
                selectPlaylist(selectedPlaylistID)
            }
        }
    }

    func selectPlaylist(_ id: String?) {
        selectedPlaylist = store.collection.first { $0.id == id }
        selectedPlaylistID = id
    }

    func selectCreatedPlaylist() {
        guard createdPlaylist != nil else {
            return
        }

        resource.load().onSuccess { _ in
            self.selectPlaylist(createdPlaylist?.id)

            self.createdPlaylist = nil
        }
    }

    func selectEditedPlaylist() {
        if editedPlaylist == nil {
            selectPlaylist(nil)
        }

        resource.load().onSuccess { _ in
            selectPlaylist(editedPlaylist?.id)

            self.editedPlaylist = nil
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

            selectPlaylist(store.collection.next(after: currentPlaylist!)?.id)
        }
        .contextMenu {
            ForEach(store.collection) { playlist in
                Button(playlist.title) {
                    selectPlaylist(playlist.id)
                }
            }
        }
    }

    var editPlaylistButton: some View {
        Button(action: {
            self.editedPlaylist = self.currentPlaylist
            self.showingEditPlaylist = true
        }) {
            Image(systemName: "pencil")
        }
    }

    var newPlaylistButton: some View {
        Button(action: { self.showingNewPlaylist = true }) {
            Image(systemName: "plus")
        }
    }
}
