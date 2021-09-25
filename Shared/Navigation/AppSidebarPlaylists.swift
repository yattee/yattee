import SwiftUI

struct AppSidebarPlaylists: View {
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlaylistsModel> private var playlists

    @Binding var selection: TabSelection?

    var body: some View {
        Section(header: Text("Playlists")) {
            ForEach(playlists.playlists.sorted { $0.title.lowercased() < $1.title.lowercased() }) { playlist in
                NavigationLink(tag: TabSelection.playlist(playlist.id), selection: $selection) {
                    LazyView(PlaylistVideosView(playlist))
                } label: {
                    Label(playlist.title, systemImage: AppSidebarNavigation.symbolSystemImage(playlist.title))
                        .badge(Text("\(playlist.videos.count)"))
                }
                .id(playlist.id)
                .contextMenu {
                    Button("Edit") {
                        navigation.presentEditPlaylistForm(playlists.find(id: playlist.id))
                    }
                }
            }

            newPlaylistButton
                .padding(.top, 8)
        }
        .onAppear {
            playlists.load()
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
