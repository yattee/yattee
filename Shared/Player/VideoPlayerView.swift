import AVKit
import Defaults
import Siesta
import SwiftUI
#if !os(tvOS)
    import SwiftUIKit
#endif

struct VideoPlayerView: View {
    static let defaultAspectRatio: Double = 1.77777778
    static var defaultMinimumHeightLeft: Double {
        #if os(macOS)
            300
        #else
            200
        #endif
    }

    @State private var playerSize: CGSize = .zero
    @State private var fullScreen = false

    #if os(iOS)
        @Environment(\.dismiss) private var dismiss
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        #if os(macOS)
            HSplitView {
                content
            }
            .frame(idealWidth: 1000, maxWidth: 1100, minHeight: 700)
        #else
            HStack(spacing: 0) {
                content
            }
            #if os(iOS)
                .navigationBarHidden(true)
            #endif
        #endif
    }

    var content: some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                #if os(tvOS)
                    player()
                #else
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            #if os(iOS)
                                if verticalSizeClass == .regular {
                                    PlaybackBar()
                                }
                            #elseif os(macOS)
                                PlaybackBar()
                            #endif

                            if player.currentItem.isNil {
                                playerPlaceholder(geometry: geometry)
                            } else {
                                player(geometry: geometry)
                            }
                        }
                        #if os(iOS)
                            .onSwipeGesture(
                                up: {
                                    withAnimation {
                                        fullScreen = true
                                    }
                                },
                                down: { dismiss() }
                            )
                        #endif

                        .background(.black)
                            .onAppear {
                                self.playerSize = geometry.size
                            }
                            .onChange(of: geometry.size) { size in
                                self.playerSize = size
                            }

                        Group {
                            #if os(iOS)
                                if verticalSizeClass == .regular {
                                    VideoDetails(sidebarQueue: sidebarQueueBinding, fullScreen: $fullScreen)
                                }

                            #else
                                VideoDetails(fullScreen: $fullScreen)
                            #endif
                        }
                        .background()
                        .modifier(VideoDetailsPaddingModifier(geometry: geometry, fullScreen: fullScreen))
                    }
                #endif
            }
            #if os(macOS)
                .frame(minWidth: 650)
            #endif
            #if os(iOS)
                if sidebarQueue {
                    PlayerQueueView(fullScreen: $fullScreen)
                        .frame(maxWidth: 350)
                }
            #elseif os(macOS)
                PlayerQueueView(fullScreen: $fullScreen)
                    .frame(minWidth: 250)
            #endif
        }
    }

    func playerPlaceholder(geometry: GeometryProxy) -> some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    #if !os(tvOS)
                        Image(systemName: "ticket")
                            .font(.system(size: 80))
                        Text("What are we watching next?")
                    #endif
                }
                Spacer()
            }
            .foregroundColor(.gray)
            Spacer()
        }
        .contentShape(Rectangle())
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: geometry.size.width / VideoPlayerView.defaultAspectRatio)
    }

    func player(geometry: GeometryProxy? = nil) -> some View {
        Player()
        #if !os(tvOS)
            .modifier(VideoPlayerSizeModifier(geometry: geometry))
        #endif
    }

    #if os(iOS)
        var sidebarQueue: Bool {
            horizontalSizeClass == .regular && playerSize.width > 750
        }

        var sidebarQueueBinding: Binding<Bool> {
            Binding(
                get: { self.sidebarQueue },
                set: { _ in }
            )
        }
    #endif
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView()
            .injectFixtureEnvironmentObjects()

        VideoPlayerView()
            .injectFixtureEnvironmentObjects()
            .previewInterfaceOrientation(.landscapeRight)
    }
}
