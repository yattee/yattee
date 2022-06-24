import CoreData
import CoreMedia
import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    let video: Video

    @Environment(\.inChannelView) private var inChannelView
    @Environment(\.inChannelPlaylistView) private var inChannelPlaylistView
    @Environment(\.navigationStyle) private var navigationStyle
    @Environment(\.currentPlaylistID) private var playlistID

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @FetchRequest private var watchRequest: FetchedResults<Watch>

    @Default(.saveHistory) private var saveHistory

    private var viewContext: NSManagedObjectContext = PersistenceController.shared.container.viewContext

    init(video: Video) {
        self.video = video
        _watchRequest = video.watchFetchRequest
    }

    var body: some View {
        if video.videoID != Video.fixtureID {
            contextMenu
        }
    }

    @ViewBuilder var contextMenu: some View {
        if saveHistory {
            Section {
                if let watchedAtString = watchedAtString {
                    Text(watchedAtString)
                }

                if !watch.isNil, !watch!.finished, !watchingNow {
                    continueButton
                }

                if !watch.isNil, !watchingNow {
                    removeFromHistoryButton
                }
            }
        }

        Section {
            playNowButton
            #if os(iOS)
                playNowInPictureInPictureButton
            #endif
            #if !os(tvOS)
                playNowInMusicMode
            #endif
        }

        Section {
            playNextButton
            addToQueueButton
        }

        if accounts.app.supportsUserPlaylists, accounts.signedIn {
            Section {
                addToPlaylistButton
                addToLastPlaylistButton

                if let id = navigation.tabSelection?.playlistID ?? playlistID {
                    removeFromPlaylistButton(playlistID: id)
                }
            }
        }

        if !inChannelView, !inChannelPlaylistView {
            Section {
                openChannelButton

                if accounts.app.supportsSubscriptions, accounts.api.signedIn {
                    subscriptionButton
                }
            }
        }

        #if os(tvOS)
            Button("Cancel", role: .cancel) {}
        #endif
    }

    private var watch: Watch? {
        watchRequest.first
    }

    private var watchingNow: Bool {
        player.currentVideo == video
    }

    private var watchedAtString: String? {
        if watchingNow {
            return "Watching now"
        }

        if let watch = watch, let watchedAtString = watch.watchedAtString {
            return "Watched \(watchedAtString)"
        }

        return nil
    }

    private var continueButton: some View {
        Button {
            player.play(video, at: .secondsInDefaultTimescale(watch!.stoppedAt))
        } label: {
            Label("Continue from \(watch!.stoppedAt.formattedAsPlaybackTime(allowZero: true) ?? "where I left off")", systemImage: "playpause")
        }
    }

    var removeFromHistoryButton: some View {
        Button {
            guard let watch = watch else {
                return
            }

            player.removeWatch(watch)
        } label: {
            Label("Remove from history", systemImage: "delete.left.fill")
        }
    }

    private var playNowButton: some View {
        Button {
            if player.musicMode {
                player.toggleMusicMode()
            }

            player.play(video)
        } label: {
            Label("Play Now", systemImage: "play")
        }
    }

    private var playNowInPictureInPictureButton: some View {
        Button {
            player.controls.startPiP(startImmediately: false)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                player.play(video, at: watch?.timeToRestart, showingPlayer: false)
            }
        } label: {
            Label("Play in PiP", systemImage: "pip")
        }
    }

    private var playNowInMusicMode: some View {
        Button {
            if !player.musicMode {
                player.toggleMusicMode()
            }

            player.play(video, at: watch?.timeToRestart, showingPlayer: false)
        } label: {
            Label("Play Music", systemImage: "music.note")
        }
    }

    private var playNextButton: some View {
        Button {
            player.playNext(video)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }
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
            NavigationModel.openChannel(
                video.channel,
                player: player,
                recents: recents,
                navigation: navigation
            )
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
                        navigation.presentUnsubscribeAlert(video.channel, subscriptions: subscriptions)
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
            Label("Add to Playlist...", systemImage: "text.badge.plus")
        }
    }

    @ViewBuilder private var addToLastPlaylistButton: some View {
        if let playlist = playlists.lastUsed {
            Button {
                playlists.addVideo(playlistID: playlist.id, videoID: video.videoID, navigation: navigation)
            } label: {
                Label("Add to \(playlist.title)", systemImage: "text.badge.star")
            }
        }
    }

    func removeFromPlaylistButton(playlistID: String) -> some View {
        Button {
            playlists.removeVideo(index: video.indexID!, playlistID: playlistID)
        } label: {
            Label("Remove from Playlist", systemImage: "text.badge.minus")
        }
    }
}
