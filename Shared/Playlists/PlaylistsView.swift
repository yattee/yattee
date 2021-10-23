import Defaults
import Siesta
import SwiftUI

struct PlaylistsView: View {
    @State private var showingNewPlaylist = false
    @State private var createdPlaylist: Playlist?

    @State private var showingEditPlaylist = false
    @State private var editedPlaylist: Playlist?

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var model

    @Namespace private var focusNamespace

    var items: [ContentItem] {
        ContentItem.array(of: model.currentPlaylist?.videos ?? [])
    }

    var body: some View {
        PlayerControlsView {
            SignInRequiredView(title: "Playlists") {
                VStack {
                    #if os(tvOS)
                        toolbar
                    #endif

                    if model.currentPlaylist != nil, items.isEmpty {
                        hintText("Playlist is empty\n\nTap and hold on a video and then tap \"Add to Playlist\"")
                    } else if model.all.isEmpty {
                        hintText("You have no playlists\n\nTap on \"New Playlist\" to create one")
                    } else {
                        #if os(tvOS)
                            HorizontalCells(items: items)
                                .padding(.top, 40)
                            Spacer()
                        #else
                            VerticalCells(items: items)
                        #endif
                    }
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
                    if !model.isEmpty {
                        selectPlaylistButton
                            .prefersDefaultFocus(in: focusNamespace)
                    }

                    if model.currentPlaylist != nil {
                        editPlaylistButton
                    }
                #endif
                newPlaylistButton
            }

            #if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Group {
                        if model.isEmpty {
                            Text("No Playlists")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Current Playlist")
                                .foregroundColor(.secondary)

                            selectPlaylistButton
                        }

                        Spacer()

                        if model.currentPlaylist != nil {
                            editPlaylistButton
                        }
                    }
                    .transaction { t in t.animation = .none }
                }
            #endif
        }
        #if os(tvOS)
            .focusScope(focusNamespace)
        #endif
        .onAppear {
            model.load()
        }
        .onChange(of: accounts.current) { _ in
            model.load(force: true)
        }
    }

    #if os(tvOS)
        var toolbar: some View {
            HStack {
                if model.isEmpty {
                    Text("No Playlists")
                        .foregroundColor(.secondary)
                } else {
                    Text("Current Playlist")
                        .foregroundColor(.secondary)

                    selectPlaylistButton
                }

                Button {
                    player.playAll(items.compactMap(\.video))
                    player.presentPlayer()
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "play.fill")
                        Text("Play All")
                    }
                }

                if model.currentPlaylist != nil {
                    editPlaylistButton
                }

                Spacer()

                newPlaylistButton
                    .padding(.leading, 40)
            }
        }
    #endif

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

    func selectCreatedPlaylist() {
        guard createdPlaylist != nil else {
            return
        }

        model.load(force: true) {
            if let id = createdPlaylist?.id {
                self.model.selectPlaylist(id)
            }

            self.createdPlaylist = nil
        }
    }

    func selectEditedPlaylist() {
        if editedPlaylist.isNil {
            model.selectPlaylist(nil)
        }

        model.load(force: true) {
            model.selectPlaylist(editedPlaylist?.id)

            self.editedPlaylist = nil
        }
    }

    var selectPlaylistButton: some View {
        #if os(tvOS)
            Button(model.currentPlaylist?.title ?? "Select playlist") {
                guard model.currentPlaylist != nil else {
                    return
                }

                model.selectPlaylist(model.all.next(after: model.currentPlaylist!)?.id)
            }
            .contextMenu {
                ForEach(model.all) { playlist in
                    Button(playlist.title) {
                        model.selectPlaylist(playlist.id)
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        #else
            Menu(model.currentPlaylist?.title ?? "Select playlist") {
                ForEach(model.all) { playlist in
                    Button(action: { model.selectPlaylist(playlist.id) }) {
                        if playlist == model.currentPlaylist {
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
            self.editedPlaylist = self.model.currentPlaylist
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
            .injectFixtureEnvironmentObjects()
    }
}
