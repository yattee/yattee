import Defaults
import SwiftUI

struct RelatedView: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var playlists

    var body: some View {
        List {
            if let related = player.currentVideo?.related {
                Section(header: Text("Related")) {
                    ForEach(related) { video in
                        PlayerQueueRow(item: PlayerQueueItem(video))
                            .contextMenu {
                                Section {
                                    Button {
                                        player.playNext(video)
                                    } label: {
                                        Label("Play Next", systemImage: "text.insert")
                                    }
                                    Button {
                                        player.enqueueVideo(video)
                                    } label: {
                                        Label("Play Last", systemImage: "text.append")
                                    }
                                }

                                if accounts.app.supportsUserPlaylists && accounts.signedIn {
                                    Section {
                                        Button {
                                            navigation.presentAddToPlaylist(video)
                                        } label: {
                                            Label("Add to playlist...", systemImage: "text.badge.plus")
                                        }

                                        if let playlist = playlists.lastUsed {
                                            Button {
                                                playlists.addVideo(playlistID: playlist.id, videoID: video.videoID, navigation: navigation)
                                            } label: {
                                                Label("Add to \(playlist.title)", systemImage: "text.badge.star")
                                            }
                                        }
                                    }
                                }
                            }
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #elseif os(iOS)
        .listStyle(.grouped)
        #else
        .listStyle(.plain)
        #endif
    }
}

struct RelatedView_Previews: PreviewProvider {
    static var previews: some View {
        RelatedView()
    }
}
