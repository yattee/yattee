import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct PlayerControls: View {
    static let animation = Animation.easeInOut(duration: 0.2)

    private var player: PlayerModel!
    private var thumbnails: ThumbnailsModel!

    @EnvironmentObject<PlayerControlsModel> private var model

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #elseif os(tvOS)
        enum Field: Hashable {
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

    init(player: PlayerModel, thumbnails: ThumbnailsModel) {
        self.player = player
        self.thumbnails = thumbnails
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack {
                ZStack(alignment: .center) {
                    OpeningStream()
                    NetworkState()

                    if model.presentingControls && !model.presentingOverlays {
                        VStack(spacing: 4) {
                            #if !os(tvOS)
                                buttonsBar

                                HStack {
                                    if !player.currentVideo.isNil, fullScreenLayout {
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

                            Group {
                                ZStack(alignment: .bottom) {
                                    floatingControls
                                        .padding(.top, 20)
                                        .padding(4)
                                        .modifier(ControlBackgroundModifier())
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    timeline
                                        .padding(4)
                                        .offset(y: -25)
                                        .zIndex(1)
                                }
                                .frame(maxWidth: 500)
                                .padding(.bottom, 2)
                            }
                        }
                        .padding(.top, 2)
                        .padding(.horizontal, 2)
                        .transition(.opacity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
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
                VideoDetailsOverlay()
                    .frame(maxWidth: detailsWidth, maxHeight: detailsHeight)
                    .modifier(ControlBackgroundModifier())
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .transition(.opacity)
            }

            if !model.presentingControls,
               !model.presentingOverlays,
               let segment = player.lastSkipped
            {
                Button {
                    player.restoreLastSkippedSegment()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")

                        Text("Skipped \(segment.durationText) seconds of \(SponsorBlockAPI.categoryDescription(segment.category)?.lowercased() ?? "segment")")
                            .frame(alignment: .bottomLeading)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 5)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .modifier(ControlBackgroundModifier())
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .onChange(of: model.presentingOverlays) { newValue in
            if newValue {
                player.backend.stopControlsUpdates()
            } else {
                #if os(tvOS)
                    focusedField = .play
                #endif
                player.backend.startControlsUpdates()
            }
        }
        #if os(tvOS)
        .onReceive(model.reporter) { value in
            if value == "swipe down", !model.presentingControls, !model.presentingOverlays {
                withAnimation(Self.animation) {
                    model.presentingControlsOverlay = true
                }
            } else {
                model.show()
            }
            model.resetTimer()
        }
        #endif
    }

    var detailsWidth: Double {
        guard let player = player, player.playerSize.width.isFinite else { return 200 }
        return [player.playerSize.width, 600].min()!
    }

    var detailsHeight: Double {
        guard let player = player, player.playerSize.height.isFinite else { return 200 }
        return [player.playerSize.height, 500].min()!
    }

    @ViewBuilder var controlsBackground: some View {
        if player.musicMode,
           let item = self.player.currentItem,
           let video = item.video,
           let url = thumbnails.best(video)
        {
            WebImage(url: url)
                .resizable()
                .placeholder {
                    Rectangle().fill(Color("PlaceholderColor"))
                }
                .retryOnAppear(true)
                .indicator(.activity)
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
        HStack(spacing: 20) {
            fullscreenButton

            #if os(iOS)
                pipButton
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
            systemImage: fullScreenLayout ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        ) {
            player.toggleFullscreen(fullScreenLayout)
        }
        #if !os(tvOS)
        .keyboardShortcut(fullScreenLayout ? .cancelAction : .defaultAction)
        #endif
    }

    private var settingsButton: some View {
        button("settings", systemImage: "gearshape", active: model.presentingControlsOverlay) {
            withAnimation(Self.animation) {
                model.presentingControlsOverlay.toggle()
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
        button("Music Mode", systemImage: "music.note", background: false, active: player.musicMode, action: player.toggleMusicMode)
            .disabled(player.activeBackend == .appleAVPlayer)
    }

    private var pipButton: some View {
        button("PiP", systemImage: "pip") {
            model.startPiP()
        }
    }

    #if os(iOS)
        private var lockOrientationButton: some View {
            button("Lock Rotation", systemImage: player.lockedOrientation.isNil ? "lock.rotation.open" : "lock.rotation", active: !player.lockedOrientation.isNil) {
                if player.lockedOrientation.isNil {
                    let orientationMask = OrientationTracker.shared.currentInterfaceOrientationMask
                    player.lockedOrientation = orientationMask
                    Orientation.lockOrientation(orientationMask)
                } else {
                    player.lockedOrientation = nil
                    Orientation.lockOrientation(.allButUpsideDown, andRotateTo: OrientationTracker.shared.currentInterfaceOrientation)
                }
            }
        }
    #endif

    var floatingControls: some View {
        HStack {
            HStack(spacing: 20) {
                togglePlayButton
                seekBackwardButton
                seekForwardButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: 20) {
                playbackModeButton
                restartVideoButton
                advanceToNextItemButton
                #if !os(tvOS)
                    musicModeButton
                #else
                    settingsButton
                    closeVideoButton
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 20))
    }

    var playbackModeButton: some View {
        button("Playback Mode", systemImage: player.playbackMode.systemImage, background: false) {
            player.playbackMode = player.playbackMode.next()
            model.objectWillChange.send()
        }
    }

    var seekBackwardButton: some View {
        button("Seek Backward", systemImage: "gobackward.10", size: 25, cornerRadius: 5, background: false) {
            player.backend.seek(relative: .secondsInDefaultTimescale(-10))
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
        button("Seek Forward", systemImage: "goforward.10", size: 25, cornerRadius: 5, background: false) {
            player.backend.seek(relative: .secondsInDefaultTimescale(10))
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
        button("Restart video", systemImage: "backward.end.fill", size: 25, cornerRadius: 5, background: false) {
            player.backend.seek(to: 0.0)
        }
    }

    private var togglePlayButton: some View {
        button(
            model.isPlaying ? "Pause" : "Play",
            systemImage: model.isPlaying ? "pause.fill" : "play.fill",
            size: 25, cornerRadius: 5, background: false
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
        button("Next", systemImage: "forward.fill", size: 25, cornerRadius: 5, background: false) {
            player.advanceToNextItem()
        }
        .disabled(!player.isAdvanceToNextItemAvailable)
    }

    func button(
        _ label: String,
        systemImage: String? = nil,
        size: Double = 25,
        width: Double? = nil,
        height: Double? = nil,
        cornerRadius: Double = 3,
        background: Bool = true,
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
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .foregroundColor(active ? Color("AppRedColor") : .primary)
        .frame(width: width ?? size, height: height ?? size)
        .modifier(ControlBackgroundModifier(enabled: useBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    var fullScreenLayout: Bool {
        #if os(iOS)
            player.playingFullScreen || verticalSizeClass == .compact
        #else
            player.playingFullScreen
        #endif
    }
}

struct PlayerControls_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray

            PlayerControls(player: PlayerModel(), thumbnails: ThumbnailsModel())
                .injectFixtureEnvironmentObjects()
        }
    }
}
