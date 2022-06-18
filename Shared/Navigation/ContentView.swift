import AVFAudio
import Defaults
import MediaPlayer
import SDWebImage
import SDWebImagePINPlugin
import SDWebImageWebPCoder
import Siesta
import SwiftUI

struct ContentView: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<InstancesModel> private var instances
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<NetworkStateModel> private var networkState
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlayerControlsModel> private var playerControls
    @EnvironmentObject<PlayerTimeModel> private var playerTime
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search
    @EnvironmentObject<SubscriptionsModel> private var subscriptions
    @EnvironmentObject<ThumbnailsModel> private var thumbnailsModel

    @EnvironmentObject<MenuModel> private var menu

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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
        .onChange(of: accounts.signedIn) { _ in
            subscriptions.load(force: true)
            playlists.load(force: true)
        }

        .environmentObject(accounts)
        .environmentObject(comments)
        .environmentObject(instances)
        .environmentObject(navigation)
        .environmentObject(networkState)
        .environmentObject(player)
        .environmentObject(playerTime)
        .environmentObject(playlists)
        .environmentObject(recents)
        .environmentObject(search)
        .environmentObject(subscriptions)
        .environmentObject(thumbnailsModel)

        #if os(iOS)
            .overlay(videoPlayer)
        #endif

            // iOS 14 has problem with multiple sheets in one view
            // but it's ok when it's in background
            .background(
                EmptyView().sheet(isPresented: $navigation.presentingWelcomeScreen) {
                    WelcomeScreen()
                        .environmentObject(accounts)
                        .environmentObject(navigation)
                }
            )
        #if !os(tvOS)
            .onOpenURL { OpenURLHandler(accounts: accounts, player: player).handle($0) }
            .background(
                EmptyView().sheet(isPresented: $navigation.presentingAddToPlaylist) {
                    AddToPlaylistView(video: navigation.videoToAddToPlaylist)
                        .environmentObject(playlists)
                }
            )
            .background(
                EmptyView().sheet(isPresented: $navigation.presentingPlaylistForm) {
                    PlaylistFormView(playlist: $navigation.editedPlaylist)
                        .environmentObject(accounts)
                        .environmentObject(playlists)
                }
            )
            .background(
                EmptyView().sheet(isPresented: $navigation.presentingSettings, onDismiss: openWelcomeScreenIfAccountEmpty) {
                    SettingsView()
                        .environmentObject(accounts)
                        .environmentObject(instances)
                        .environmentObject(player)
                }
            )
        #endif
            .alert(isPresented: $navigation.presentingUnsubscribeAlert) {
                Alert(
                    title: Text(
                        "Are you sure you want to unsubscribe from \(navigation.channelToUnsubscribe.name)?"
                    ),
                    primaryButton: .destructive(Text("Unsubscribe")) {
                        subscriptions.unsubscribe(navigation.channelToUnsubscribe.id)
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(isPresented: $navigation.presentingAlert) {
                Alert(title: Text(navigation.alertTitle), message: Text(navigation.alertMessage))
            }
    }

    func openWelcomeScreenIfAccountEmpty() {
        guard Defaults[.instances].isEmpty else {
            return
        }

        navigation.presentingWelcomeScreen = true
    }

    var videoPlayer: some View {
        VideoPlayerView()
            .environmentObject(accounts)
            .environmentObject(comments)
            .environmentObject(instances)
            .environmentObject(navigation)
            .environmentObject(player)
            .environmentObject(playerControls)
            .environmentObject(playlists)
            .environmentObject(recents)
            .environmentObject(subscriptions)
            .environmentObject(thumbnailsModel)
            .environment(\.navigationStyle, .sidebar)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .injectFixtureEnvironmentObjects()
    }
}
