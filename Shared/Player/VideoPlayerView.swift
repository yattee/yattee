import AVKit
#if os(iOS)
    import CoreMotion
#endif
import Defaults
import Repeat
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

    static let defaultAspectRatio = Constants.aspectRatio16x9
    static var defaultMinimumHeightLeft: Double {
        #if os(macOS)
            335
        #else
            140
        #endif
    }

    @State private var playerSize: CGSize = .zero { didSet { updateSidebarQueue() } }
    @State private var hoveringPlayer = false
    @State private var sidebarQueue = defaultSidebarQueueValue

    @Environment(\.colorScheme) private var colorScheme

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @ObservedObject private var safeAreaModel = SafeAreaModel.shared
        private var orientationModel = OrientationModel.shared
    #elseif os(macOS)
        var hoverThrottle = Throttle(interval: 0.5)
        var mouseLocation: CGPoint { NSEvent.mouseLocation }
    #endif

    #if !os(tvOS)
        @GestureState var dragGestureState = false
        @GestureState var dragGestureOffset = CGSize.zero
        // swiftlint:disable private_swiftui_state
        @State var isHorizontalDrag = false
        @State var isVerticalDrag = false
        @State var viewDragOffset = Self.hiddenOffset
        @State var detailViewDragOffset: Double = 0
        // swiftlint:enable private_swiftui_state

    #endif

    // swiftlint:disable private_swiftui_state
    @State var disableToggleGesture = false
    @State var fullScreenDetails = false
    // swiftlint:enable private_swiftui_state

    @ObservedObject var player = PlayerModel.shared // swiftlint:disable:this swiftui_state_private

    #if os(macOS)
        @ObservedObject private var navigation = NavigationModel.shared
    #endif

    @Default(.horizontalPlayerGestureEnabled) var horizontalPlayerGestureEnabled
    @Default(.fullscreenPlayerGestureEnabled) var fullscreenPlayerGestureEnabled
    @Default(.seekGestureSpeed) var seekGestureSpeed
    @Default(.seekGestureSensitivity) var seekGestureSensitivity
    @Default(.playerSidebar) var playerSidebar
    @Default(.gestureBackwardSeekDuration) private var gestureBackwardSeekDuration
    @Default(.gestureForwardSeekDuration) private var gestureForwardSeekDuration
    @Default(.avPlayerUsesSystemControls) var avPlayerUsesSystemControls

    @ObservedObject var controlsOverlayModel = ControlOverlaysModel.shared // swiftlint:disable:this swiftui_state_private

    var body: some View {
        ZStack(alignment: overlayAlignment) {
            videoPlayer
                .zIndex(-1)
            #if os(iOS)
                .gesture(controlsOverlayModel.presenting ? videoPlayerCloseControlsOverlayGesture : nil)
            #endif

            overlay
        }
        .onAppear {
            if player.musicMode {
                player.backend.startControlsUpdates()
            }
            updateSidebarQueue()
        }
        .onChange(of: playerSidebar) { _ in
            updateSidebarQueue()
        }
    }

    var videoPlayer: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                content
                    .onAppear {
                        playerSize = geometry.size
                    }
            }
            .ignoresSafeArea(.all, edges: .bottom)
            #if os(iOS)
                .frame(height: playerHeight.isNil ? nil : Double(playerHeight!))
            #endif
                .onChange(of: geometry.size) { _ in
                    self.playerSize = geometry.size
                }
            #if os(iOS)
                .onChange(of: player.presentingPlayer) { newValue in
                    if newValue {
                        viewDragOffset = 0
                    }
                }
                .onAppear {
                    #if os(macOS)
                        if player.videoForDisplay.isNil {
                            player.hide()
                        }
                    #endif
                    viewDragOffset = 0
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
        .persistentSystemOverlays(!fullScreenPlayer)
        #endif
        #if os(macOS)
        .frame(minWidth: playerSidebar != .never ? 1100 : 650, minHeight: 700)
        #endif
    }

    func updateSidebarQueue() {
        #if os(iOS)
            sidebarQueue = playerSize.width > 900 && playerSidebar == .whenFits
        #elseif os(macOS)
            sidebarQueue = playerSidebar != .never
        #endif
    }

    var overlay: some View {
        VStack {
            if controlsOverlayModel.presenting {
                HStack {
                    HStack {
                        ControlsOverlay()
                        #if os(tvOS)
                            .onExitCommand {
                                withAnimation(PlayerControls.animation) {
                                    player.controls.hideOverlays()
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
                    .frame(maxWidth: fullScreenPlayer ? .infinity : player.playerSize.width)
                    #endif

                    #if !os(tvOS)
                        if !fullScreenPlayer, sidebarQueue {
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
                    player.controls.hideOverlays()
                }
            }
        }

        var playerOffset: Double {
            dragGestureState && !isHorizontalDrag ? dragGestureOffset.height : dragOffset
        }

        var dragOffset: Double {
            if viewDragOffset.isZero || viewDragOffset == Self.hiddenOffset {
                return viewDragOffset
            }

            return player.presentingPlayer ? 0 : Self.hiddenOffset
        }

        var playerHeight: Double? {
            let lockedPortrait = player.lockedOrientation?.contains(.portrait) ?? false
            let isPortrait = OrientationTracker.shared.currentInterfaceOrientation.isPortrait || lockedPortrait
            return fullScreenPlayer ? UIScreen.main.bounds.size.height - (isPortrait ? safeAreaModel.safeArea.top + safeAreaModel.safeArea.bottom : 0) : nil
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
                            .modifier(
                                VideoPlayerSizeModifier(
                                    geometry: geometry,
                                    aspectRatio: player.aspectRatio,
                                    fullScreen: fullScreenPlayer,
                                    detailsHiddenInFullScreen: detailsHiddenInFullScreen
                                )
                            )
                            .onHover { hovering in
                                hoveringPlayer = hovering
                                if hovering {
                                    player.controls.show()
                                } else {
                                    player.controls.hide()
                                }
                            }
                            .gesture(player.controls.presentingOverlays ? nil : playerDragGesture)
                        #if os(macOS)
                            .onAppear {
                                NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
                                    hoverThrottle.execute {
                                        if !player.currentItem.isNil, hoveringPlayer {
                                            player.controls.resetTimer()
                                        }
                                    }

                                    return $0
                                }
                            }
                        #endif

                            .background(Color.black)

                        if !detailsHiddenInFullScreen {
                            VideoDetails(
                                video: player.videoForDisplay,
                                fullScreen: $fullScreenDetails,
                                sidebarQueue: $sidebarQueue
                            )
                            .modifier(VideoDetailsPaddingModifier(
                                playerSize: player.playerSize,
                                fullScreen: fullScreenDetails
                            ))
                            #if os(macOS)
                            // TODO: Check whether this is needed on macOS.
                            .onDisappear {
                                if player.presentingPlayer {
                                    player.setNeedsDrawing(true)
                                }
                            }
                            #endif
                            .id(player.currentVideo?.cacheKey)
                            .transition(.opacity)
                            .offset(y: detailViewDragOffset)
                            .gesture(detailsDragGesture)
                        } else {
                            VStack {}
                        }
                    }
                #endif
            }
            #if os(iOS)
            .background(BackgroundBlackView().edgesIgnoringSafeArea(.all))
            #endif
            .background(((colorScheme == .dark || fullScreenPlayer) ? Color.black : Color.white).edgesIgnoringSafeArea(.all))
            #if os(macOS)
                .frame(minWidth: 650)
            #endif
            #if os(tvOS)
            .onMoveCommand { direction in
                if direction == .up {
                    player.controls.show()
                } else if direction == .down, !controlsOverlayModel.presenting, !player.controls.presentingControls {
                    withAnimation(PlayerControls.animation) {
                        controlsOverlayModel.hide()
                    }
                }

                player.controls.resetTimer()

                guard !player.controls.presentingControls else { return }

                if direction == .left {
                    let interval = TimeInterval(gestureBackwardSeekDuration) ?? 10
                    player.backend.seek(relative: .secondsInDefaultTimescale(-interval), seekType: .userInteracted)
                }
                if direction == .right {
                    let interval = TimeInterval(gestureForwardSeekDuration) ?? 10
                    player.backend.seek(relative: .secondsInDefaultTimescale(interval), seekType: .userInteracted)
                }
            }
            .onPlayPauseCommand {
                player.togglePlay()
            }
            .onExitCommand {
                if player.controls.presentingOverlays {
                    player.controls.hideOverlays()
                }
                if player.controls.presentingControls {
                    player.controls.hide()
                } else {
                    player.hide()
                }
            }
            #endif
            if !detailsHiddenInFullScreen {
                #if os(iOS)
                    if sidebarQueue {
                        List {
                            PlayerQueueView(sidebarQueue: true)
                        }
                        #if os(macOS)
                        .listStyle(.inset)
                        #elseif os(iOS)
                        .listStyle(.grouped)
                        .backport
                        .scrollContentBackground(false)
                        #else
                        .listStyle(.plain)
                        #endif
                        .frame(maxWidth: 350)
                        .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
                        .transition(.move(edge: .bottom))
                    }
                #elseif os(macOS)
                    if Defaults[.playerSidebar] != .never {
                        List {
                            PlayerQueueView(sidebarQueue: true)
                        }
                        .frame(maxWidth: 450)
                        .background(colorScheme == .dark ? Color.black : Color.white)
                    }
                #endif
            } else {
                VStack {}
            }
        }
        .onChange(of: fullScreenPlayer) { newValue in
            if !newValue { player.controls.hideOverlays() }
        }
        #if os(iOS)
        .statusBar(hidden: fullScreenPlayer)
        .backport
        .toolbarBackground(colorScheme == .light ? .white : .black)
        .backport
        .toolbarBackgroundVisibility(true)
        .backport
        .toolbarColorScheme(colorScheme)
        #endif
        #if os(macOS)
        .background(
            EmptyView().sheet(isPresented: $navigation.presentingPlaybackSettings) {
                PlaybackSettings()
            }
        )
        #endif
    }

    var detailsHiddenInFullScreen: Bool {
        guard fullScreenPlayer else { return false }

        if player.activeBackend == .mpv {
            return true
        }

        #if os(iOS)
            return !avPlayerUsesSystemControls || verticalSizeClass == .compact
        #else
            return !avPlayerUsesSystemControls
        #endif
    }

    var fullScreenPlayer: Bool {
        #if os(iOS)
            player.playingFullScreen || verticalSizeClass == .compact
        #elseif os(macOS)
            player.playingFullScreen
        #elseif os(tvOS)
            true
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
                    .opacity(fullScreenPlayer ? 1 : 0)
                    .buttonStyle(.plain)
                    .padding(10)
                    .foregroundColor(.gray)
                #endif
            }
            .background(colorScheme == .dark ? Color.black : .white)
            .contentShape(Rectangle())
            .frame(width: player.playerSize.width, height: player.playerSize.height)
        }
    }

    #if os(tvOS)
        var tvControls: some View {
            TVControls()
        }
    #endif
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.red
            VideoPlayerView()
        }
    }
}

#if os(iOS)
    struct BackgroundBlackView: UIViewRepresentable {
        func makeUIView(context _: Context) -> UIView {
            let view = UIView()
            DispatchQueue.main.async {
                view.superview?.superview?.backgroundColor = .black
                view.superview?.superview?.layer.removeAllAnimations()
            }
            return view
        }

        func updateUIView(_: UIView, context _: Context) {}
    }
#endif
