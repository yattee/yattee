import AVFAudio
import Defaults
import MediaPlayer
import SDWebImage
import SDWebImagePINPlugin
import SDWebImageWebPCoder
import Siesta
import SwiftUI

struct ContentView: View {
    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var player = PlayerModel.shared
    private var playlists = PlaylistsModel.shared
    private var subscriptions = SubscribedChannelsModel.shared

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var playerControls: PlayerControlsModel { .shared }

    let persistenceController = PersistenceController.shared

    var body: some View {
        Group {
            #if os(iOS)
                if horizontalSizeClass == .compact {
                    AppTabNavigation()
                } else {
                    AppSidebarNavigation()
                }
            #elseif os(macOS)
                AppSidebarNavigation()
            #elseif os(tvOS)
                TVNavigationView()
            #endif
        }
        #if os(iOS)
        .overlay(videoPlayer)
        .sheet(isPresented: $navigation.presentingShareSheet) {
            if let shareURL = navigation.shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
        #endif

        // iOS 14 has problem with multiple sheets in one view
        // but it's ok when it's in background
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingWelcomeScreen) {
                WelcomeScreen()
            }
        )
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingSettings) {
                SettingsView()
            }
        )
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingAccounts) {
                AccountsView()
            }
        )
        #if !os(tvOS)
        .fileImporter(
            isPresented: $navigation.presentingFileImporter,
            allowedContentTypes: [.audiovisualContent],
            allowsMultipleSelection: true
        ) { result in
            do {
                let selectedFiles = try result.get()
                let urlsToOpen = selectedFiles.map { url in
                    if let bookmarkURL = URLBookmarkModel.shared.loadBookmark(url) {
                        return bookmarkURL
                    }

                    if url.startAccessingSecurityScopedResource() {
                        URLBookmarkModel.shared.saveBookmark(url)
                    }

                    return url
                }

                OpenVideosModel.shared.openURLs(urlsToOpen)
            } catch {
                NavigationModel.shared.presentAlert(title: "Could not open Files")
            }

            NavigationModel.shared.presentingOpenVideos = false
        }
        .onOpenURL { url in
            URLBookmarkModel.shared.saveBookmark(url)
            OpenURLHandler.shared.handle(url)
        }
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingAddToPlaylist) {
                AddToPlaylistView(video: navigation.videoToAddToPlaylist)
            }
        )
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingPlaylistForm) {
                PlaylistFormView(playlist: $navigation.editedPlaylist)
            }
        )
        #endif
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingOpenVideos) {
                OpenVideosView()
            }
        )
        .alert(isPresented: $navigation.presentingAlert) { navigation.alert }
    }

    var navigationStyle: NavigationStyle {
        #if os(iOS)
            return horizontalSizeClass == .compact ? .tab : .sidebar
        #elseif os(tvOS)
            return .tab
        #else
            return .sidebar
        #endif
    }

    @ViewBuilder var videoPlayer: some View {
        if player.presentingPlayer {
            playerView
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                .zIndex(3)
        } else if player.activeBackend == .appleAVPlayer {
            #if os(iOS)
                playerView.offset(y: UIScreen.main.bounds.height)
            #endif
        }
    }

    var playerView: some View {
        VideoPlayerView()
            .environment(\.navigationStyle, navigationStyle)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .injectFixtureEnvironmentObjects()
    }
}
