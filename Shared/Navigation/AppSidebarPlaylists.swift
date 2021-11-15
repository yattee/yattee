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
                    Label(playlist.title, systemImage: AppSidebarNavigation.symbolSystemImage(playlist.title))
                        .badge(Text("\(playlist.videos.count)"))
                }
                .id(playlist.id)
                .contextMenu {
                    Button("Add to queue...") {
                        playlists.find(id: playlist.id)?.videos.forEach { video in
                            player.enqueueVideo(video)
                        }
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

    var newPlaylistButton: some View {
        Button(action: { navigation.presentNewPlaylistForm() }) {
            Label("New Playlist", systemImage: "plus.circle")
        }
        .foregroundColor(.secondary)
        .buttonStyle(.plain)
    }
}
