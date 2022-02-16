import Defaults
import Siesta
import SwiftUI

struct PlaylistsView: View {
    @State private var selectedPlaylistID: Playlist.ID = ""

    @State private var showingNewPlaylist = false
    @State private var createdPlaylist: Playlist?

    @State private var showingEditPlaylist = false
    @State private var editedPlaylist: Playlist?

    @StateObject private var store = Store<ChannelPlaylist>()

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var model

    @Namespace private var focusNamespace

    var items: [ContentItem] {
        var videos = currentPlaylist?.videos ?? []

        if videos.isEmpty {
            videos = store.item?.videos ?? []
            if !player.accounts.app.userPlaylistsEndpointIncludesVideos {
                var i = 0

                for index in videos.indices {
                    var video = videos[index]
                    video.indexID = "\(i)"
                    i += 1
                    videos[index] = video
                }
            }
        }

        return ContentItem.array(of: videos)
    }

    private var resource: Resource? {
        guard !player.accounts.app.userPlaylistsEndpointIncludesVideos,
              let playlist = currentPlaylist
        else {
            return nil
        }

        let resource = player.accounts.api.playlist(playlist.id)
        resource?.addObserver(store)

        return resource
    }

    var body: some View {
        BrowserPlayerControls(toolbar: {
            HStack {
                HStack {
                    newPlaylistButton
                        .offset(x: -10)
                    if currentPlaylist != nil {
                        editPlaylistButton
                    }
                }

                if !model.isEmpty {
                    Spacer()
                }

                HStack {
                    if model.isEmpty {
                        Text("No Playlists")
                            .foregroundColor(.secondary)
                    } else {
                        selectPlaylistButton
                            .transaction { t in t.animation = .none }
                    }
                }

                Spacer()

                if currentPlaylist != nil {
                    HStack(spacing: 0) {
                        playButton

                        shuffleButton
                    }
                    .offset(x: 10)
                }
            }
            .padding(.horizontal)
        }) {
            SignInRequiredView(title: "Playlists") {
                VStack {
                    #if os(tvOS)
                        toolbar
                    #endif

                    if currentPlaylist != nil, items.isEmpty {
                        hintText("Playlist is empty\n\nTap and hold on a video and then tap \"Add to Playlist\"")
                    } else if model.all.isEmpty {
                        hintText("You have no playlists\n\nTap on \"New Playlist\" to create one")
                    } else {
                        Group {
                            #if os(tvOS)
                                HorizontalCells(items: items)
                                    .padding(.top, 40)
                                Spacer()
                            #else
                                VerticalCells(items: items)
                                    .environment(\.scrollViewBottomPadding, 70)
                            #endif
                        }
                        .environment(\.currentPlaylistID, currentPlaylist?.id)
                    }
                }
            }
        }
        .onAppear {
            model.load()
        }
        .onChange(of: accounts.current) { _ in
            model.load(force: true)
        }
        .onChange(of: selectedPlaylistID) { _ in
            resource?.load()
        }
        .onChange(of: model.reloadPlaylists) { _ in
            resource?.load()
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
            PlaylistFormView(playlist: $createdPlaylist)
                .environmentObject(accounts)
        }
        .fullScreenCover(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
            PlaylistFormView(playlist: $editedPlaylist)
                .environmentObject(accounts)
        }
        .focusScope(focusNamespace)
        #else
        .background(
            EmptyView()
                .sheet(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
                    PlaylistFormView(playlist: $createdPlaylist)
                        .environmentObject(accounts)
                }
        )
        .background(
            EmptyView()
                .sheet(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
                    PlaylistFormView(playlist: $editedPlaylist)
                        .environmentObject(accounts)
                }
        )
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
        #endif
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

                if let playlist = currentPlaylist {
                    editPlaylistButton

                    FavoriteButton(item: FavoriteItem(section: .playlist(playlist.id)))
                        .labelStyle(.iconOnly)

                    playButton
                    shuffleButton
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
            .background(Color.secondaryBackground)
        #endif
    }

    func selectCreatedPlaylist() {
        guard createdPlaylist != nil else {
            return
        }

        model.load(force: true) {
            if let id = createdPlaylist?.id {
                selectedPlaylistID = id
            }

            self.createdPlaylist = nil
        }
    }

    func selectEditedPlaylist() {
        if editedPlaylist.isNil {
            selectedPlaylistID = ""
        }

        model.load(force: true) {
            self.selectedPlaylistID = editedPlaylist?.id ?? ""

            self.editedPlaylist = nil
        }
    }

    var selectPlaylistButton: some View {
        #if os(tvOS)
            Button(currentPlaylist?.title ?? "Select playlist") {
                guard currentPlaylist != nil else {
                    return
                }

                selectedPlaylistID = model.all.next(after: currentPlaylist!)?.id ?? ""
            }
            .contextMenu {
                ForEach(model.all) { playlist in
                    Button(playlist.title) {
                        selectedPlaylistID = playlist.id
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        #else
            Menu {
                ForEach(model.all) { playlist in
                    Button(action: { selectedPlaylistID = playlist.id }) {
                        if playlist == currentPlaylist {
                            Label(playlist.title, systemImage: "checkmark")
                        } else {
                            Text(playlist.title)
                        }
                    }
                }
            } label: {
                Text(currentPlaylist?.title ?? "Select playlist")
                    .frame(maxWidth: 140, alignment: .center)
            }
        #endif
    }

    var editPlaylistButton: some View {
        Button(action: {
            self.editedPlaylist = self.currentPlaylist
            self.showingEditPlaylist = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
            }
        }
    }

    var newPlaylistButton: some View {
        Button(action: { self.showingNewPlaylist = true }) {
            HStack(spacing: 0) {
                Image(systemName: "plus")
                    .padding(8)
                    .contentShape(Rectangle())
                #if os(tvOS)
                    Text("New Playlist")
                #endif
            }
        }
    }

    private var playButton: some View {
        Button {
            player.play(items.compactMap(\.video))
        } label: {
            Image(systemName: "play")
                .padding(8)
                .contentShape(Rectangle())
        }
    }

    private var shuffleButton: some View {
        Button {
            player.play(items.compactMap(\.video), shuffling: true)
        } label: {
            Image(systemName: "shuffle")
                .padding(8)
                .contentShape(Rectangle())
        }
    }

    private var currentPlaylist: Playlist? {
        model.find(id: selectedPlaylistID) ?? model.all.first
    }
}

struct PlaylistsView_Provider: PreviewProvider {
    static var previews: some View {
        PlaylistsView()
            .injectFixtureEnvironmentObjects()
    }
}
