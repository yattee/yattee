import AVKit
import Defaults
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
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    content
                }
                .onAppear {
                    self.playerSize = geometry.size
                }
                .onChange(of: geometry.size) { size in
                    self.playerSize = size
                }
                .navigationBarHidden(true)
            }
        #endif
    }

    var content: some View {
        Group {
            Group {
                #if os(tvOS)
                    player.playerView
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
                                #if os(macOS)
                                    Player()
                                        .modifier(VideoPlayerSizeModifier(geometry: geometry, aspectRatio: player.controller?.aspectRatio))

                                #else
                                    player.playerView
                                        .modifier(VideoPlayerSizeModifier(geometry: geometry, aspectRatio: player.controller?.aspectRatio))
                                #endif
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

                        Group {
                            #if os(iOS)
                                if verticalSizeClass == .regular {
                                    VideoDetails(sidebarQueue: sidebarQueueBinding, fullScreen: $fullScreen)
                                }

                            #else
                                VideoDetails(sidebarQueue: sidebarQueueBinding, fullScreen: $fullScreen)
                            #endif
                        }
                        .background()
                        .modifier(VideoDetailsPaddingModifier(geometry: geometry, aspectRatio: player.controller?.aspectRatio, fullScreen: fullScreen))
                    }
                #endif
            }
            #if os(macOS)
                .frame(minWidth: 650)
            #endif
            #if os(iOS)
                if sidebarQueue {
                    PlayerQueueView(sidebarQueue: .constant(true), fullScreen: $fullScreen)
                        .frame(maxWidth: 350)
                }
            #elseif os(macOS)
                if Defaults[.playerSidebar] != .never {
                    PlayerQueueView(sidebarQueue: sidebarQueueBinding, fullScreen: $fullScreen)
                        .frame(minWidth: 250)
                }
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
                            .font(.system(size: 120))
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

    var sidebarQueue: Bool {
        switch Defaults[.playerSidebar] {
        case .never:
            return false
        case .always:
            return true
        case .whenFits:
            return playerSize.width > 900
        }
    }

    var sidebarQueueBinding: Binding<Bool> {
        Binding(
            get: { sidebarQueue },
            set: { _ in }
        )
    }
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView()
            .injectFixtureEnvironmentObjects()
    }
}
