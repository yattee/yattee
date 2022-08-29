import AVKit
#if os(iOS)
    import CoreMotion
#endif
import Defaults
import Siesta
import SwiftUI

struct VideoPlayerView: View {
    #if os(iOS)
        static let hiddenOffset = UIScreen.main.bounds.height
        static let defaultSidebarQueueValue = UIScreen.main.bounds.width > 900 && Defaults[.playerSidebar] == .whenFits
    #else
        static let defaultSidebarQueueValue = Defaults[.playerSidebar] != .never
    #endif

    #if os(macOS)
        static let hiddenOffset = 0.0
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

        @State internal var orientation = UIInterfaceOrientation.portrait
        @State internal var lastOrientation: UIInterfaceOrientation?
    #elseif os(macOS)
        var hoverThrottle = Throttle(interval: 0.5)
        var mouseLocation: CGPoint { NSEvent.mouseLocation }
    #endif

    #if !os(tvOS)
        @GestureState internal var dragGestureState = false
        @GestureState internal var dragGestureOffset = CGSize.zero
        @State internal var isHorizontalDrag = false
        @State internal var isVerticalDrag = false
        @State internal var viewDragOffset = Self.hiddenOffset
        @State internal var orientationObserver: Any?
    #endif

    @EnvironmentObject<AccountsModel> internal var accounts
    @EnvironmentObject<NavigationModel> internal var navigation
    @EnvironmentObject<PlayerModel> internal var player
    @EnvironmentObject<PlayerControlsModel> internal var playerControls
    @EnvironmentObject<RecentsModel> internal var recents
    #if os(macOS)
        @EnvironmentObject<SearchModel> internal var search
    #endif
    @EnvironmentObject<ThumbnailsModel> internal var thumbnails

    @Default(.horizontalPlayerGestureEnabled) var horizontalPlayerGestureEnabled
    @Default(.seekGestureSpeed) var seekGestureSpeed
    @Default(.seekGestureSensitivity) var seekGestureSensitivity

    var body: some View {
        ZStack(alignment: overlayAlignment) {
            videoPlayer
                .zIndex(-1)
            #if os(iOS)
                .gesture(playerControls.presentingControlsOverlay ? videoPlayerCloseControlsOverlayGesture : nil)
            #endif

            overlay
        }
        .animation(nil, value: player.playerSize)
        .onAppear {
            if player.musicMode {
                player.backend.startControlsUpdates()
            }
        }
    }

    var videoPlayer: some View {
        #if DEBUG
            // TODO: remove
            if #available(iOS 15.0, macOS 12.0, *) {
                Self._printChanges()
            }
        #endif

        #if os(macOS)
            return GeometryReader { geometry in
                HSplitView {
                    content
                }
                .onAppear {
                    playerSize = geometry.size
                }
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
                #if os(iOS)
                .frame(width: playerWidth.isNil ? nil : Double(playerWidth!), height: playerHeight.isNil ? nil : Double(playerHeight!))
                .ignoresSafeArea(.all, edges: playerEdgesIgnoringSafeArea)
                .onAppear {
                    viewDragOffset = 0

                    Delay.by(0.2) {
                        configureOrientationUpdatesBasedOnAccelerometer()

                        if let orientationMask = player.lockedOrientation {
                            Orientation.lockOrientation(
                                orientationMask,
                                andRotateTo: orientationMask == .landscapeLeft ? .landscapeLeft : orientationMask == .landscapeRight ? .landscapeRight : .portrait
                            )
                        }
                    }
                }
                .onDisappear {
                    if Defaults[.lockPortraitWhenBrowsing] {
                        Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                    } else {
                        Orientation.lockOrientation(.allButUpsideDown)
                    }
                    stopOrientationUpdates()
                    playerControls.hideOverlays()

                    player.lockedOrientation = nil
                }
                .onAnimationCompleted(for: viewDragOffset) {
                    guard !dragGestureState else { return }
                    if viewDragOffset == 0 {
                        player.onPresentPlayer.forEach { $0() }
                        player.onPresentPlayer = []
                    } else if viewDragOffset == Self.hiddenOffset {
                        player.hide(animate: false)
                    }
                }
                #endif
            }
            #if os(iOS)
            .onChange(of: dragGestureState) { newValue in
                guard !newValue else { return }
                onPlayerDragGestureEnded()
            }
            .offset(y: playerOffset)
            .animation(dragGestureState ? .interactiveSpring(response: 0.05) : .easeOut(duration: 0.2), value: playerOffset)
            .backport
            .persistentSystemOverlays(!fullScreenLayout)
            #endif
        #endif
    }

    var overlay: some View {
        VStack {
            if playerControls.presentingControlsOverlay {
                HStack {
                    HStack {
                        ControlsOverlay()
                        #if os(tvOS)
                            .onExitCommand {
                                withAnimation(PlayerControls.animation) {
                                    playerControls.hideOverlays()
                                }
                            }
                            .onPlayPauseCommand {
                                player.togglePlay()
                            }
                        #endif
                            .padding()
                            .modifier(ControlBackgroundModifier())
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    #if !os(tvOS)
                    .frame(maxWidth: fullScreenLayout ? .infinity : player.playerSize.width)
                    #endif

                    #if !os(tvOS)
                        if !fullScreenLayout && sidebarQueue {
                            Spacer()
                        }
                    #endif
                }
                #if os(tvOS)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                #endif
                .zIndex(1)
                .transition(.opacity)
            }
        }
    }

    var overlayWidth: Double {
        guard playerSize.width.isFinite else { return 200 }
        return [playerSize.width - 50, 250].min()!
    }

    var overlayAlignment: Alignment {
        #if os(tvOS)
            return .bottomTrailing
        #else
            return .top
        #endif
    }

    #if os(iOS)
        var videoPlayerCloseControlsOverlayGesture: some Gesture {
            TapGesture().onEnded {
                withAnimation(PlayerControls.animation) {
                    playerControls.hideOverlays()
                }
            }
        }

        var playerOffset: Double {
            dragGestureState && !isHorizontalDrag ? dragGestureOffset.height : viewDragOffset
        }

        var playerWidth: Double? {
            fullScreenLayout ? (UIScreen.main.bounds.size.width - SafeArea.insets.left - SafeArea.insets.right) : nil
        }

        var playerHeight: Double? {
            let lockedPortrait = player.lockedOrientation?.contains(.portrait) ?? false
            return fullScreenLayout ? UIScreen.main.bounds.size.height - (OrientationTracker.shared.currentInterfaceOrientation.isPortrait || lockedPortrait ? (SafeArea.insets.top + SafeArea.insets.bottom) : 0) : nil
        }

        var playerEdgesIgnoringSafeArea: Edge.Set {
            if let orientation = player.lockedOrientation, orientation.contains(.portrait) {
                return []
            }

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
                        player.playerBackendView

                        if player.activeBackend == .mpv {
                            tvControls
                        }
                    }
                    .ignoresSafeArea()
                #else
                    GeometryReader { geometry in
                        player.playerBackendView
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
                        #if !os(tvOS)
                            .gesture(playerControls.presentingOverlays ? nil : playerDragGesture)
                        #endif
                        #if os(macOS)
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
                                #endif
                                    .background(colorScheme == .dark ? Color.black : Color.white)
                                    .modifier(VideoDetailsPaddingModifier(
                                        playerSize: player.playerSize,
                                        fullScreen: fullScreenDetails
                                    ))
                                    .onDisappear {
                                        if player.presentingPlayer {
                                            player.setNeedsDrawing(true)
                                        }
                                    }
                            }
                        #endif
                    }
                #endif
            }
            .background(((colorScheme == .dark || fullScreenLayout) ? Color.black : Color.white).edgesIgnoringSafeArea(.all))
            #if os(macOS)
                .frame(minWidth: 650)
            #endif
            #if os(tvOS)
            .onMoveCommand { direction in
                if direction == .up {
                    playerControls.show()
                } else if direction == .down, !playerControls.presentingControlsOverlay, !playerControls.presentingControls {
                    withAnimation(PlayerControls.animation) {
                        playerControls.presentingControlsOverlay = true
                    }
                }

                playerControls.resetTimer()

                guard !playerControls.presentingControls else { return }

                if direction == .left {
                    player.backend.seek(relative: .secondsInDefaultTimescale(-10), seekType: .userInteracted)
                }
                if direction == .right {
                    player.backend.seek(relative: .secondsInDefaultTimescale(10), seekType: .userInteracted)
                }
            }
            .onPlayPauseCommand {
                player.togglePlay()
            }
            .onExitCommand {
                if playerControls.presentingOverlays {
                    playerControls.hideOverlays()
                }
                if playerControls.presentingControls {
                    playerControls.hide()
                } else {
                    player.hide()
                }
            }
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
            if !newValue { playerControls.hideOverlays() }
        }
        #if os(iOS)
        .statusBar(hidden: fullScreenLayout)
        #endif
    }

    var fullScreenLayout: Bool {
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0, blendDuration: 0)) {
                            viewDragOffset = Self.hiddenOffset
                        }
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

    #if os(tvOS)
        var tvControls: some View {
            TVControls(model: playerControls, player: player, thumbnails: thumbnails)
        }
    #endif
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView()
            .injectFixtureEnvironmentObjects()
    }
}
