import Defaults
import Siesta
import SwiftUI

struct PlaylistsView: View {
    @ObservedObject private var store = Store<[Playlist]>()

    @Default(.selectedPlaylistID) private var selectedPlaylistID

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
                #if os(tvOS)
                    HStack {
                        if store.collection.isEmpty {
                            Text("No Playlists")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Current Playlist")
                                .foregroundColor(.secondary)

                            selectPlaylistButton
                        }

                        if currentPlaylist != nil {
                            editPlaylistButton
                        }

                        newPlaylistButton
                            .padding(.leading, 40)
                    }
                    .scaleEffect(0.85)
                #endif

                if currentPlaylist != nil {
                    if currentPlaylist!.videos.isEmpty {
                        Spacer()

                        Text("Playlist is empty\n\nTap and hold on a video and then tap \"Add to Playlist\"")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Spacer()
                    } else {
                        VideosView(videos: currentPlaylist!.videos)
                    }
                } else {
                    Spacer()
                }
            }
        }
        #if !os(macOS)
            .fullScreenCover(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
                PlaylistFormView(playlist: $createdPlaylist)
            }
            .fullScreenCover(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
                PlaylistFormView(playlist: $editedPlaylist)
            }
        #endif
        .onAppear {
            resource.loadIfNeeded()?.onSuccess { _ in
                selectPlaylist(selectedPlaylistID)
            }
        }
        #if !os(tvOS)
            .navigationTitle("Playlists")
        #elseif os(iOS)
            .navigationBarItems(trailing: newPlaylistButton)
        #endif
    }

    func selectPlaylist(_ id: String?) {
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
        store.collection.first { $0.id == selectedPlaylistID } ?? store.collection.first
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
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                Text("Edit")
            }
        }
    }

    var newPlaylistButton: some View {
        Button(action: { self.showingNewPlaylist = true }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                #if os(tvOS)
                    Text("New Playlist")
                #endif
            }
        }
    }
}
