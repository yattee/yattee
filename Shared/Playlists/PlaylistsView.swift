import Defaults
import Siesta
import SwiftUI

struct PlaylistsView: View {
    @State private var selectedPlaylistID: Playlist.ID = ""

    @State private var showingNewPlaylist = false
    @State private var createdPlaylist: Playlist?

    @State private var showingEditPlaylist = false
    @State private var editedPlaylist: Playlist?

    @StateObject private var channelPlaylist = Store<ChannelPlaylist>()
    @StateObject private var userPlaylist = Store<Playlist>()

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var model = PlaylistsModel.shared

    private var player = PlayerModel.shared
    private var cache = PlaylistsCacheModel.shared

    @Namespace private var focusNamespace

    @Default(.playlistListingStyle) private var playlistListingStyle
    @Default(.showCacheStatus) private var showCacheStatus

    var items: [ContentItem] {
        var videos = currentPlaylist?.videos ?? []

        if videos.isEmpty {
            videos = userPlaylist.item?.videos ?? channelPlaylist.item?.videos ?? []

            if !accounts.app.userPlaylistsEndpointIncludesVideos {
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
        guard let playlist = currentPlaylist else { return nil }

        let resource = accounts.api.playlist(playlist.id)

        if accounts.app.userPlaylistsUseChannelPlaylistEndpoint {
            resource?.addObserver(channelPlaylist)
        } else {
            resource?.addObserver(userPlaylist)
        }

        return resource
    }

    var body: some View {
        SignInRequiredView(title: "Playlists".localized()) {
            Section {
                VStack {
                    #if os(tvOS)
                        toolbar
                    #endif
                    if currentPlaylist != nil, items.isEmpty {
                        hintText("Playlist is empty\n\nTap and hold on a video and then \n\"Add to Playlist\"".localized())
                    } else if model.all.isEmpty {
                        hintText("You have no playlists\n\nTap on \"New Playlist\" to create one".localized())
                    } else {
                        Group {
                            #if os(tvOS)
                                HorizontalCells(items: items)
                                    .padding(.top, 40)
                                Spacer()
                            #else
                                VerticalCells(items: items) {
                                    if showCacheStatus {
                                        HStack {
                                            Spacer()

                                            CacheStatusHeader(
                                                refreshTime: cache.getFormattedPlaylistTime(account: accounts.current),
                                                isLoading: model.isLoading
                                            )
                                        }
                                    }
                                }
                                .environment(\.scrollViewBottomPadding, 70)
                            #endif
                        }
                        .environment(\.currentPlaylistID, currentPlaylist?.id)
                        .environment(\.listingStyle, playlistListingStyle)
                    }
                }
            }
        }
        .onAppear {
            model.load()
            loadResource()
        }
        .onChange(of: accounts.current) { _ in
            model.load(force: true)
            loadResource()
        }
        .onChange(of: currentPlaylist) { _ in
            channelPlaylist.clear()
            userPlaylist.clear()
            loadResource()
        }
        .onChange(of: model.reloadPlaylists) { _ in
            loadResource()
        }
        #if os(iOS)
        .refreshControl { refreshControl in
            model.load(force: true) {
                model.reloadPlaylists.toggle()
                refreshControl.endRefreshing()
            }
        }
        .backport
        .refreshable {
            DispatchQueue.main.async {
                model.load(force: true) { model.reloadPlaylists.toggle() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                RequestErrorButton(error: model.error)
            }

            ToolbarItem(placement: .principal) {
                playlistsMenu
            }
        }
        #endif
        #if os(tvOS)
        .fullScreenCover(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
            PlaylistFormView(playlist: $createdPlaylist)
        }
        .fullScreenCover(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
            PlaylistFormView(playlist: $editedPlaylist)
        }
        .focusScope(focusNamespace)
        #else
        .background(
            EmptyView()
                .sheet(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
                    PlaylistFormView(playlist: $createdPlaylist)
                }
        )
        .background(
            EmptyView()
                .sheet(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
                    PlaylistFormView(playlist: $editedPlaylist)
                }
        )
        #endif

        #if os(macOS)
        .toolbar {
            ToolbarItem {
                ListingStyleButtons(listingStyle: $playlistListingStyle)
            }
        }
        #else
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    model.load()
                    loadResource()
                }
        #endif
        #if !os(tvOS)
        .background(
            Button("Refresh") {
                resource?.load()
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
    }

    func loadResource() {
        loadCachedResource()
        resource?.load()
            .onSuccess { response in
                if let playlist: Playlist = response.typedContent() {
                    ChannelPlaylistsCacheModel.shared.storePlaylist(playlist: playlist.channelPlaylist)
                }
            }
    }

    func loadCachedResource() {
        if !selectedPlaylistID.isEmpty,
           let cache = ChannelPlaylistsCacheModel.shared.retrievePlaylist(selectedPlaylistID)
        {
            DispatchQueue.main.async {
                self.channelPlaylist.replace(cache)
            }
        }
    }

    #if os(iOS)
        var playlistsMenu: some View {
            let title = currentPlaylist?.title ?? "Playlists"
            return Menu {
                Menu {
                    selectPlaylistButton
                } label: {
                    Label(title, systemImage: "list.and.film")
                }
                Section {
                    if let currentPlaylist {
                        playButtons

                        editPlaylistButton

                        if let account = accounts.current {
                            FavoriteButton(item: FavoriteItem(section: .playlist(account.id, currentPlaylist.id)))
                        }
                    }
                }

                if accounts.signedIn {
                    newPlaylistButton
                }

                ListingStyleButtons(listingStyle: $playlistListingStyle)

                Section {
                    SettingsButtons()
                }
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.and.film")

                        Text(title)
                            .font(.headline)
                    }
                    .foregroundColor(.primary)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .imageScale(.small)
                .lineLimit(1)
                .frame(maxWidth: 320)
                .transaction { t in t.animation = nil }
            }
            .disabled(!accounts.signedIn)
        }
    #endif

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

                    FavoriteButton(item: FavoriteItem(section: .playlist(accounts.current.id, playlist.id)))
                        .labelStyle(.iconOnly)

                    playButtons
                }

                Spacer()

                newPlaylistButton
                    .padding(.leading, 40)
            }
            .labelStyle(.iconOnly)
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
            .lineLimit(1)
            .contextMenu {
                ForEach(model.all) { playlist in
                    Button(playlist.title) {
                        selectedPlaylistID = playlist.id
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        #else
            Picker("Current Playlist", selection: $selectedPlaylistID) {
                ForEach(model.all) { playlist in
                    Text(playlist.title).tag(playlist.id)
                }
            }
        #endif
    }

    var editPlaylistButton: some View {
        Button(action: {
            self.editedPlaylist = self.currentPlaylist
            self.showingEditPlaylist = true
        }) {
            Label("Edit Playlist", systemImage: "rectangle.and.pencil.and.ellipsis")
        }
    }

    var newPlaylistButton: some View {
        Button(action: { self.showingNewPlaylist = true }) {
            Label("New Playlist", systemImage: "plus")
        }
    }

    private var playButtons: some View {
        Group {
            Button {
                player.play(items.compactMap(\.video))
            } label: {
                Label("Play", systemImage: "play")
            }
            Button {
                player.play(items.compactMap(\.video), shuffling: true)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
        }
    }

    private var currentPlaylist: Playlist? {
        if selectedPlaylistID.isEmpty {
            DispatchQueue.main.async {
                self.selectedPlaylistID = model.all.first?.id ?? ""
            }
        }
        return model.find(id: selectedPlaylistID) ?? model.all.first
    }
}

struct PlaylistsView_Provider: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlaylistsView()
        }
    }
}
