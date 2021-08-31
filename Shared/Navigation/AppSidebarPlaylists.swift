import SwiftUI

struct AppSidebarPlaylists: View {
    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<Playlists> private var playlists

    @Binding var selection: TabSelection?

    var body: some View {
        Section(header: Text("Playlists")) {
            ForEach(playlists.all) { playlist in
                NavigationLink(tag: TabSelection.playlist(playlist.id), selection: $selection) {
                    PlaylistVideosView(playlist)
                } label: {
                    Label(playlist.title, systemImage: AppSidebarNavigation.symbolSystemImage(playlist.title))
                        .badge(Text("\(playlist.videos.count)"))
                }
                .id(playlist.id)
                .contextMenu {
                    Button("Edit") {
                        navigationState.presentEditPlaylistForm(playlists.find(id: playlist.id))
                    }
                }
            }

            newPlaylistButton
                .padding(.top, 8)
        }
    }

    var newPlaylistButton: some View {
        Button(action: { navigationState.presentNewPlaylistForm() }) {
            Label("New Playlist", systemImage: "plus.square")
        }
        .foregroundColor(.secondary)
        .buttonStyle(.plain)
    }
}
