import CoreData
import CoreMedia
import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    let video: Video

    @Environment(\.inChannelView) private var inChannelView
    @Environment(\.inChannelPlaylistView) private var inChannelPlaylistView
    @Environment(\.inQueueListing) private var inQueueListing
    @Environment(\.navigationStyle) private var navigationStyle
    @Environment(\.currentPlaylistID) private var playlistID

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var player = PlayerModel.shared
    @ObservedObject private var playlists = PlaylistsModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared

    @FetchRequest private var watchRequest: FetchedResults<Watch>

    @Default(.showPlayNowInBackendContextMenu) private var showPlayNowInBackendContextMenu

    private var backgroundContext = PersistenceController.shared.container.newBackgroundContext()

    @State private var isOverlayVisible = false

    init(video: Video) {
        self.video = video
        _watchRequest = video.watchFetchRequest
    }

    var body: some View {
        ZStack {
            // Conditional overlay to block taps on underlying views
            if isOverlayVisible {
                Color.clear
                    .contentShape(Rectangle())
                #if !os(tvOS)
                    // This is not available on tvOS < 16 so we leave out.
                    // TODO: remove #if when setting the minimum deployment target to >= 16
                    .onTapGesture {
                        // Dismiss overlay without triggering other interactions
                        isOverlayVisible = false
                    }
                #endif
                    .ignoresSafeArea() // Ensure overlay covers the entire screen
                    .accessibilityLabel("Dismiss context menu")
                    .accessibilityHint("Tap to close the context")
                    .accessibilityAddTraits(.isButton)
            }

            if video.videoID != Video.fixtureID {
                contextMenu
                    .onAppear {
                        isOverlayVisible = true
                    }
                    .onDisappear {
                        isOverlayVisible = false
                    }
            }
        }
    }

    @ViewBuilder var contextMenu: some View {
        if inQueueListing {
            if let item = player.queue.first(where: { $0.videoID == video.videoID }) {
                removeFromQueueButton(item)
            }
            removeAllFromQueueButton()
        }
        if !video.localStreamIsDirectory {
            if Defaults[.saveHistory] {
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

            if Defaults[.showPlayNowInBackendContextMenu] {
                Section {
                    ForEach(PlayerBackendType.allCases, id: \.self) { backend in
                        playNowInBackendButton(backend)
                    }
                }
            }

            Section {
                playNextButton
                addToQueueButton
            }

            if accounts.app.supportsUserPlaylists, accounts.signedIn, !video.isLocal {
                Section {
                    #if os(tvOS)
                        addToPlaylistButton
                    #else
                        addToPlaylistMenu
                    #endif
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
            FeedModel.shared.calculateUnwatchedFeed()
            WatchModel.shared.watchesChanged()
        } label: {
            Label("Mark as watched", systemImage: "checkmark.circle.fill")
        }
    }

    var removeFromHistoryButton: some View {
        Button {
            guard let watch else { return }
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

    private func playNowInBackendButton(_ backend: PlayerBackendType) -> some View {
        Button {
            if player.musicMode {
                player.toggleMusicMode()
            }

            player.forceBackendOnPlay = backend

            player.play(video)
        } label: {
            Label("Play Now in \(backend.label)", systemImage: "play")
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

    #if !os(tvOS)
        @ViewBuilder private var addToPlaylistMenu: some View {
            if playlists.playlists.isEmpty {
                Text("No Playlists")
            } else {
                Menu {
                    ForEach(playlists.editable) { playlist in
                        Button {
                            playlists.addVideo(playlistID: playlist.id, videoID: video.videoID)
                        } label: {
                            Text(playlist.title).tag(playlist.id)
                        }
                    }
                } label: {
                    Label("Add to Playlist...", systemImage: "text.badge.plus")
                }
            }
        }
    #endif

    func removeFromPlaylistButton(playlistID: String) -> some View {
        Button {
            playlists.removeVideo(index: video.indexID!, playlistID: playlistID)
        } label: {
            Label("Remove from Playlist", systemImage: "text.badge.minus")
        }
    }

    private func removeFromQueueButton(_ item: PlayerQueueItem) -> some View {
        Button {
            player.remove(item)
        } label: {
            Label("Remove from the queue", systemImage: "trash")
        }
    }

    private func removeAllFromQueueButton() -> some View {
        Button {
            player.removeQueueItems()
        } label: {
            Label("Clear the queue", systemImage: "trash.fill")
        }
    }
}
