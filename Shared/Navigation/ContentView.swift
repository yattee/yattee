import AVFAudio
import Defaults
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
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlaylistsModel> private var playlists
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search
    @EnvironmentObject<SubscriptionsModel> private var subscriptions
    @EnvironmentObject<ThumbnailsModel> private var thumbnailsModel

    @EnvironmentObject<MenuModel> private var menu

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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
        .onAppear(perform: configure)
        .onChange(of: accounts.signedIn) { _ in
            subscriptions.load(force: true)
            playlists.load(force: true)
        }

        .environmentObject(accounts)
        .environmentObject(comments)
        .environmentObject(instances)
        .environmentObject(navigation)
        .environmentObject(player)
        .environmentObject(playlists)
        .environmentObject(recents)
        .environmentObject(search)
        .environmentObject(subscriptions)
        .environmentObject(thumbnailsModel)

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
    }

    func configure() {
        SiestaLog.Category.enabled = .common
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
        SDWebImageManager.defaultImageCache = PINCache(name: "stream.yattee.app")
        #if !os(macOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif

        #if os(iOS)
            if Defaults[.lockPortraitWhenBrowsing] {
                Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
            }
        #endif

        if let account = accounts.lastUsed ??
            instances.lastUsed?.anonymousAccount ??
            InstancesModel.all.first?.anonymousAccount
        {
            accounts.setCurrent(account)
        }

        if accounts.current.isNil {
            navigation.presentingWelcomeScreen = true
        }

        playlists.accounts = accounts
        search.accounts = accounts
        subscriptions.accounts = accounts

        comments.player = player

        menu.accounts = accounts
        menu.navigation = navigation
        menu.player = player

        player.accounts = accounts
        player.comments = comments

        if !accounts.current.isNil {
            player.restoreQueue()
        }

        if !Defaults[.saveRecents] {
            recents.clear()
        }

        var section = Defaults[.visibleSections].min()?.tabSelection

        #if os(macOS)
            if section == .playlists {
                section = .search
            }
        #endif

        navigation.tabSelection = section ?? .search

        subscriptions.load()
        playlists.load()
    }

    func openWelcomeScreenIfAccountEmpty() {
        guard Defaults[.instances].isEmpty else {
            return
        }

        navigation.presentingWelcomeScreen = true
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .injectFixtureEnvironmentObjects()
    }
}
