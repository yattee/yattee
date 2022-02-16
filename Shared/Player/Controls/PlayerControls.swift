import Foundation
import SwiftUI

struct PlayerControls: View {
    static let animation = Animation.easeInOut(duration: 0)

    private var player: PlayerModel!
    @EnvironmentObject<PlayerControlsModel> private var model

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(player: PlayerModel) {
        self.player = player
    }

    var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Group {
                        statusBar
                            .padding(3)
                        #if os(macOS)
                            .background(VisualEffectBlur(material: .hudWindow))
                        #elseif os(iOS)
                            .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
                        #endif
                            .mask(RoundedRectangle(cornerRadius: 3))

                        buttonsBar
                            .padding(.top, 4)
                            .padding(.horizontal, 4)
                    }

                    Spacer()

                    mediumButtonsBar

                    Spacer()

                    timeline
                        .offset(y: 10)
                        .zIndex(1)

                    bottomBar

                    #if os(macOS)
                    .background(VisualEffectBlur(material: .hudWindow))
                    #elseif os(iOS)
                    .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
                    #endif
                    .mask(RoundedRectangle(cornerRadius: 3))
                }
            }
            .opacity(model.presentingControls ? 1 : 0)
        }
        .background(controlsBackground)
        .environment(\.colorScheme, .dark)
    }

    var controlsBackground: some View {
        model.presentingControls ?
            AnyView(
                PlayerGestures()
                    .background(Color.black.opacity(0.5))
            ) :
            AnyView(Color.clear)
    }

    var timeline: some View {
        TimelineView(duration: durationBinding, current: currentTimeBinding, cornerRadius: 0)
    }

    var durationBinding: Binding<Double> {
        Binding<Double>(
            get: { model.duration.seconds },
            set: { value in model.duration = .secondsInDefaultTimescale(value) }
        )
    }

    var currentTimeBinding: Binding<Double> {
        Binding<Double>(
            get: { model.currentTime.seconds },
            set: { value in model.currentTime = .secondsInDefaultTimescale(value) }
        )
    }

    var statusBar: some View {
        HStack(spacing: 4) {
            hidePlayerButton
            Text(playbackStatus)
            Spacer()
            ToggleBackendButton()
            Text("•")
            StreamControl()
        }
        .foregroundColor(.primary)
        .padding(.trailing, 4)
        .font(.system(size: 14))
    }

    private var hidePlayerButton: some View {
        Button {
            player.hide()
        } label: {
            Image(systemName: "chevron.down.circle.fill")
        }
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
        HStack {
            fullscreenButton
            Spacer()
            button("Music Mode", systemImage: "music.note")
        }
    }

    var fullscreenButton: some View {
        button(
            "Fullscreen",
            systemImage: fullScreenLayout ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        ) {
            model.toggleFullscreen(fullScreenLayout)
        }
        .keyboardShortcut(fullScreenLayout ? .cancelAction : .defaultAction)
    }

    var mediumButtonsBar: some View {
        HStack {
            button("Seek Backward", systemImage: "gobackward.10", size: 50, cornerRadius: 10) {
                player.backend.seek(relative: .secondsInDefaultTimescale(-10))
            }
            .keyboardShortcut("k")

            Spacer()

            button(
                model.isPlaying ? "Pause" : "Play",
                systemImage: model.isPlaying ? "pause.fill" : "play.fill",
                size: 50,
                cornerRadius: 10
            ) {
                player.backend.togglePlay()
            }
            .keyboardShortcut("p")
            .disabled(model.isLoadingVideo)

            Spacer()

            button("Seek Forward", systemImage: "goforward.10", size: 50, cornerRadius: 10) {
                player.backend.seek(relative: .secondsInDefaultTimescale(10))
            }
            .keyboardShortcut("l")
        }
        .font(.system(size: 30))
        .padding(.horizontal, 4)
    }

    var bottomBar: some View {
        HStack {
            Spacer()

            Text(model.playbackTime)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .labelStyle(.iconOnly)
        .foregroundColor(.primary)
    }

    func button(
        _ label: String,
        systemImage: String = "arrow.up.left.and.arrow.down.right",
        size: Double = 30,
        cornerRadius: Double = 3,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button {
            action()
            model.resetTimer()
        } label: {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .padding()
                .contentShape(Rectangle())
        }
        .foregroundColor(.primary)
        .frame(width: size, height: size)
        #if os(macOS)
            .background(VisualEffectBlur(material: .hudWindow))
        #elseif os(iOS)
            .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
        #endif
            .mask(RoundedRectangle(cornerRadius: cornerRadius))
    }

    var fullScreenLayout: Bool {
        model.playingFullscreen || verticalSizeClass == .compact
    }
}

struct PlayerControls_Previews: PreviewProvider {
    static var previews: some View {
        PlayerControls(player: PlayerModel())
    }
}
