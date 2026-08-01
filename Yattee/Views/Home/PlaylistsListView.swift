//
//  PlaylistsListView.swift
//  Yattee
//
//  Full page view for listing all playlists.
//

import SwiftUI

struct PlaylistsListView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var playlists: [LocalPlaylist] = []
    @State private var searchText = ""
    @State private var showingNewPlaylist = false
    @State private var playlistToEdit: LocalPlaylist?
    #if os(tvOS)
    @FocusState private var focusedPlaylistID: UUID?
    #endif

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    /// Playlists filtered by search.
    private var filteredPlaylists: [LocalPlaylist] {
        guard !searchText.isEmpty else { return playlists }
        let query = searchText.lowercased()
        return playlists.filter { playlist in
            playlist.title.lowercased().contains(query) ||
            (playlist.playlistDescription?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        Group {
            #if os(tvOS)
            tvOSContent
            #else
            if filteredPlaylists.isEmpty {
                emptyView
            } else {
                listContent
            }
            #endif
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "home.playlists.title"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $searchText, prompt: Text(String(localized: "playlists.search.placeholder")))
        .toolbar {
            #if os(macOS)
            // Pin the trailing group (search field + toolbar buttons) to the right edge,
            // matching the global Search view.
            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        #endif
        .sheet(isPresented: $showingNewPlaylist) {
            PlaylistFormSheet(mode: .create) { title, description in
                _ = dataManager?.createPlaylist(title: title, description: description)
                loadPlaylists()
            }
        }
        .sheet(item: $playlistToEdit) { playlist in
            PlaylistFormSheet(mode: .edit(playlist)) { newTitle, newDescription in
                dataManager?.updatePlaylist(playlist, title: newTitle, description: newDescription)
                loadPlaylists()
            }
        }
        .onAppear {
            loadPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            loadPlaylists()
        }
    }

    #if os(tvOS)
    // MARK: - tvOS Content

    private var tvOSContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                TextField(String(localized: "playlists.search.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)

                Button {
                    showingNewPlaylist = true
                } label: {
                    Label(String(localized: "home.playlists.new"), systemImage: "plus")
                }
            }
            .focusSection()
            .padding(.horizontal, 48)
            .padding(.top, 20)
            .padding(.bottom, 20)

            Group {
                if filteredPlaylists.isEmpty {
                    emptyView
                } else {
                    listContent
                }
            }
            .focusSection()
        }
        .onChange(of: playlists.first?.id, initial: true) { _, newValue in
            // Work around tvOS focus bug: set initial focus to first playlist once cells materialize.
            guard let newValue else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusedPlaylistID = newValue
            }
        }
    }
    #endif

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            noPlaylistsView
        }
    }

    private var noPlaylistsView: some View {
        ContentUnavailableView {
            Label(String(localized: "home.playlists.title"), systemImage: "list.bullet.rectangle")
        } description: {
            Text(String(localized: "home.empty.description"))
        } actions: {
            Button {
                showingNewPlaylist = true
            } label: {
                Label(String(localized: "home.playlists.new"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Content

    private var listContent: some View {
        VideoListContainer(listStyle: listStyle, rowStyle: .regular) {
            Spacer()
                .frame(height: 16)
        } content: {
            ForEach(Array(filteredPlaylists.enumerated()), id: \.element.id) { index, playlist in
                VideoListRow(
                    isLast: index == filteredPlaylists.count - 1,
                    rowStyle: .regular,
                    listStyle: listStyle,
                    contentWidth: 80  // PlaylistRowView thumbnail width
                ) {
                    playlistRow(playlist: playlist)
                }
                #if !os(tvOS)
                .swipeActions {
                    SwipeAction(
                        symbolImage: "pencil",
                        tint: .white,
                        background: .orange
                    ) { reset in
                        playlistToEdit = playlist
                        reset()
                    }
                    SwipeAction(
                        symbolImage: "trash.fill",
                        tint: .white,
                        background: .red
                    ) { reset in
                        dataManager?.deletePlaylist(playlist)
                        loadPlaylists()
                        reset()
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func playlistRow(playlist: LocalPlaylist) -> some View {
        #if os(tvOS)
        NavigationLink(value: NavigationDestination.playlist(.local(playlist.id, title: playlist.title))) {
            PlaylistRowView(playlist: playlist)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zoomTransitionSource(id: playlist.id)
        .focused($focusedPlaylistID, equals: playlist.id)
        #else
        PlaylistRowView(playlist: playlist)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                appEnvironment?.navigationCoordinator.navigate(to: .playlist(.local(playlist.id, title: playlist.title)))
            }
            .zoomTransitionSource(id: playlist.id)
        #endif
    }

    private func loadPlaylists() {
        playlists = (dataManager?.playlists() ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
