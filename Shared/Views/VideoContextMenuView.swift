import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    @EnvironmentObject<NavigationState> private var navigationState
    @EnvironmentObject<Subscriptions> private var subscriptions

    let video: Video

    @Default(.showingAddToPlaylist) var showingAddToPlaylist
    @Default(.videoIDToAddToPlaylist) var videoIDToAddToPlaylist

    @State private var subscribed = false

    var body: some View {
        Section {
            if navigationState.showOpenChannel(video.channel.id) {
                openChannelButton
            }

            subscriptionButton
                .opacity(subscribed ? 1 : 1)

            openVideoDetailsButton

            if navigationState.tabSelection == .playlists {
                removeFromPlaylistButton
            } else {
                addToPlaylistButton
            }
        }
    }

    var openChannelButton: some View {
        Button("\(video.author) Channel") {
            navigationState.openChannel(video.channel)
            navigationState.sidebarSectionChanged.toggle()
        }
    }

    var subscriptionButton: some View {
        Group {
            if subscriptions.isSubscribing(video.channel.id) {
                Button("Unsubscribe", role: .destructive) {
                    #if os(tvOS)
                        subscriptions.unsubscribe(video.channel.id)
                    #else
                        navigationState.presentUnsubscribeAlert(video.channel)
                    #endif
                }
            } else {
                Button("Subscribe") {
                    subscriptions.subscribe(video.channel.id) {
                        navigationState.sidebarSectionChanged.toggle()
                    }
                }
            }
        }
    }

    var openVideoDetailsButton: some View {
        Button("Open video details") {
            navigationState.openVideoDetails(video)
        }
    }

    var addToPlaylistButton: some View {
        Button("Add to playlist...") {
            videoIDToAddToPlaylist = video.id
            showingAddToPlaylist = true
        }
    }

    var removeFromPlaylistButton: some View {
        Button("Remove from playlist", role: .destructive) {
            let resource = InvidiousAPI.shared.playlistVideo(Defaults[.selectedPlaylistID]!, video.indexID!)
            resource.request(.delete).onSuccess { _ in
                InvidiousAPI.shared.playlists.load()
            }
        }
    }
}
