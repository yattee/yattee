import SwiftUI

struct ContentView: View {
    @StateObject private var navigationState = NavigationState()
    @StateObject private var playbackState = PlaybackState()
    @StateObject private var searchState = SearchState()
    @StateObject private var subscriptions = Subscriptions()

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
        #if !os(tvOS)
            .sheet(isPresented: $navigationState.showingVideo) {
                if let video = navigationState.video {
                    VideoPlayerView(video)

                    #if !os(iOS)
                        .frame(minWidth: 550, minHeight: 720)
                        .onExitCommand {
                            navigationState.showingVideo = false
                        }
                    #endif
                }
            }
        #endif
        .environmentObject(navigationState)
            .environmentObject(playbackState)
            .environmentObject(searchState)
            .environmentObject(subscriptions)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
