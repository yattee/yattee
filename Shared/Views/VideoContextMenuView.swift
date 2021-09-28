import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    let video: Video

    var body: some View {
        Section {
            openChannelButton

            subscriptionButton

            if case let .playlist(id) = navigation.tabSelection {
                removeFromPlaylistButton(playlistID: id)
            }

            if navigation.tabSelection == .playlists {
                removeFromPlaylistButton(playlistID: playlists.currentPlaylist!.id)
            } else {
                addToPlaylistButton
            }
        }
    }

    var openChannelButton: some View {
        Button("\(video.author) Channel") {
            let recent = RecentItem(from: video.channel)
            recents.add(recent)
            navigation.tabSelection = .recentlyOpened(recent.tag)
            navigation.isChannelOpen = true
            navigation.sidebarSectionChanged.toggle()
        }
    }

    var subscriptionButton: some View {
        Group {
            if subscriptions.isSubscribing(video.channel.id) {
                Button("Unsubscribe", role: .destructive) {
                    #if os(tvOS)
                        subscriptions.unsubscribe(video.channel.id)
                    #else
                        navigation.presentUnsubscribeAlert(video.channel)
                    #endif
                }
            } else {
                Button("Subscribe") {
                    subscriptions.subscribe(video.channel.id) {
                        navigation.sidebarSectionChanged.toggle()
                    }
                }
            }
        }
    }

    var addToPlaylistButton: some View {
        Button("Add to playlist...") {
            navigation.presentAddToPlaylist(video)
        }
    }

    func removeFromPlaylistButton(playlistID: String) -> some View {
        Button("Remove from playlist", role: .destructive) {
            playlists.removeVideoFromPlaylist(videoIndexID: video.indexID!, playlistID: playlistID)
        }
    }
}
