import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct PlayerControls: View {
    static let animation = Animation.easeInOut(duration: 0.2)

    private var player: PlayerModel { .shared }
    private var thumbnails: ThumbnailsModel { .shared }

    @ObservedObject private var model = PlayerControlsModel.shared

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #elseif os(tvOS)
        enum Field: Hashable {
            case seekOSD
            case play
            case backward
            case forward
            case settings
            case close
        }

        @FocusState private var focusedField: Field?
    #endif

    #if !os(macOS)
        @Default(.closePlayerOnItemClose) private var closePlayerOnItemClose
    #endif

    @Default(.playerControlsLayout) private var regularPlayerControlsLayout
    @Default(.fullScreenPlayerControlsLayout) private var fullScreenPlayerControlsLayout

    private let controlsOverlayModel = ControlOverlaysModel.shared

    var playerControlsLayout: PlayerControlsLayout {
        player.playingFullScreen ? fullScreenPlayerControlsLayout : regularPlayerControlsLayout
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Seek()
                .zIndex(4)
                .transition(.opacity)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            #if os(tvOS)
                .focused($focusedField, equals: .seekOSD)
                .onChange(of: player.seek.lastSeekTime) { _ in
                    if !model.presentingControls {
                        focusedField = .seekOSD
                    }
                }
            #else
                    .offset(y: 2)
            #endif

            VStack {
                ZStack {
                    VStack(spacing: 0) {
                        ZStack {
                            OpeningStream()
                            NetworkState()
                        }

                        Spacer()
                    }
                    .offset(y: playerControlsLayout.osdVerticalOffset + 5)

                    Section {
                        #if !os(tvOS)
                            HStack {
                                seekBackwardButton
                                Spacer()
                                togglePlayButton
                                Spacer()
                                seekForwardButton
                            }
                            .font(.system(size: playerControlsLayout.bigButtonFontSize))
                        #endif

                        ZStack(alignment: .bottom) {
                            VStack(spacing: 4) {
                                #if !os(tvOS)
                                    buttonsBar

                                    HStack {
                                        if !player.currentVideo.isNil, player.playingFullScreen {
                                            Button {
                                                withAnimation(Self.animation) {
                                                    model.presentingDetailsOverlay = true
                                                }
                                            } label: {
                                                ControlsBar(fullScreen: $model.presentingDetailsOverlay, presentingControls: false, detailsTogglePlayer: false, detailsToggleFullScreen: false)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    .frame(maxWidth: 300, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Spacer()
                                    }
                                #endif

                                Spacer()

                                if playerControlsLayout.displaysTitleLine {
                                    VStack(alignment: .leading) {
                                        Text(player.currentVideo?.displayTitle ?? "Not Playing")
                                            .shadow(radius: 10)
                                            .font(.system(size: playerControlsLayout.titleLineFontSize).bold())
                                            .lineLimit(1)

                                        Text(player.currentVideo?.displayAuthor ?? "")
                                            .fontWeight(.semibold)
                                            .shadow(radius: 10)
                                            .foregroundColor(.init(white: 0.8))
                                            .font(.system(size: playerControlsLayout.authorLineFontSize))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(y: -40)
                                }

                                timeline
                                    .padding(.bottom, 2)
                            }
                            .zIndex(1)
                            .padding(.top, 2)
                            .transition(.opacity)

                            HStack(spacing: playerControlsLayout.buttonsSpacing) {
                                #if os(tvOS)
                                    togglePlayButton
                                    seekBackwardButton
                                    seekForwardButton
                                #endif
                                restartVideoButton
                                advanceToNextItemButton
                                Spacer()
                                #if os(tvOS)
                                    settingsButton
                                #endif
                                playbackModeButton
                                #if os(tvOS)
                                    closeVideoButton
                                #else
                                    musicModeButton
                                #endif
                            }
                            .zIndex(0)
                            #if os(tvOS)
                                .offset(y: -playerControlsLayout.timelineHeight - 30)
                            #else
                                .offset(y: -playerControlsLayout.timelineHeight - 5)
                            #endif
                        }
                    }
                    .opacity(model.presentingControls ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
            #if os(tvOS)
                .onChange(of: model.presentingControls) { newValue in
                    if newValue { focusedField = .play }
                }
                .onChange(of: focusedField) { _ in model.resetTimer() }
            #else
                .background(PlayerGestures())
                .background(controlsBackground)
            #endif

            if model.presentingDetailsOverlay {
                Section {
                    VideoDetailsOverlay()
                        .frame(maxWidth: detailsWidth, maxHeight: detailsHeight)
                        .transition(.opacity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .onChange(of: model.presentingOverlays) { newValue in
            if newValue {
                model.hide()
            }
        }
        #if os(tvOS)
        .onReceive(model.reporter) { value in
            guard player.presentingPlayer else { return }
            if value == "swipe down", !model.presentingControls, !model.presentingOverlays {
                withAnimation(Self.animation) {
                    controlsOverlayModel.hide()
                }
            } else {
                model.show()
            }
            model.resetTimer()
        }
        #endif
    }

    var detailsWidth: Double {
        guard player.playerSize.width.isFinite else { return 200 }
        return [player.playerSize.width, 600].min()!
    }

    var detailsHeight: Double {
        guard player.playerSize.height.isFinite else { return 200 }
        var inset = 0.0
        #if os(iOS)
            inset = SafeArea.insets.bottom
        #endif
        return [player.playerSize.height - inset, 500].min()!
    }

    @ViewBuilder var controlsBackground: some View {
        if player.musicMode,
           let item = self.player.currentItem,
           let video = item.video,
           let url = thumbnails.best(video)
        {
            WebImage(url: url, options: [.lowPriority])
                .resizable()
                .placeholder {
                    Rectangle().fill(Color("PlaceholderColor"))
                }
                .retryOnAppear(true)
                .indicator(.activity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var timeline: some View {
        TimelineView(context: .player).foregroundColor(.primary)
    }

    private var hidePlayerButton: some View {
        button("Hide", systemImage: "chevron.down") {
            player.hide()
        }

        #if !os(tvOS)
        .keyboardShortcut(.cancelAction)
        #endif
    }

    private var playbackStatus: String {
        if player.live {
            return "LIVE"
        }

        guard !player.isLoadingVideo else {
            return "loading..."
        }

        let videoLengthAtRate = (player.currentVideo?.length ?? 0) / Double(player.currentRate)
        let remainingSeconds = videoLengthAtRate - (player.time?.seconds ?? 0)

        if remainingSeconds < 60 {
            return "less than a minute"
        }

        let timeFinishAt = Date().addingTimeInterval(remainingSeconds)

        return "ends at \(formattedTimeFinishAt(timeFinishAt))"
    }

    private func formattedTimeFinishAt(_ date: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short

        return dateFormatter.string(from: date)
    }

    var buttonsBar: some View {
        HStack(spacing: playerControlsLayout.buttonsSpacing) {
            fullscreenButton

            pipButton
            #if os(iOS)
                lockOrientationButton
            #endif

            Spacer()

            settingsButton
            closeVideoButton
        }
    }

    var fullscreenButton: some View {
        button(
            "Fullscreen",
            systemImage: player.playingFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        ) {
            player.toggleFullscreen(player.playingFullScreen)
        }
        #if !os(tvOS)
        .keyboardShortcut(player.playingFullScreen ? .cancelAction : .defaultAction)
        #endif
    }

    private var settingsButton: some View {
        button("settings", systemImage: "gearshape") {
            withAnimation(Self.animation) {
                controlsOverlayModel.toggle()
            }
        }
        #if os(tvOS)
        .focused($focusedField, equals: .settings)
        #endif
    }

    private var closeVideoButton: some View {
        button("Close", systemImage: "xmark") {
            player.closeCurrentItem()
        }
        #if os(tvOS)
        .focused($focusedField, equals: .close)
        #endif
    }

    private var musicModeButton: some View {
        button("Music Mode", systemImage: "music.note", active: player.musicMode, action: player.toggleMusicMode)
    }

    private var pipButton: some View {
        let image = player.transitioningToPiP ? "pip.fill" : player.pipController?.isPictureInPictureActive ?? false ? "pip.exit" : "pip.enter"
        return button("PiP", systemImage: image) {
            (player.pipController?.isPictureInPictureActive ?? false) ? player.closePiP() : player.startPiP()
        }
        .disabled(!player.pipPossible)
    }

    #if os(iOS)
        private var lockOrientationButton: some View {
            button("Lock Rotation", systemImage: player.lockedOrientation.isNil ? "lock.rotation.open" : "lock.rotation", active: !player.lockedOrientation.isNil) {
                if player.lockedOrientation.isNil {
                    let orientationMask = OrientationTracker.shared.currentInterfaceOrientationMask
                    player.lockedOrientation = orientationMask
                    let orientation = OrientationTracker.shared.currentInterfaceOrientation
                    Orientation.lockOrientation(orientationMask, andRotateTo: .landscapeLeft)
                    // iOS 16 workaround
                    Orientation.lockOrientation(orientationMask, andRotateTo: orientation)
                } else {
                    player.lockedOrientation = nil
                    Orientation.lockOrientation(.allButUpsideDown, andRotateTo: OrientationTracker.shared.currentInterfaceOrientation)
                }
            }
        }
    #endif

    var playbackModeButton: some View {
        button("Playback Mode", systemImage: player.playbackMode.systemImage) {
            player.playbackMode = player.playbackMode.next()
            model.objectWillChange.send()
        }
    }

    var seekBackwardButton: some View {
        var foregroundColor: Color?
        var fontSize: Double?
        var size: Double?
        #if !os(tvOS)
            foregroundColor = .white
            fontSize = playerControlsLayout.bigButtonFontSize
            size = playerControlsLayout.bigButtonSize
        #endif

        return button("Seek Backward", systemImage: "gobackward.10", fontSize: fontSize, size: size, cornerRadius: 5, background: false, foregroundColor: foregroundColor) {
            player.backend.seek(relative: .secondsInDefaultTimescale(-10), seekType: .userInteracted)
        }
        .disabled(player.liveStreamInAVPlayer)
        #if os(tvOS)
            .focused($focusedField, equals: .backward)
        #else
            .keyboardShortcut("k", modifiers: [])
            .keyboardShortcut(KeyEquivalent.leftArrow, modifiers: [])
        #endif
    }

    var seekForwardButton: some View {
        var foregroundColor: Color?
        var fontSize: Double?
        var size: Double?
        #if !os(tvOS)
            foregroundColor = .white
            fontSize = playerControlsLayout.bigButtonFontSize
            size = playerControlsLayout.bigButtonSize
        #endif

        return button("Seek Forward", systemImage: "goforward.10", fontSize: fontSize, size: size, cornerRadius: 5, background: false, foregroundColor: foregroundColor) {
            player.backend.seek(relative: .secondsInDefaultTimescale(10), seekType: .userInteracted)
        }
        .disabled(player.liveStreamInAVPlayer)
        #if os(tvOS)
            .focused($focusedField, equals: .forward)
        #else
            .keyboardShortcut("l", modifiers: [])
            .keyboardShortcut(KeyEquivalent.rightArrow, modifiers: [])
        #endif
    }

    private var restartVideoButton: some View {
        button("Restart video", systemImage: "backward.end.fill", cornerRadius: 5) {
            player.backend.seek(to: 0.0, seekType: .userInteracted)
        }
    }

    private var togglePlayButton: some View {
        var foregroundColor: Color?
        var fontSize: Double?
        var size: Double?
        #if !os(tvOS)
            foregroundColor = .white
            fontSize = playerControlsLayout.bigButtonFontSize
            size = playerControlsLayout.bigButtonSize
        #endif

        return button(
            model.isPlaying ? "Pause" : "Play",
            systemImage: model.isPlaying ? "pause.fill" : "play.fill",
            fontSize: fontSize,
            size: size,
            background: false, foregroundColor: foregroundColor
        ) {
            player.backend.togglePlay()
        }
        #if os(tvOS)
        .focused($focusedField, equals: .play)
        #else
        .keyboardShortcut("p")
        .keyboardShortcut(.space)
        #endif
        .disabled(model.isLoadingVideo)
    }

    private var advanceToNextItemButton: some View {
        button("Next", systemImage: "forward.fill", cornerRadius: 5) {
            player.advanceToNextItem()
        }
        .disabled(!player.isAdvanceToNextItemAvailable)
    }

    func button(
        _ label: String,
        systemImage: String? = nil,
        fontSize: Double? = nil,
        size: Double? = nil,
        width _: Double? = nil,
        height _: Double? = nil,
        cornerRadius: Double = 3,
        background: Bool = false,
        foregroundColor: Color? = nil,
        active: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        #if os(tvOS)
            let useBackground = false
        #else
            let useBackground = background
        #endif
        return Button {
            action()
            model.resetTimer()
        } label: {
            Group {
                if let image = systemImage {
                    Label(label, systemImage: image)
                        .labelStyle(.iconOnly)
                } else {
                    Label(label, systemImage: "")
                        .labelStyle(.titleOnly)
                }
            }
            .padding()
            .contentShape(Rectangle())
            .shadow(radius: (foregroundColor == .white || !useBackground) ? 3 : 0)
        }
        .font(.system(size: fontSize ?? playerControlsLayout.buttonFontSize))
        .buttonStyle(.plain)
        .foregroundColor(foregroundColor.isNil ? (active ? Color("AppRedColor") : .primary) : foregroundColor)
        .frame(width: size ?? playerControlsLayout.buttonSize, height: size ?? playerControlsLayout.buttonSize)
        .modifier(ControlBackgroundModifier(enabled: useBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .environment(\.colorScheme, .dark)
    }
}

struct PlayerControls_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray

            PlayerControls()
                .injectFixtureEnvironmentObjects()
        }
    }
}
