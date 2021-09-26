import Defaults
import Siesta
import SwiftUI

struct PlaylistsView: View {
    @StateObject private var store = Store<[Playlist]>()

    @EnvironmentObject<InvidiousAPI> private var api

    @State private var showingNewPlaylist = false
    @State private var createdPlaylist: Playlist?

    @State private var showingEditPlaylist = false
    @State private var editedPlaylist: Playlist?

    @Default(.selectedPlaylistID) private var selectedPlaylistID

    var resource: Resource {
        api.playlists
    }

    var videos: [Video] {
        currentPlaylist?.videos ?? []
    }

    var body: some View {
        SignInRequiredView(title: "Playlists") {
            VStack {
                #if os(tvOS)
                    toolbar
                        .font(.system(size: 28))

                #endif
                if currentPlaylist != nil, videos.isEmpty {
                    hintText("Playlist is empty\n\nTap and hold on a video and then tap \"Add to Playlist\"")
                } else if store.collection.isEmpty {
                    hintText("You have no playlists\n\nTap on \"New Playlist\" to create one")
                } else {
                    VideosView(videos: videos)
                }
            }
        }
        #if os(tvOS)
            .fullScreenCover(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
                PlaylistFormView(playlist: $createdPlaylist)
            }
            .fullScreenCover(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
                PlaylistFormView(playlist: $editedPlaylist)
            }
        #else
            .sheet(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
                PlaylistFormView(playlist: $createdPlaylist)
            }
            .sheet(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
                PlaylistFormView(playlist: $editedPlaylist)
            }
        #endif
        .toolbar {
            ToolbarItemGroup {
                #if !os(iOS)
                    if !store.collection.isEmpty {
                        selectPlaylistButton
                    }

                    if currentPlaylist != nil {
                        editPlaylistButton
                    }
                #endif
                newPlaylistButton
            }

            #if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Group {
                        if store.collection.isEmpty {
                            Text("No Playlists")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Current Playlist")
                                .foregroundColor(.secondary)

                            selectPlaylistButton
                        }

                        Spacer()

                        if currentPlaylist != nil {
                            editPlaylistButton
                        }
                    }
                    .transaction { t in t.animation = .none }
                }
            #endif
        }
        .onAppear {
            resource.addObserver(store)

            resource.loadIfNeeded()?.onSuccess { _ in
                selectPlaylist(selectedPlaylistID)
            }
        }
    }

    var toolbar: some View {
        HStack {
            if store.collection.isEmpty {
                Text("No Playlists")
                    .foregroundColor(.secondary)
            } else {
                Text("Current Playlist")
                    .foregroundColor(.secondary)

                selectPlaylistButton
            }

            #if os(iOS)
                Spacer()
            #endif

            if currentPlaylist != nil {
                editPlaylistButton
            }

            #if !os(iOS)
                newPlaylistButton
                    .padding(.leading, 40)
            #endif
        }
    }

    func hintText(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        #if os(macOS)
            .background()
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
        if editedPlaylist.isNil {
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
        #if os(tvOS)
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
        #else
            Menu(currentPlaylist?.title ?? "Select playlist") {
                ForEach(store.collection) { playlist in
                    Button(action: { selectPlaylist(playlist.id) }) {
                        if playlist == self.currentPlaylist {
                            Label(playlist.title, systemImage: "checkmark")
                        } else {
                            Text(playlist.title)
                        }
                    }
                }
            }
        #endif
    }

    var editPlaylistButton: some View {
        Button(action: {
            self.editedPlaylist = self.currentPlaylist
            self.showingEditPlaylist = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
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

struct PlaylistsView_Provider: PreviewProvider {
    static var previews: some View {
        PlaylistsView()
            .environmentObject(NavigationModel())
    }
}
