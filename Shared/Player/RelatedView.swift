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
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                VideoContextMenuView(video: video)
                            }
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #elseif os(iOS)
        .listStyle(.grouped)
        .backport
        .scrollContentBackground(false)
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
