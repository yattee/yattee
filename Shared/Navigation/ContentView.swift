import Defaults
import SwiftUI

struct ContentView: View {
    @StateObject private var navigation = NavigationModel()
    @StateObject private var playback = PlaybackModel()
    @StateObject private var recents = RecentsModel()

    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<InstancesModel> private var instances
    @EnvironmentObject<PlaylistsModel> private var playlists

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Section {
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
        .environmentObject(navigation)
        .environmentObject(playback)
        .environmentObject(recents)
        #if !os(tvOS)
            .sheet(isPresented: $navigation.showingVideo) {
                if let video = navigation.video {
                    VideoPlayerView(video)
                        .environmentObject(playback)

                    #if !os(iOS)
                        .frame(minWidth: 550, minHeight: 720)
                        .onExitCommand {
                            navigation.showingVideo = false
                        }
                    #endif
                }
            }
            .sheet(isPresented: $navigation.presentingAddToPlaylist) {
                AddToPlaylistView(video: navigation.videoToAddToPlaylist)
            }
            .sheet(isPresented: $navigation.presentingPlaylistForm) {
                PlaylistFormView(playlist: $navigation.editedPlaylist)
            }
            .sheet(isPresented: $navigation.presentingSettings) {
                SettingsView()
            }
        #endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
