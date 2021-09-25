import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    let video: Video

    @Default(.showingAddToPlaylist) var showingAddToPlaylist
    @Default(.videoIDToAddToPlaylist) var videoIDToAddToPlaylist

    var body: some View {
        Section {
            openChannelButton

            subscriptionButton

            if navigation.tabSelection == .playlists {
                removeFromPlaylistButton
            } else {
                addToPlaylistButton
            }
        }
    }

    var openChannelButton: some View {
        Button("\(video.author) Channel") {
            let recent = RecentItem(from: video.channel)
            recents.open(recent)
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
            videoIDToAddToPlaylist = video.id
            showingAddToPlaylist = true
        }
    }

    var removeFromPlaylistButton: some View {
        Button("Remove from playlist", role: .destructive) {
            let resource = api.playlistVideo(Defaults[.selectedPlaylistID]!, video.indexID!)
            resource.request(.delete).onSuccess { _ in
                api.playlists.load()
            }
        }
    }
}
