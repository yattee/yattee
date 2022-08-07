import SwiftUI

struct PlayerBackendView: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<ThumbnailsModel> private var thumbnails

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch player.activeBackend {
                case .mpv:
                    player.mpvPlayerView
                case .appleAVPlayer:
                    player.avPlayerView
                    #if os(iOS)
                        .onAppear {
                            player.pipController = .init(playerLayer: player.playerLayerView.playerLayer)
                            let pipDelegate = PiPDelegate()
                            pipDelegate.player = player

                            player.pipDelegate = pipDelegate
                            player.pipController?.delegate = pipDelegate
                            player.playerLayerView.playerLayer.player = player.avPlayerBackend.avPlayer
                        }
                    #endif
                }
            }
            .overlay(GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        player.playerSize = proxy.size
                    }
                    .onChange(of: proxy.size) { _ in player.playerSize = proxy.size }
                    .onChange(of: player.controls.presentingOverlays) { _ in player.playerSize = proxy.size }
                    .onChange(of: player.aspectRatio) { _ in player.playerSize = proxy.size }
            })
            #if os(iOS)
            .padding(.top, player.playingFullScreen && verticalSizeClass == .regular ? 20 : 0)
            #endif

            #if !os(tvOS)
                PlayerGestures()
                PlayerControls(player: player, thumbnails: thumbnails)
                #if os(iOS)
                    .padding(.top, controlsTopPadding)
                    .padding(.bottom, controlsBottomPadding)
                #endif
            #endif
        }
        #if os(iOS)
        .statusBarHidden(fullScreenLayout)
        #endif
    }

    var fullScreenLayout: Bool {
        #if os(iOS)
            player.playingFullScreen || verticalSizeClass == .compact
        #else
            player.playingFullScreen
        #endif
    }

    #if os(iOS)
        var controlsTopPadding: Double {
            guard fullScreenLayout else { return 0 }

            if UIDevice.current.userInterfaceIdiom != .pad {
                return verticalSizeClass == .compact ? SafeArea.insets.top : 0
            } else {
                return SafeArea.insets.top.isZero ? SafeArea.insets.bottom : SafeArea.insets.top
            }
        }

        var controlsBottomPadding: Double {
            guard fullScreenLayout else { return 0 }

            if UIDevice.current.userInterfaceIdiom != .pad {
                return fullScreenLayout && verticalSizeClass == .compact ? SafeArea.insets.bottom : 0
            } else {
                return fullScreenLayout ? SafeArea.insets.bottom : 0
            }
        }
    #endif
}

struct PlayerBackendView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerBackendView()
            .injectFixtureEnvironmentObjects()
    }
}
