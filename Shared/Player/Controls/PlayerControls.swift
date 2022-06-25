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
        }

        @FocusState private var focusedField: Field?
    #endif

    init(player: PlayerModel, thumbnails: ThumbnailsModel) {
        self.player = player
        self.thumbnails = thumbnails
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack {
                ZStack(alignment: .center) {
                    OpeningStream()
                    NetworkState()

                    Group {
                        VStack(spacing: 4) {
                            buttonsBar

                            if let video = player.currentVideo, player.playingFullScreen {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(video.title)
                                        .font(.title2.bold())

                                    Text(video.author)
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .modifier(ControlBackgroundModifier())
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

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
                    }
                    .opacity(model.presentingControlsOverlay ? 1 : model.presentingControls ? 1 : 0)
                }
            }
            #if os(tvOS)
            .onChange(of: model.presentingControls) { _ in
                if model.presentingControls {
                    focusedField = .play
                }
            }
            .onChange(of: focusedField) { _ in
                model.resetTimer()
            }
            #else
                    .background(PlayerGestures())
                    .background(controlsBackground)
            #endif

            ControlsOverlay()
                .padding()
                .modifier(ControlBackgroundModifier(enabled: true))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(x: -2, y: 40)
                .opacity(model.presentingControlsOverlay ? 1 : 0)

            Button {
                player.restoreLastSkippedSegment()
            } label: {
                HStack(spacing: 10) {
                    if let segment = player.lastSkipped {
                        Image(systemName: "arrow.counterclockwise")

                        Text("Skipped \(segment.durationText) seconds of \(SponsorBlockAPI.categoryDescription(segment.category)?.lowercased() ?? "segment")")
                            .frame(alignment: .bottomLeading)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 5)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .modifier(ControlBackgroundModifier())
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .offset(x: -2, y: -2)
            }
            .buttonStyle(.plain)
            .opacity(model.presentingControls ? 0 : player.lastSkipped.isNil ? 0 : 1)
        }
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
            #if !os(tvOS)
                fullscreenButton

                #if os(iOS)
                    pipButton
                #endif

                Spacer()

                button("settings", systemImage: "gearshape", active: model.presentingControlsOverlay) {
                    withAnimation(Self.animation) {
                        model.presentingControlsOverlay.toggle()
                    }
                }

                closeVideoButton
            #endif
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

    private var closeVideoButton: some View {
        button("Close", systemImage: "xmark") {
            player.pause()

            player.hide()
            player.closePiP()

            var delay = 0.2
            #if os(macOS)
                delay = 0.0
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                player.closeCurrentItem()
            }
        }
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
                restartVideoButton
                advanceToNextItemButton
                musicModeButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 20))
    }

    var seekBackwardButton: some View {
        button("Seek Backward", systemImage: "gobackward.10", size: 25, cornerRadius: 5, background: false) {
            player.backend.seek(relative: .secondsInDefaultTimescale(-10))
        }
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
        .disabled(player.queue.isEmpty)
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
        Button {
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
        .modifier(ControlBackgroundModifier(enabled: background))
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
