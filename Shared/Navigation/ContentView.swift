import AVFAudio
import Defaults
import MediaPlayer
import SDWebImage
import SDWebImagePINPlugin
import SDWebImageWebPCoder
import Siesta
import SwiftUI

struct ContentView: View {
    @ObservedObject private var navigation = NavigationModel.shared
    @ObservedObject private var player = PlayerModel.shared

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Default(.avPlayerUsesSystemControls) private var avPlayerUsesSystemControls

    var body: some View {
        GeometryReader { proxy in
            Group {
                #if os(iOS)
                    Group {
                        if Constants.isIPhone {
                            AppTabNavigation()
                        } else {
                            if horizontalSizeClass == .compact {
                                AppTabNavigation()
                            } else {
                                AppSidebarNavigation()
                            }
                        }
                    }
                #elseif os(macOS)
                    AppSidebarNavigation()
                #elseif os(tvOS)
                    TVNavigationView()
                #endif
            }
            #if !os(macOS)
            .onAppear {
                SafeAreaModel.shared.safeArea = proxy.safeAreaInsets
            }
            .onChange(of: proxy.safeAreaInsets) { newValue in
                SafeAreaModel.shared.safeArea = newValue
            }
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
        .modifier(ImportSettingsSheetViewModifier(isPresented: $navigation.presentingSettingsImportSheet, settingsFile: $navigation.settingsImportURL))
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingAccounts) {
                AccountsView()
            }
        )
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingHomeSettings) {
                #if os(macOS)
                    VStack(alignment: .leading) {
                        Button("Done") {
                            navigation.presentingHomeSettings = false
                        }
                        .padding()
                        .keyboardShortcut(.cancelAction)

                        HomeSettings()
                    }
                    .frame(width: 500, height: 800)
                #else
                    NavigationView {
                        HomeSettings()
                        #if os(iOS)
                            .toolbar {
                                ToolbarItem(placement: .navigation) {
                                    Button {
                                        navigation.presentingHomeSettings = false
                                    } label: {
                                        Text("Done")
                                    }
                                }
                            }
                        #endif
                    }
                #endif
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
        #if os(iOS)
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingPlaybackSettings) {
                PlaybackSettings()
            }
        )
        #endif
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingOpenVideos) {
                OpenVideosView()
            }
        )
        #if !os(macOS)
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingChannelSheet) {
                NavigationView {
                    ChannelVideosView(channel: navigation.channelPresentedInSheet, showCloseButton: true)
                }
            }
        )
        #endif
        .alert(isPresented: $navigation.presentingAlert) { navigation.alert }
        #if os(iOS)
            .statusBarHidden(player.playingFullScreen)
        #endif
        #if os(macOS)
        .frame(minWidth: 1200, minHeight: 600)
        #endif
    }

    @ViewBuilder var videoPlayer: some View {
        if player.presentingPlayer {
            playerView
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                .zIndex(3)
        } else if player.activeBackend == .appleAVPlayer,
                  avPlayerUsesSystemControls || player.avPlayerBackend.isStartingPiP
        {
            #if os(iOS)
                AppleAVPlayerLayerView().offset(y: UIScreen.main.bounds.height)
            #endif
        }
    }

    var playerView: some View {
        VideoPlayerView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .injectFixtureEnvironmentObjects()
    }
}
