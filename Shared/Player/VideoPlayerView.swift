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
    @State private var hoveringPlayer = false
    @State private var fullScreenDetails = false

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass

        @Default(.enterFullscreenInLandscape) private var enterFullscreenInLandscape
        @Default(.honorSystemOrientationLock) private var honorSystemOrientationLock
        @Default(.lockLandscapeOnRotation) private var lockLandscapeOnRotation

        @State private var motionManager: CMMotionManager!
        @State private var orientation = UIInterfaceOrientation.portrait
        @State private var lastOrientation: UIInterfaceOrientation?
    #elseif os(macOS)
        var mouseLocation: CGPoint { NSEvent.mouseLocation }
    #endif

    #if !os(macOS)
        @State private var playerOffset = UIScreen.main.bounds.height
    #endif

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<PlayerControlsModel> private var playerControls
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
                        }
                }
                .onChange(of: geometry.size) { size in
                    self.playerSize = size
                }
                .onChange(of: fullScreenDetails) { value in
                    player.backend.setNeedsDrawing(!value)
                }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                    handleOrientationDidChangeNotification()
                }
                #endif
            }
            .offset(y: playerOffset)
            .animation(.easeIn(duration: 0.2), value: playerOffset)
        #endif
    }

    var content: some View {
        Group {
            Group {
                #if os(tvOS)
                    playerView
                        .ignoresSafeArea(.all, edges: .all)
                        .onMoveCommand { direction in
                            if direction == .left {
                                playerControls.resetTimer()
                                player.backend.seek(relative: .secondsInDefaultTimescale(-10))
                            }
                            if direction == .right {
                                playerControls.resetTimer()
                                player.backend.seek(relative: .secondsInDefaultTimescale(10))
                            }
                            if direction == .up {
                                playerControls.show()
                                playerControls.resetTimer()
                            }
                            if direction == .down {
                                playerControls.show()
                                playerControls.resetTimer()
                            }
                        }
                #else
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            if player.currentItem.isNil {
                                playerPlaceholder(geometry: geometry)
                            } else if player.playingInPictureInPicture {
                                pictureInPicturePlaceholder(geometry: geometry)
                            } else {
                                playerView
                                #if !os(tvOS)
                                .modifier(
                                    VideoPlayerSizeModifier(
                                        geometry: geometry,
                                        aspectRatio: player.avPlayerBackend.controller?.aspectRatio,
                                        fullScreen: playerControls.playingFullscreen
                                    )
                                )
                                #endif
                            }
                        }
                        .frame(maxWidth: fullScreenLayout ? .infinity : nil, maxHeight: fullScreenLayout ? .infinity : nil)
                        .onHover { hovering in
                            hoveringPlayer = hovering
                            hovering ? playerControls.show() : playerControls.hide()
                        }
                        #if !os(tvOS)
                        .onChange(of: player.presentingPlayer) { newValue in
                            if newValue {
                                playerOffset = 0
                                #if os(iOS)
                                    configureOrientationUpdatesBasedOnAccelerometer()
                                #endif
                            } else {
                                #if !os(macOS)
                                    playerOffset = UIScreen.main.bounds.height

                                    #if os(iOS)
                                        if Defaults[.lockPortraitWhenBrowsing] {
                                            Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                                        } else {
                                            Orientation.lockOrientation(.allButUpsideDown)
                                        }

                                        motionManager?.stopAccelerometerUpdates()
                                        motionManager = nil
                                    #endif
                                #endif
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !fullScreenLayout else {
                                        return
                                    }

                                    player.backend.setNeedsDrawing(false)
                                    let drag = value.translation.height

                                    guard drag > 0 else {
                                        return
                                    }

                                    withAnimation(.easeIn(duration: 0.2)) {
                                        playerOffset = drag
                                    }
                                }
                                .onEnded { _ in
                                    if playerOffset > 100 {
                                        player.backend.setNeedsDrawing(true)
                                        player.hide()
                                    } else {
                                        player.show()
                                        playerOffset = 0
                                    }
                                }
                        )
                        #endif
                        #if os(macOS)
                        .onAppear(perform: {
                            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
                                if hoveringPlayer {
                                    playerControls.resetTimer()
                                }

                                return $0
                            }
                        })
                        #endif

                        .background(Color.black)

                        #if !os(tvOS)
                            if !playerControls.playingFullscreen {
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
                                    aspectRatio: player.avPlayerBackend.controller?.aspectRatio,
                                    fullScreen: fullScreenDetails
                                ))
                            }
                        #endif
                    }
                #endif
            }
            .background(((colorScheme == .dark || fullScreenLayout) ? Color.black : Color.white).edgesIgnoringSafeArea(.all))
            #if os(macOS)
                .frame(minWidth: 650)
            #endif
            if !playerControls.playingFullscreen {
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
        .ignoresSafeArea(.all, edges: fullScreenLayout ? .vertical : Edge.Set())
        #if os(iOS)
            .statusBar(hidden: playerControls.playingFullscreen)
            .navigationBarHidden(true)
        #endif
    }

    var playerView: some View {
        ZStack(alignment: .top) {
            switch player.activeBackend {
            case .mpv:
                player.mpvPlayerView
                    .overlay(GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                player.playerSize = proxy.size
                            }
                            .onChange(of: proxy.size) { _ in
                                player.playerSize = proxy.size
                            }
                    })
            case .appleAVPlayer:
                player.avPlayerView
                #if os(iOS)
                    .onAppear {
                        player.pipController = .init(playerLayer: player.playerLayerView.playerLayer)
                        let pipDelegate = PiPDelegate()
                        pipDelegate.player = player

                        player.pipDelegate = pipDelegate
                        player.pipController!.delegate = pipDelegate
                        player.playerLayerView.playerLayer.player = player.avPlayerBackend.avPlayer
                    }
                #endif
            }

            #if !os(tvOS)
                PlayerGestures()
            #endif

            PlayerControls(player: player)
        }
        #if os(iOS)
        .onAppear {
            // ugly patch for #78
            guard player.activeBackend == .mpv else {
                return
            }

            player.activeBackend = .appleAVPlayer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                player.activeBackend = .mpv
            }
        }
        #endif
    }

    var fullScreenLayout: Bool {
        #if os(iOS)
            playerControls.playingFullscreen || verticalSizeClass == .compact
        #else
            playerControls.playingFullscreen
        #endif
    }

    func playerPlaceholder(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
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

            #if os(iOS)
                Button {
                    player.hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .padding(10)
                .foregroundColor(.gray)
            #endif
        }
        .contentShape(Rectangle())
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: geometry.size.width / Self.defaultAspectRatio)
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
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: geometry.size.width / Self.defaultAspectRatio)
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
               !playerControls.playingFullscreen,
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
                          enterFullscreenInLandscape,
                          !lockLandscapeOnRotation
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
            playerOffset = playerOffset == 0 ? 0 : UIScreen.main.bounds.height
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
