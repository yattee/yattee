import AVKit
#if os(iOS)
    import CoreMotion
#endif
import Defaults
import Siesta
import SwiftUI

struct VideoPlayerView: View {
    static let defaultAspectRatio = 16 / 9.0
    static var defaultMinimumHeightLeft: Double {
        #if os(macOS)
            300
        #else
            200
        #endif
    }

    @State private var playerSize: CGSize = .zero
    @State private var fullScreenDetails = false

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.presentationMode) private var presentationMode
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass

        @Default(.enterFullscreenInLandscape) private var enterFullscreenInLandscape
        @Default(.honorSystemOrientationLock) private var honorSystemOrientationLock
        @Default(.lockLandscapeOnRotation) private var lockLandscapeOnRotation

        @State private var motionManager: CMMotionManager!
        @State private var orientation = UIInterfaceOrientation.portrait
        @State private var lastOrientation: UIInterfaceOrientation?
    #endif

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        #if os(macOS)
            HSplitView {
                content
            }
            .onOpenURL { OpenURLHandler(accounts: accounts, player: player).handle($0) }
            .frame(minWidth: 950, minHeight: 700)
        #else
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    content
                        .onAppear {
                            playerSize = geometry.size

                            #if os(iOS)
                                configureOrientationUpdatesBasedOnAccelerometer()
                            #endif
                        }
                }
                .onChange(of: geometry.size) { size in
                    self.playerSize = size
                }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                    handleOrientationDidChangeNotification()
                }
                .onDisappear {
                    guard !player.playingFullscreen else {
                        return // swiftlint:disable:this implicit_return
                    }

                    if Defaults[.lockPortraitWhenBrowsing] {
                        Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                    } else {
                        Orientation.lockOrientation(.allButUpsideDown)
                    }

                    motionManager?.stopAccelerometerUpdates()
                    motionManager = nil
                }
                #endif
            }
            .navigationBarHidden(true)
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
                            } else if player.playingInPictureInPicture {
                                pictureInPicturePlaceholder(geometry: geometry)
                            } else {
                                player.playerView
                                    .modifier(
                                        VideoPlayerSizeModifier(
                                            geometry: geometry,
                                            aspectRatio: player.controller?.aspectRatio
                                        )
                                    )
                            }
                        }
                        #if os(iOS)
                        .onSwipeGesture(
                            up: {
                                withAnimation {
                                    fullScreenDetails = true
                                }
                            },
                            down: { player.hide() }
                        )
                        #endif

                        .background(Color.black)

                        Group {
                            #if os(iOS)
                                if verticalSizeClass == .regular {
                                    VideoDetails(sidebarQueue: sidebarQueueBinding, fullScreen: $fullScreenDetails)
                                }

                            #else
                                VideoDetails(sidebarQueue: sidebarQueueBinding, fullScreen: $fullScreenDetails)
                            #endif
                        }
                        .background(colorScheme == .dark ? Color.black : Color.white)
                        .modifier(VideoDetailsPaddingModifier(
                            geometry: geometry,
                            aspectRatio: player.controller?.aspectRatio,
                            fullScreen: fullScreenDetails
                        ))
                    }
                #endif
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            #if os(macOS)
                .frame(minWidth: 650)
            #endif
            #if os(iOS)
                if sidebarQueue {
                    PlayerQueueView(sidebarQueue: .constant(true), fullScreen: $fullScreenDetails)
                        .frame(maxWidth: 350)
                }
            #elseif os(macOS)
                if Defaults[.playerSidebar] != .never {
                    PlayerQueueView(sidebarQueue: sidebarQueueBinding, fullScreen: $fullScreenDetails)
                        .frame(minWidth: 300)
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

    func pictureInPicturePlaceholder(geometry: GeometryProxy) -> some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    #if !os(tvOS)
                        Image(systemName: "pip")
                            .font(.system(size: 120))
                    #endif

                    Text("Playing in Picture in Picture")
                }
                Spacer()
            }
            .foregroundColor(.gray)
            Spacer()
        }
        .contextMenu {
            Button {
                player.closePiP()
            } label: {
                Label("Exit Picture in Picture", systemImage: "pip.exit")
            }
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

    #if os(iOS)
        private func configureOrientationUpdatesBasedOnAccelerometer() {
            if UIDevice.current.orientation.isLandscape,
               enterFullscreenInLandscape,
               !player.playingFullscreen,
               !player.playingInPictureInPicture
            {
                DispatchQueue.main.async {
                    player.enterFullScreen()
                }
            }

            guard !honorSystemOrientationLock, motionManager.isNil else {
                return
            }

            motionManager = CMMotionManager()
            motionManager.accelerometerUpdateInterval = 0.2
            motionManager.startAccelerometerUpdates(to: OperationQueue()) { data, _ in
                guard player.presentingPlayer, !player.playingInPictureInPicture, !data.isNil else {
                    return
                }

                guard let acceleration = data?.acceleration else {
                    return
                }

                var orientation = UIInterfaceOrientation.unknown

                if acceleration.x >= 0.65 {
                    orientation = .landscapeLeft
                } else if acceleration.x <= -0.65 {
                    orientation = .landscapeRight
                } else if acceleration.y <= -0.65 {
                    orientation = .portrait
                } else if acceleration.y >= 0.65 {
                    orientation = .portraitUpsideDown
                }

                guard lastOrientation != orientation else {
                    return
                }

                lastOrientation = orientation

                if orientation.isLandscape {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        guard enterFullscreenInLandscape else {
                            return
                        }

                        player.enterFullScreen()

                        let orientationLockMask = orientation == .landscapeLeft ?
                            UIInterfaceOrientationMask.landscapeLeft : .landscapeRight

                        Orientation.lockOrientation(orientationLockMask, andRotateTo: orientation)

                        guard lockLandscapeOnRotation else {
                            return
                        }

                        player.lockedOrientation = orientation
                    }
                } else {
                    guard abs(acceleration.z) <= 0.74,
                          player.lockedOrientation.isNil,
                          enterFullscreenInLandscape
                    else {
                        return
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        player.exitFullScreen()
                    }

                    Orientation.lockOrientation(.portrait)
                }
            }
        }

        private func handleOrientationDidChangeNotification() {
            let newOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation
            if newOrientation?.isLandscape ?? false,
               player.presentingPlayer,
               lockLandscapeOnRotation,
               !player.lockedOrientation.isNil
            {
                Orientation.lockOrientation(.landscape, andRotateTo: newOrientation)
                return
            }

            guard player.presentingPlayer, enterFullscreenInLandscape, honorSystemOrientationLock else {
                return
            }

            if UIDevice.current.orientation.isLandscape {
                DispatchQueue.main.async {
                    player.lockedOrientation = newOrientation
                    player.enterFullScreen()
                }
            } else {
                DispatchQueue.main.async {
                    player.exitFullScreen()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    player.exitFullScreen()
                }
            }
        }
    #endif
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView()
            .injectFixtureEnvironmentObjects()
    }
}
