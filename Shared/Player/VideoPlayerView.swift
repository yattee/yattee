import AVKit
import Siesta
import SwiftUI

struct VideoPlayerView: View {
    static let defaultAspectRatio: CGFloat = 1.77777778
    static var defaultMinimumHeightLeft: CGFloat {
        #if os(macOS)
            300
        #else
            200
        #endif
    }

    @EnvironmentObject<NavigationState> private var navigationState

    @ObservedObject private var store = Store<Video>()

    @ObservedObject private var playbackState = PlaybackState()

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var resource: Resource {
        InvidiousAPI.shared.video(video.id)
    }

    var video: Video

    init(_ video: Video) {
        self.video = video
        resource.addObserver(store)
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
                Player(playbackState: playbackState, video: video)
            #else
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        #if os(iOS)
                            if verticalSizeClass == .regular {
                                PlaybackBar(playbackState: playbackState, video: video)
                            }
                        #elseif os(macOS)
                            PlaybackBar(playbackState: playbackState, video: video)
                        #endif

                        Player(playbackState: playbackState, video: video)
                            .modifier(VideoPlayerSizeModifier(geometry: geometry, aspectRatio: playbackState.aspectRatio))
                    }
                    .background(.black)

                    VStack(spacing: 0) {
                        #if os(iOS)
                            if verticalSizeClass == .regular {
                                ScrollView(.vertical, showsIndicators: showScrollIndicators) {
                                    if let video = store.item {
                                        VideoDetails(video: video)
                                    } else {
                                        VideoDetails(video: video)
                                    }
                                }
                            }
                        #else
                            if let video = store.item {
                                VideoDetails(video: video)
                            } else {
                                VideoDetails(video: video)
                            }
                        #endif
                    }
                    .modifier(VideoDetailsPaddingModifier(geometry: geometry, aspectRatio: playbackState.aspectRatio))
                }
                .animation(.linear(duration: 0.2), value: playbackState.aspectRatio)
            #endif
        }

        .onAppear {
            resource.loadIfNeeded()
        }
        .onDisappear {
            resource.removeObservers(ownedBy: store)
            resource.invalidate()

            navigationState.showingVideoDetails = navigationState.returnToDetails
        }
        #if os(macOS)
            .navigationTitle(video.title)
            .frame(maxWidth: 1000, minHeight: 700)
        #elseif os(iOS)
            .navigationBarTitle(video.title, displayMode: .inline)
        #endif
    }

    var showScrollIndicators: Bool {
        #if os(macOS)
            false
        #else
            true
        #endif
    }
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
        }
        .sheet(isPresented: .constant(true)) {
            VideoPlayerView(Video.fixture)
                .environmentObject(NavigationState())
        }
    }
}
