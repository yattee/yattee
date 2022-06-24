import AVKit
#if os(iOS)
    import CoreMotion
#endif
import Defaults
import Siesta
import SwiftUI

struct VideoPlayerView: View {
    #if os(iOS)
        static let hiddenOffset = YatteeApp.isForPreviews ? 0 : max(UIScreen.main.bounds.height, UIScreen.main.bounds.width) + 100
    #endif

    static let defaultAspectRatio = 16 / 9.0
    static var defaultMinimumHeightLeft: Double {
        #if os(macOS)
            300
        #else
            200
        #endif
    }

    @State private var playerSize: CGSize = .zero { didSet {
        if playerSize.width > 900 && Defaults[.playerSidebar] == .whenFits {
            sidebarQueue = true
        } else {
            sidebarQueue = false
        }
    }}
    @State private var hoveringPlayer = false
    @State private var fullScreenDetails = false
    @State private var sidebarQueue = false

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass

        @State private var motionManager: CMMotionManager!
        @State private var orientation = UIInterfaceOrientation.portrait
        @State private var lastOrientation: UIInterfaceOrientation?
    #elseif os(macOS)
        var mouseLocation: CGPoint { NSEvent.mouseLocation }
    #endif

    #if os(iOS)
        @State private var viewVerticalOffset = Self.hiddenOffset
    #endif

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search
    @EnvironmentObject<ThumbnailsModel> private var thumbnails

    init() {
        if Defaults[.playerSidebar] == .always {
            sidebarQueue = true
        }
    }

    var body: some View {
        #if DEBUG
            // TODO: remove
            if #available(iOS 15.0, macOS 12.0, *) {
                _ = Self._printChanges()
            }
        #endif

        #if os(macOS)
            return HSplitView {
                content
            }
            .alert(isPresented: $navigation.presentingAlertInVideoPlayer) { navigation.alert }
            .onOpenURL {
                OpenURLHandler(
                    accounts: accounts,
                    navigation: navigation,
                    recents: recents,
                    player: player,
                    search: search
                ).handle($0)
            }
            .frame(minWidth: 950, minHeight: 700)
        #else
            return GeometryReader { geometry in
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
                .onChange(of: player.presentingPlayer) { newValue in
                    if newValue {
                        viewVerticalOffset = 0
                        configureOrientationUpdatesBasedOnAccelerometer()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak player] in
                            player?.onPresentPlayer?()
                            player?.onPresentPlayer = nil
                        }
                    } else {
                        if Defaults[.lockPortraitWhenBrowsing] {
                            Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                        } else {
                            Orientation.lockOrientation(.allButUpsideDown)
                        }

                        motionManager?.stopAccelerometerUpdates()
                        motionManager = nil
                        viewVerticalOffset = Self.hiddenOffset
                    }
                }
                #endif
            }
            #if os(iOS)
            .offset(y: viewVerticalOffset)
            .animation(.easeOut(duration: 0.3), value: viewVerticalOffset)
            .backport
            .persistentSystemOverlays(!fullScreenLayout)
            #endif
        #endif
    }

    var content: some View {
        Group {
            ZStack(alignment: .bottomLeading) {
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
                            if player.playingInPictureInPicture {
                                pictureInPicturePlaceholder
                            } else {
                                playerView
                                #if !os(tvOS)
                                .modifier(
                                    VideoPlayerSizeModifier(
                                        geometry: geometry,
                                        aspectRatio: player.avPlayerBackend.controller?.aspectRatio,
                                        fullScreen: player.playingFullScreen
                                    )
                                )
                                .overlay(playerPlaceholder)
                                #endif
                            }
                        }
                        .frame(maxWidth: fullScreenLayout ? .infinity : nil, maxHeight: fullScreenLayout ? .infinity : nil)
                        .onHover { hovering in
                            hoveringPlayer = hovering
//                            hovering ? playerControls.show() : playerControls.hide()
                        }
                        #if !os(macOS)
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    guard player.presentingPlayer else { return }

                                    let drag = value.translation.height

                                    guard drag > 0 else { return }

                                    guard drag < 100 else {
                                        player.hide()
                                        return
                                    }

                                    viewVerticalOffset = drag
                                }
                                .onEnded { _ in
                                    if viewVerticalOffset > 100 {
                                        player.backend.setNeedsDrawing(false)
                                        player.hide()
                                    } else {
                                        viewVerticalOffset = 0
                                        player.backend.setNeedsDrawing(true)
                                        player.show()
                                    }
                                }
                        )
                        #else
//                                .onAppear(perform: {
//                                    NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
//                                        if hoveringPlayer {
//                                            playerControls.resetTimer()
//                                        }
//
//                                        return $0
//                                    }
//                                })
                        #endif

.background(Color.black)

                        #if !os(tvOS)
                            if !player.playingFullScreen {
                                VStack(spacing: 0) {
                                    #if os(iOS)
                                        if verticalSizeClass == .regular {
                                            VideoDetails(sidebarQueue: sidebarQueue, fullScreen: fullScreenDetails)
                                                .edgesIgnoringSafeArea(.bottom)
                                        }

                                    #else
                                        VideoDetails(sidebarQueue: sidebarQueue, fullScreen: fullScreenDetails)

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
            if !player.playingFullScreen {
                #if os(iOS)
                    if sidebarQueue {
                        PlayerQueueView(sidebarQueue: true, fullScreen: fullScreenDetails)
                            .frame(maxWidth: 350)
                    }
                #elseif os(macOS)
                    if Defaults[.playerSidebar] != .never {
                        PlayerQueueView(sidebarQueue: true, fullScreen: fullScreenDetails)
                            .frame(minWidth: 300)
                    }
                #endif
            }
        }
        .ignoresSafeArea(.all, edges: fullScreenLayout ? .vertical : Edge.Set())
        #if os(iOS)
            .statusBar(hidden: player.playingFullScreen)
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

            PlayerControls(player: player, thumbnails: thumbnails)
        }
    }

    var fullScreenLayout: Bool {
        #if os(iOS)
            player.playingFullScreen || verticalSizeClass == .compact
        #else
            player.playingFullScreen
        #endif
    }

    @ViewBuilder var playerPlaceholder: some View {
        if player.currentItem.isNil {
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
            .background(Color.black)
            .contentShape(Rectangle())
            .frame(width: player.playerSize.width, height: player.playerSize.height)
        }
    }

    var pictureInPicturePlaceholder: some View {
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
        .frame(width: player.playerSize.width, height: player.playerSize.height)
    }

    #if os(iOS)
        private func configureOrientationUpdatesBasedOnAccelerometer() {
            if UIDevice.current.orientation.isLandscape,
               Defaults[.enterFullscreenInLandscape],
               !player.playingFullScreen,
               !player.playingInPictureInPicture
            {
                DispatchQueue.main.async {
                    player.enterFullScreen()
                }
            }

            guard !Defaults[.honorSystemOrientationLock], motionManager.isNil else {
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
                        guard Defaults[.enterFullscreenInLandscape] else {
                            return
                        }

                        player.enterFullScreen()

                        let orientationLockMask = orientation == .landscapeLeft ?
                            UIInterfaceOrientationMask.landscapeLeft : .landscapeRight

                        Orientation.lockOrientation(orientationLockMask, andRotateTo: orientation)

                        guard Defaults[.lockOrientationInFullScreen] else {
                            return
                        }

                        player.lockedOrientation = orientation
                    }
                } else {
                    guard abs(acceleration.z) <= 0.74,
                          player.lockedOrientation.isNil,
                          Defaults[.enterFullscreenInLandscape],
                          !Defaults[.lockOrientationInFullScreen]
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
            viewVerticalOffset = viewVerticalOffset == 0 ? 0 : Self.hiddenOffset
            let newOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation
            if newOrientation?.isLandscape ?? false,
               player.presentingPlayer,
               Defaults[.lockOrientationInFullScreen],
               !player.lockedOrientation.isNil
            {
                Orientation.lockOrientation(.landscape, andRotateTo: newOrientation)
                return
            }

            guard player.presentingPlayer, Defaults[.enterFullscreenInLandscape], Defaults[.honorSystemOrientationLock] else {
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
