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
            VStack {
                VerticalCells(items: items, allowEmpty: true) { if shouldDisplayHeader { header } }
                    .environment(\.currentPlaylistID, currentPlaylist?.id)
                    .environment(\.listingStyle, playlistListingStyle)

                if currentPlaylist != nil, items.isEmpty {
                    hintText("Playlist is empty\n\nTap and hold on a video and then \n\"Add to Playlist\"".localized())
                } else if model.all.isEmpty {
                    hintText("You have no playlists\n\nTap on \"New Playlist\" to create one".localized())
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
            ToolbarItem {
                HideWatchedButtons()
            }
            ToolbarItem {
                HideShortsButtons()
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
           let currentPlaylist,
           let cache = ChannelPlaylistsCacheModel.shared.retrievePlaylist(currentPlaylist.channelPlaylist)
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
                                .id(currentPlaylist.id)
                        }
                    }
                }

                if accounts.signedIn {
                    newPlaylistButton
                }

                ListingStyleButtons(listingStyle: $playlistListingStyle)

                Section {
                    HideWatchedButtons()
                    HideShortsButtons()
                }

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
            Button {
                guard currentPlaylist != nil else {
                    return
                }

                selectedPlaylistID = model.all.next(after: currentPlaylist!)?.id ?? ""
            } label: {
                Text(currentPlaylist?.title ?? "Select playlist")
                    .frame(maxWidth: .infinity)
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

    var shouldDisplayHeader: Bool {
        #if os(tvOS)
            true
        #else
            showCacheStatus
        #endif
    }

    var header: some View {
        HStack {
            #if os(tvOS)
                if model.isEmpty {
                    Text("No Playlists")
                        .foregroundColor(.secondary)
                } else {
                    selectPlaylistButton
                }

                if let playlist = currentPlaylist {
                    editPlaylistButton

                    FavoriteButton(item: FavoriteItem(section: .playlist(accounts.current.id, playlist.id)))
                        .labelStyle(.iconOnly)

                    playButtons
                }

                newPlaylistButton

                Spacer()

                ListingStyleButtons(listingStyle: $playlistListingStyle)
                HideWatchedButtons()
                HideShortsButtons()
            #else
                Spacer()
            #endif

            if let account = accounts.current, showCacheStatus {
                CacheStatusHeader(
                    refreshTime: cache.getFormattedPlaylistTime(account: account),
                    isLoading: model.isLoading
                )
            }

            #if os(tvOS)
                Button {
                    model.load(force: true)
                    loadResource()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
            #endif
        }
        .labelStyle(.iconOnly)
        .font(.caption)
        .imageScale(.small)
        #if os(tvOS)
            .padding(.leading, 30)
            .padding(.bottom, 15)
            .padding(.trailing, 30)
        #endif
    }
}

struct PlaylistsView_Provider: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlaylistsView()
        }
    }
}
