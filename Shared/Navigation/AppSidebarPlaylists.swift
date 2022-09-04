import SwiftUI

struct AppSidebarPlaylists: View {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var playlists

    var body: some View {
        Section(header: Text("Playlists")) {
            ForEach(playlists.playlists.sorted { $0.title.lowercased() < $1.title.lowercased() }) { playlist in
                NavigationLink(tag: TabSelection.playlist(playlist.id), selection: $navigation.tabSelection) {
                    LazyView(PlaylistVideosView(playlist))
                } label: {
                    playlistLabel(playlist)
                }
                .id(playlist.id)
                .contextMenu {
                    Button("Play All") {
                        player.play(playlists.find(id: playlist.id)?.videos ?? [])
                    }
                    Button("Shuffle All") {
                        player.play(playlists.find(id: playlist.id)?.videos ?? [], shuffling: true)
                    }
                    Button("Edit") {
                        navigation.presentEditPlaylistForm(playlists.find(id: playlist.id))
                    }
                }
            }

            newPlaylistButton
                .padding(.top, 8)
        }
    }

    @ViewBuilder func playlistLabel(_ playlist: Playlist) -> some View {
        let label = Label(playlist.title, systemImage: RecentsModel.symbolSystemImage(playlist.title))

        if player.accounts.app.userPlaylistsEndpointIncludesVideos, !playlist.videos.isEmpty {
            label
                .backport
                .badge(Text("\(playlist.videos.count)"))
        } else {
            label
        }
    }

    var newPlaylistButton: some View {
        Button(action: { navigation.presentNewPlaylistForm() }) {
            Label("New Playlist", systemImage: "plus.circle")
        }
        .foregroundColor(.secondary)
        .buttonStyle(.plain)
    }
}
