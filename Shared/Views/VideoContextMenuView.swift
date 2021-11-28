import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    let video: Video

    @Binding var playerNavigationLinkActive: Bool

    @Environment(\.inNavigationView) private var inNavigationView
    @Environment(\.inChannelView) private var inChannelView
    @Environment(\.navigationStyle) private var navigationStyle
    @Environment(\.currentPlaylistID) private var playlistID

    @EnvironmentObject<AccountsModel> private var accounts
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

        if !inChannelView {
            Section {
                openChannelButton

                if accounts.app.supportsSubscriptions {
                    subscriptionButton
                }
            }
        }

        if accounts.app.supportsUserPlaylists {
            Section {
                addToPlaylistButton

                if let id = navigation.tabSelection?.playlistID ?? playlistID {
                    removeFromPlaylistButton(playlistID: id)
                }
            }
        }

        #if os(tvOS)
            Button("Cancel", role: .cancel) {}
        #endif
    }

    private var playNowButton: some View {
        Button {
            player.playNow(video)

            guard !player.playingInPictureInPicture else {
                return
            }

            if inNavigationView {
                playerNavigationLinkActive = true
            } else {
                player.presentPlayer()
            }
        } label: {
            Label("Play Now", systemImage: "play")
        }
    }

    private var playNextButton: some View {
        Button {
            player.playNext(video)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }
    }

    private var isShowingChannelButton: Bool {
        if case .channel = navigation.tabSelection {
            return false
        }

        return !inChannelView
    }

    private var addToQueueButton: some View {
        Button {
            player.enqueueVideo(video)
        } label: {
            Label("Play Last", systemImage: "text.append")
        }
    }

    private var openChannelButton: some View {
        Button {
            let recent = RecentItem(from: video.channel)
            recents.add(recent)
            navigation.presentingChannel = true

            if navigationStyle == .sidebar {
                navigation.sidebarSectionChanged.toggle()
                navigation.tabSelection = .recentlyOpened(recent.tag)
            }
        } label: {
            Label("\(video.author) Channel", systemImage: "rectangle.stack.fill.badge.person.crop")
        }
    }

    private var subscriptionButton: some View {
        Group {
            if subscriptions.isSubscribing(video.channel.id) {
                Button {
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

    private var addToPlaylistButton: some View {
        Button {
            navigation.presentAddToPlaylist(video)
        } label: {
            Label("Add to playlist...", systemImage: "text.badge.plus")
        }
    }

    func removeFromPlaylistButton(playlistID: String) -> some View {
        Button {
            playlists.removeVideo(videoIndexID: video.indexID!, playlistID: playlistID)
        } label: {
            Label("Remove from playlist", systemImage: "text.badge.minus")
        }
    }
}
