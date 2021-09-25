import AVKit
import Siesta
import SwiftUI

struct VideoPlayerView: View {
    static let defaultAspectRatio: Double = 1.77777778
    static var defaultMinimumHeightLeft: Double {
        #if os(macOS)
            300
        #else
            200
        #endif
    }

    @StateObject private var store = Store<Video>()

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlaybackModel> private var playback

    var resource: Resource {
        api.video(video.id)
    }

    var video: Video

    init(_ video: Video) {
        self.video = video
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
                Player(video: video)
                    .environmentObject(playback)
            #else
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        #if os(iOS)
                            if verticalSizeClass == .regular {
                                PlaybackBar(video: video)
                            }
                        #elseif os(macOS)
                            PlaybackBar(video: video)
                        #endif

                        Player(video: video)
                            .environmentObject(playback)
                            .modifier(VideoPlayerSizeModifier(geometry: geometry, aspectRatio: playback.aspectRatio))
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
                    .modifier(VideoDetailsPaddingModifier(geometry: geometry, aspectRatio: playback.aspectRatio))
                }
                .animation(.linear(duration: 0.2), value: playback.aspectRatio)
            #endif
        }
        .onAppear {
            resource.addObserver(store)
            resource.loadIfNeeded()
        }
        .onDisappear {
            resource.removeObservers(ownedBy: store)
            resource.invalidate()
        }
        #if os(macOS)
            .frame(maxWidth: 1000, minHeight: 700)
        #elseif os(iOS)
            .navigationBarHidden(true)
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
                .environmentObject(NavigationModel())
        }
    }
}
