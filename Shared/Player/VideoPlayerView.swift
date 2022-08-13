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
        static let defaultSidebarQueueValue = UIScreen.main.bounds.width > 900 && Defaults[.playerSidebar] == .whenFits
    #else
        static let defaultSidebarQueueValue = Defaults[.playerSidebar] != .never
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
        sidebarQueue = playerSize.width > 900 && Defaults[.playerSidebar] == .whenFits
    }}
    @State private var hoveringPlayer = false
    @State private var fullScreenDetails = false
    @State private var sidebarQueue = defaultSidebarQueueValue

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass

        @State private var orientation = UIInterfaceOrientation.portrait
        @State private var lastOrientation: UIInterfaceOrientation?
    #elseif os(macOS)
        var hoverThrottle = Throttle(interval: 0.5)
        var mouseLocation: CGPoint { NSEvent.mouseLocation }
    #endif

    #if os(iOS)
        @GestureState private var dragGestureState = false
        @GestureState private var dragGestureOffset = CGSize.zero
        @State private var viewDragOffset = 0.0
        @State private var orientationObserver: Any?
    #endif

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlayerControlsModel> private var playerControls
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SearchModel> private var search
    @EnvironmentObject<ThumbnailsModel> private var thumbnails

    var body: some View {
        #if DEBUG
            // TODO: remove
            if #available(iOS 15.0, macOS 12.0, *) {
                Self._printChanges()
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
                #if os(iOS)
                .frame(width: playerWidth.isNil ? nil : Double(playerWidth!), height: playerHeight.isNil ? nil : Double(playerHeight!))
                .ignoresSafeArea(.all, edges: playerEdgesIgnoringSafeArea)
                #endif
                .onChange(of: geometry.size) { size in
                    self.playerSize = size
                }
                .onChange(of: fullScreenDetails) { value in
                    player.backend.setNeedsDrawing(!value)
                }
                .onAppear {
                    #if os(iOS)
                        viewDragOffset = 0.0
                        configureOrientationUpdatesBasedOnAccelerometer()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak player] in
                            player?.onPresentPlayer?()
                            player?.onPresentPlayer = nil
                        }

                        if let orientationMask = player.lockedOrientation {
                            Orientation.lockOrientation(
                                orientationMask,
                                andRotateTo: orientationMask == .landscapeLeft ? .landscapeLeft : orientationMask == .landscapeRight ? .landscapeRight : .portrait
                            )
                        }
                    #endif
                }
                .onDisappear {
                    #if os(iOS)
                        if Defaults[.lockPortraitWhenBrowsing] {
                            Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                        } else {
                            Orientation.lockOrientation(.allButUpsideDown)
                        }
                        stopOrientationUpdates()
                        player.controls.hideOverlays()

                        player.lockedOrientation = nil
                    #endif
                }
            }
            #if os(iOS)
            .offset(y: playerOffset)
            .animation(.linear(duration: 0.2), value: playerOffset)
            .backport
            .persistentSystemOverlays(!fullScreenLayout)
            #endif
        #endif
    }

    #if os(iOS)
        var playerOffset: Double {
            dragGestureState ? dragGestureOffset.height : viewDragOffset
        }

        var playerWidth: Double? {
            fullScreenLayout ? (UIScreen.main.bounds.size.width - SafeArea.insets.left - SafeArea.insets.right) : nil
        }

        var playerHeight: Double? {
            fullScreenLayout ? UIScreen.main.bounds.size.height - (OrientationTracker.shared.currentInterfaceOrientation.isPortrait ? (SafeArea.insets.top + SafeArea.insets.bottom) : 0) : nil
        }

        var playerEdgesIgnoringSafeArea: Edge.Set {
            if fullScreenLayout, UIDevice.current.orientation.isLandscape {
                return [.vertical]
            }
            return []
        }
    #endif

    var content: some View {
        Group {
            ZStack(alignment: .bottomLeading) {
                #if os(tvOS)
                    ZStack {
                        PlayerBackendView()

                        tvControls
                    }
                    .ignoresSafeArea()
                    .onMoveCommand { direction in
                        if direction == .up || direction == .down {
                            playerControls.show()
                        }

                        playerControls.resetTimer()

                        guard !playerControls.presentingControls else { return }

                        if direction == .left {
                            player.backend.seek(relative: .secondsInDefaultTimescale(-10))
                        }
                        if direction == .right {
                            player.backend.seek(relative: .secondsInDefaultTimescale(10))
                        }
                    }
                    .onPlayPauseCommand {
                        player.togglePlay()
                    }

                    .onExitCommand {
                        if playerControls.presentingControls {
                            playerControls.hide()
                        } else {
                            player.hide()
                        }
                    }
                #else
                    GeometryReader { geometry in
                        PlayerBackendView()
                        #if !os(tvOS)
                            .modifier(
                                VideoPlayerSizeModifier(
                                    geometry: geometry,
                                    aspectRatio: player.aspectRatio,
                                    fullScreen: fullScreenLayout
                                )
                            )
                            .overlay(playerPlaceholder)
                        #endif
                            .frame(maxWidth: fullScreenLayout ? .infinity : nil, maxHeight: fullScreenLayout ? .infinity : nil)
                            .onHover { hovering in
                                hoveringPlayer = hovering
                                hovering ? playerControls.show() : playerControls.hide()
                            }
                        #if os(iOS)
                            .gesture(playerControls.presentingOverlays ? nil : playerDragGesture)
                            .onChange(of: dragGestureState) { _ in
                                if !dragGestureState {
                                    onPlayerDragGestureEnded()
                                }
                            }
                        #elseif os(macOS)
                            .onAppear(perform: {
                                NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
                                    hoverThrottle.execute {
                                        if !player.currentItem.isNil, hoveringPlayer {
                                            playerControls.resetTimer()
                                        }
                                    }

                                    return $0
                                }
                            })
                        #endif

                            .background(Color.black)

                        #if !os(tvOS)
                            if !fullScreenLayout {
                                VideoDetails(sidebarQueue: sidebarQueue, fullScreen: $fullScreenDetails)
                                #if os(iOS)
                                    .ignoresSafeArea(.all, edges: .bottom)
                                    .transition(.move(edge: .bottom))
                                #endif
                                    .background(colorScheme == .dark ? Color.black : Color.white)
                                    .modifier(VideoDetailsPaddingModifier(
                                        playerSize: player.playerSize,
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
            if !fullScreenLayout {
                #if os(iOS)
                    if sidebarQueue {
                        PlayerQueueView(sidebarQueue: true, fullScreen: $fullScreenDetails)
                            .frame(maxWidth: 350)
                            .background(colorScheme == .dark ? Color.black : Color.white)
                            .transition(.move(edge: .bottom))
                    }
                #elseif os(macOS)
                    if Defaults[.playerSidebar] != .never {
                        PlayerQueueView(sidebarQueue: true, fullScreen: $fullScreenDetails)
                            .frame(minWidth: 300)
                            .background(colorScheme == .dark ? Color.black : Color.white)
                    }
                #endif
            }
        }
        .onChange(of: fullScreenLayout) { newValue in
            if !newValue { playerControls.presentingDetailsOverlay = false }
        }
        #if os(iOS)
        .statusBar(hidden: fullScreenLayout)
        #endif
    }

    var fullScreenLayout: Bool {
        if player.currentItem.isNil {
            return false
        }

        #if os(iOS)
            return player.playingFullScreen || verticalSizeClass == .compact
        #else
            return player.playingFullScreen
        #endif
    }

    @ViewBuilder var playerPlaceholder: some View {
        if player.currentItem.isNil {
            ZStack(alignment: .topTrailing) {
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

    #if os(iOS)
        var playerDragGesture: some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .updating($dragGestureOffset) { value, state, _ in
                    state = value.translation.height > 0 ? value.translation : .zero
                }
                .updating($dragGestureState) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    guard player.presentingPlayer,
                          !playerControls.presentingControlsOverlay else { return }

                    if player.controls.presentingControls {
                        player.controls.presentingControls = false
                    }

                    let drag = value.translation.height

                    guard drag > 0 else { return }

                    viewDragOffset = drag

                    if drag > 60,
                       player.playingFullScreen
                    {
                        player.exitFullScreen()
                        if Defaults[.rotateToPortraitOnExitFullScreen] {
                            Orientation.lockOrientation(.allButUpsideDown, andRotateTo: .portrait)
                            playerControls.show()
                        }
                    }
                }
                .onEnded { _ in
                    onPlayerDragGestureEnded()
                }
        }

        private func onPlayerDragGestureEnded() {
            guard player.presentingPlayer,
                  !playerControls.presentingControlsOverlay else { return }

            if viewDragOffset > 100 {
                player.hide()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    player.backend.setNeedsDrawing(false)
                    player.exitFullScreen()
                }

                viewDragOffset = Self.hiddenOffset
            } else {
                withAnimation(.linear(duration: 0.2)) {
                    viewDragOffset = 0
                }
                player.backend.setNeedsDrawing(true)
                player.show()
            }
        }

        private func configureOrientationUpdatesBasedOnAccelerometer() {
            let currentOrientation = OrientationTracker.shared.currentInterfaceOrientation
            if currentOrientation.isLandscape,
               Defaults[.enterFullscreenInLandscape],
               !player.playingFullScreen,
               !player.playingInPictureInPicture
            {
                DispatchQueue.main.async {
                    player.controls.presentingControls = false
                    player.enterFullScreen(showControls: false)
                }

                Orientation.lockOrientation(.allButUpsideDown, andRotateTo: currentOrientation)
            }

            orientationObserver = NotificationCenter.default.addObserver(
                forName: OrientationTracker.deviceOrientationChangedNotification,
                object: nil,
                queue: .main
            ) { _ in
                guard !Defaults[.honorSystemOrientationLock],
                      player.presentingPlayer,
                      !player.playingInPictureInPicture,
                      player.lockedOrientation.isNil
                else {
                    return
                }

                let orientation = OrientationTracker.shared.currentInterfaceOrientation

                guard lastOrientation != orientation else {
                    return
                }

                lastOrientation = orientation

                DispatchQueue.main.async {
                    guard Defaults[.enterFullscreenInLandscape] else {
                        return
                    }

                    if orientation.isLandscape {
                        player.controls.presentingControls = false
                        player.enterFullScreen(showControls: false)
                        Orientation.lockOrientation(OrientationTracker.shared.currentInterfaceOrientationMask, andRotateTo: orientation)
                    } else {
                        player.exitFullScreen(showControls: false)
                        Orientation.lockOrientation(.allButUpsideDown, andRotateTo: .portrait)
                    }
                }
            }
        }

        private func stopOrientationUpdates() {
            guard let observer = orientationObserver else { return }
            NotificationCenter.default.removeObserver(observer)
        }
    #endif

    #if os(tvOS)
        var tvControls: some View {
            TVControls(model: playerControls, player: player, thumbnails: thumbnails)
                .onReceive(playerControls.reporter) { _ in
                    playerControls.show()
                    playerControls.resetTimer()
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
