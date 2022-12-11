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

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var player = PlayerModel.shared
    @ObservedObject private var playlists = PlaylistsModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared

    @FetchRequest private var watchRequest: FetchedResults<Watch>

    @Default(.saveHistory) private var saveHistory

    private var backgroundContext = PersistenceController.shared.container.newBackgroundContext()
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
        if !video.localStreamIsDirectory {
            if saveHistory {
                Section {
                    if let watchedAtString {
                        Text(watchedAtString)
                    }

                    if !watch.isNil, !watch!.finished, !watchingNow {
                        continueButton
                    }

                    if !(watch?.finished ?? false) {
                        markAsWatchedButton
                    }

                    if !watch.isNil, !watchingNow {
                        removeFromHistoryButton
                    }
                }
            }

            Section {
                playNowButton
                #if !os(tvOS)
                    playNowInPictureInPictureButton
                    playNowInMusicMode
                #endif
            }

            Section {
                playNextButton
                addToQueueButton
            }

            if accounts.app.supportsUserPlaylists, accounts.signedIn, !video.isLocal {
                Section {
                    addToPlaylistButton
                    addToLastPlaylistButton

                    if let id = navigation.tabSelection?.playlistID ?? playlistID {
                        removeFromPlaylistButton(playlistID: id)
                    }
                }
            }

            #if !os(tvOS)
                Section {
                    ShareButton(contentItem: .init(video: video))
                }
            #endif
        }

        #if os(iOS)
            if video.isLocal,
               let url = video.localStream?.localURL,
               DocumentsModel.shared.isDocument(url)
            {
                Section {
                    removeDocumentButton
                }
            }
        #endif

        if !inChannelView, !inChannelPlaylistView, !video.isLocal {
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
            return "Watching now".localized()
        }

        if let watch, let watchedAtString = watch.watchedAtString {
            if watchedAtString == "in 0 seconds" {
                return "Just watched".localized()
            }
            let localizedWatchedString = "Watched %@".localized()
            return String(format: localizedWatchedString, watchedAtString)
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

    var markAsWatchedButton: some View {
        Button {
            Watch.markAsWatched(videoID: video.videoID, account: accounts.current, duration: video.length, context: backgroundContext)
        } label: {
            Label("Mark as watched", systemImage: "checkmark.circle.fill")
        }
    }

    var removeFromHistoryButton: some View {
        Button {
            guard let watch else {
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
            player.avPlayerBackend.startPictureInPictureOnPlay = true

            #if !os(macOS)
                player.exitFullScreen()
            #endif

            if player.activeBackend != PlayerBackendType.appleAVPlayer {
                player.changeActiveBackend(from: .mpv, to: .appleAVPlayer)
            }
            player.hide()

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

    #if os(iOS)
        @ViewBuilder private var removeDocumentButton: some View {
            let action = {
                if let url = video.localStream?.localURL {
                    NavigationModel.shared.presentAlert(
                        Alert(
                            title: Text("Are you sure you want to remove this document?"),
                            message: Text(String(format: "\"%@\" will be irreversibly removed from this device.", video.displayTitle)),
                            primaryButton: .destructive(Text("Remove")) {
                                do {
                                    try DocumentsModel.shared.removeDocument(url)
                                } catch {
                                    NavigationModel.shared.presentAlert(title: "Could not delete document", message: error.localizedDescription)
                                }
                            },
                            secondaryButton: .cancel()
                        )
                    )
                }
            }
            let label = Label("Remove…", systemImage: "trash.fill")
                .foregroundColor(Color("AppRedColor"))

            if #available(iOS 15, macOS 12, *) {
                Button(role: .destructive, action: action) { label }
            } else {
                Button(action: action) { label }
            }
        }
    #endif

    private var openChannelButton: some View {
        Button {
            NavigationModel.shared.openChannel(
                video.channel,
                navigationStyle: navigationStyle
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
                playlists.addVideo(playlistID: playlist.id, videoID: video.videoID)
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
