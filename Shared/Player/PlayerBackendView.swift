import Defaults
import SwiftUI

struct PlayerBackendView: View {
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @ObservedObject private var safeAreaModel = SafeAreaModel.shared
    #endif
    @ObservedObject private var player = PlayerModel.shared

    @Default(.avPlayerUsesSystemControls) private var avPlayerUsesSystemControls

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                ZStack {
                    Group {
                        switch player.activeBackend {
                        case .mpv:
                            player.mpvPlayerView
                        case .appleAVPlayer:
                            #if os(tvOS)
                                AppleAVPlayerView()
                            #else
                                if avPlayerUsesSystemControls,
                                   !player.playingInPictureInPicture,
                                   !player.avPlayerBackend.isStartingPiP
                                {
                                    AppleAVPlayerView()
                                } else if !avPlayerUsesSystemControls ||
                                    player.playingInPictureInPicture ||
                                    player.avPlayerBackend.isStartingPiP
                                {
                                    AppleAVPlayerLayerView()
                                }
                            #endif
                        }
                    }
                    .zIndex(0)
                }
            }
            .overlay(GeometryReader { proxy in
                Color.clear
                    .onAppear { player.playerSize = proxy.size }
                    .onChange(of: proxy.size) { _ in player.playerSize = proxy.size }
                    .onChange(of: player.currentItem?.id) { _ in player.playerSize = proxy.size }
            })

            #if !os(tvOS)
                if player.activeBackend == .mpv || !avPlayerUsesSystemControls {
                    PlayerGestures()
                }
                PlayerControls()
                #if os(iOS)
                    .padding(.top, controlsTopPadding)
                    .padding(.bottom, controlsBottomPadding)
                #endif
            #else
                hiddenControlsButton
            #endif
        }
        #if os(iOS)
        .statusBarHidden(player.playingFullScreen)
        #endif
    }

    #if os(iOS)
        var controlsTopPadding: Double {
            guard player.playingFullScreen else { return 0 }

            if UIDevice.current.userInterfaceIdiom != .pad {
                return verticalSizeClass == .compact ? safeAreaModel.safeArea.top : 0
            }
            return safeAreaModel.safeArea.top.isZero ? safeAreaModel.safeArea.bottom : safeAreaModel.safeArea.top
        }

        var controlsBottomPadding: Double {
            if UIDevice.current.userInterfaceIdiom != .pad {
                return player.playingFullScreen || verticalSizeClass == .compact ? safeAreaModel.safeArea.bottom : 0
            }
            return player.playingFullScreen ? safeAreaModel.safeArea.bottom : 0
        }
    #endif

    #if os(tvOS)
        private var hiddenControlsButton: some View {
            VStack {
                Button {
                    player.controls.show()
                } label: {
                    EmptyView()
                }
                .offset(y: -100)
                .buttonStyle(.plain)
                .background(Color.clear)
                .foregroundColor(.clear)
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
