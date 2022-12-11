import Siesta
import SwiftUI

struct ChannelPlaylistView: View {
    var playlist: ChannelPlaylist?
    var showCloseButton = false

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?

    @StateObject private var store = Store<ChannelPlaylist>()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigationStyle) private var navigationStyle

    @ObservedObject private var accounts = AccountsModel.shared
    var player = PlayerModel.shared
    @ObservedObject private var recents = RecentsModel.shared

    private var items: [ContentItem] {
        ContentItem.array(of: store.item?.videos ?? [])
    }

    private var presentedPlaylist: ChannelPlaylist? {
        playlist ?? recents.presentedPlaylist
    }

    private var resource: Resource? {
        guard let playlist = presentedPlaylist else {
            return nil
        }

        let resource = accounts.api.channelPlaylist(playlist.id)
        resource?.addObserver(store)

        return resource
    }

    var body: some View {
        VStack(alignment: .leading) {
            #if os(tvOS)
                HStack {
                    if let playlist = presentedPlaylist {
                        Text(playlist.title)
                            .font(.title2)
                            .frame(alignment: .leading)

                        Spacer()

                        FavoriteButton(item: FavoriteItem(section: .channelPlaylist(playlist.id, playlist.title)))
                            .labelStyle(.iconOnly)
                    }

                    playButton
                        .labelStyle(.iconOnly)
                }
            #endif
            VerticalCells(items: items)
                .environment(\.inChannelPlaylistView, true)
        }
        .onAppear {
            if navigationStyle == .tab {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    resource?.loadIfNeeded()
                }
            } else {
                resource?.loadIfNeeded()
            }
        }
        #if os(tvOS)
        .background(Color.background(scheme: colorScheme))
        #else
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if showCloseButton {
                    Button {
                        NavigationModel.shared.presentingPlaylist = false
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }

            ToolbarItem(placement: playlistButtonsPlacement) {
                HStack {
                    ShareButton(contentItem: contentItem)

                    if let playlist = presentedPlaylist {
                        FavoriteButton(item: FavoriteItem(section: .channelPlaylist(playlist.id, playlist.title)))
                    }

                    playButton
                }
            }
        }
        .navigationTitle(presentedPlaylist?.title ?? "")
        #endif
    }

    private var playlistButtonsPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .navigationBarTrailing
        #else
            .automatic
        #endif
    }

    private var playButton: some View {
        Button {
            player.play(videos)
        } label: {
            Label("Play All", systemImage: "play")
        }
        .contextMenu {
            Button {
                player.play(videos, shuffling: true)
            } label: {
                Label("Shuffle All", systemImage: "shuffle")
            }
        }
    }

    private var videos: [Video] {
        items.compactMap(\.video)
    }

    private var contentItem: ContentItem {
        ContentItem(playlist: playlist)
    }
}

struct ChannelPlaylistView_Previews: PreviewProvider {
    static var previews: some View {
        ChannelPlaylistView(playlist: ChannelPlaylist.fixture)
            .injectFixtureEnvironmentObjects()
    }
}
