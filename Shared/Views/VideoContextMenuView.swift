import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    let video: Video

    @Binding var playerNavigationLinkActive: Bool

    @Environment(\.inNavigationView) private var inNavigationView

    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    var body: some View {
        Section {
            playNowButton
        }
        Section {
            playNextButton
            addToQueueButton
        }

        Section {
            openChannelButton
            subscriptionButton
        }

        Section {
            if navigation.tabSelection != .playlists {
                addToPlaylistButton
            } else if let playlist = playlists.currentPlaylist {
                removeFromPlaylistButton(playlistID: playlist.id)
            }

            if case let .playlist(id) = navigation.tabSelection {
                removeFromPlaylistButton(playlistID: id)
            }
        }
    }

    var playNowButton: some View {
        Button {
            player.playNow(video)

            if inNavigationView {
                playerNavigationLinkActive = true
            } else {
                player.presentPlayer()
            }
        } label: {
            Label("Play Now", systemImage: "play")
        }
    }

    var playNextButton: some View {
        Button {
            player.playNext(video)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }
    }

    var addToQueueButton: some View {
        Button {
            player.enqueueVideo(video)
        } label: {
            Label("Play Last", systemImage: "text.append")
        }
    }

    var openChannelButton: some View {
        Button {
            let recent = RecentItem(from: video.channel)
            recents.add(recent)
            navigation.isChannelOpen = true
            navigation.sidebarSectionChanged.toggle()
            navigation.tabSelection = .recentlyOpened(recent.tag)
        } label: {
            Label("\(video.author) Channel", systemImage: "rectangle.stack.fill.badge.person.crop")
        }
    }

    var subscriptionButton: some View {
        Group {
            if subscriptions.isSubscribing(video.channel.id) {
                Button(role: .destructive) {
                    #if os(tvOS)
                        subscriptions.unsubscribe(video.channel.id)
                    #else
                        navigation.presentUnsubscribeAlert(video.channel)
                    #endif
                } label: {
                    Label("Unsubscribe", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    subscriptions.subscribe(video.channel.id) {
                        navigation.sidebarSectionChanged.toggle()
                    }
                } label: {
                    Label("Subscribe", systemImage: "star.circle")
                }
            }
        }
    }

    var addToPlaylistButton: some View {
        Button {
            navigation.presentAddToPlaylist(video)
        } label: {
            Label("Add to playlist...", systemImage: "text.badge.plus")
        }
    }

    func removeFromPlaylistButton(playlistID: String) -> some View {
        Button(role: .destructive) {
            playlists.removeVideoFromPlaylist(videoIndexID: video.indexID!, playlistID: playlistID)
        } label: {
            Label("Remove from playlist", systemImage: "text.badge.minus")
        }
    }
}
