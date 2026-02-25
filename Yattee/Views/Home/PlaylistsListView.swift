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
    @State private var showingNewPlaylist = false
    @State private var playlistToEdit: LocalPlaylist?

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    var body: some View {
        Group {
            if playlists.isEmpty {
                emptyView
            } else {
                listContent
            }
        }
        .navigationTitle(String(localized: "home.playlists.title"))
        #if !os(tvOS)
        .toolbarTitleDisplayMode(.inlineLarge)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
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

    // MARK: - Empty View

    private var emptyView: some View {
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
            ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                VideoListRow(
                    isLast: index == playlists.count - 1,
                    rowStyle: .regular,
                    listStyle: listStyle,
                    contentWidth: 80  // PlaylistRowView thumbnail width
                ) {
                    playlistRow(playlist: playlist)
                }
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
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func playlistRow(playlist: LocalPlaylist) -> some View {
        PlaylistRowView(playlist: playlist)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                appEnvironment?.navigationCoordinator.navigate(to: .playlist(.local(playlist.id, title: playlist.title)))
            }
            .zoomTransitionSource(id: playlist.id)
    }

    private func loadPlaylists() {
        playlists = (dataManager?.playlists() ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
