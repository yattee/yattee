import Defaults
import Siesta
import SwiftUI

struct AddToPlaylistView: View {
    @StateObject private var store = Store<[Playlist]>()

    @State private var selectedPlaylist: Playlist?

    @Default(.videoIDToAddToPlaylist) private var videoID

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject<InvidiousAPI> private var api

    var resource: Resource {
        api.playlists
    }

    init() {
        resource.addObserver(store)
    }

    var body: some View {
        HStack {
            Spacer()

            VStack {
                Spacer()

                if !resource.isLoading && store.collection.isEmpty {
                    CoverSectionView("You have no Playlists", inline: true) {
                        Text("Open \"Playlists\" tab to create new one")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("Go back") {
                        dismiss()
                    }
                    .padding()
                } else if !store.collection.isEmpty {
                    CoverSectionView("Add to Playlist", inline: true) { selectPlaylistButton }

                    CoverSectionRowView {
                        Button("Add", action: addToPlaylist)
                            .disabled(currentPlaylist == nil)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: 1200)

            Spacer()
        }
        .background(.thinMaterial)
        .onAppear {
            resource.loadIfNeeded()?.onSuccess { _ in
                selectedPlaylist = store.collection.first
            }
        }
    }

    var selectPlaylistButton: some View {
        Button(currentPlaylist?.title ?? "Select playlist") {
            guard currentPlaylist != nil else {
                return
            }

            self.selectedPlaylist = store.collection.next(after: currentPlaylist!)
        }
        .contextMenu {
            ForEach(store.collection) { playlist in
                Button(playlist.title) {
                    self.selectedPlaylist = playlist
                }
            }
        }
    }

    var currentPlaylist: Playlist? {
        selectedPlaylist ?? store.collection.first
    }

    func addToPlaylist() {
        guard currentPlaylist != nil else {
            return
        }

        let resource = api.playlistVideos(currentPlaylist!.id)
        let body = ["videoId": videoID]

        resource.request(.post, json: body).onSuccess { _ in
            Defaults.reset(.videoIDToAddToPlaylist)
            api.playlists.load()
            dismiss()
        }
    }
}
