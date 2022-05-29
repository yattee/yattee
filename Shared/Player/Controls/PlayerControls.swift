import Foundation
import SwiftUI

struct PlayerControls: View {
    static let animation = Animation.easeInOut(duration: 0.2)

    private var player: PlayerModel!

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

    init(player: PlayerModel) {
        self.player = player
    }

    var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Group {
                        HStack {
                            statusBar
                                .padding(3)
                            #if os(macOS)
                                .background(VisualEffectBlur(material: .hudWindow))
                            #elseif os(iOS)
                                .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
                            #endif
                                .mask(RoundedRectangle(cornerRadius: 3))

                            Spacer()
                        }

                        buttonsBar
                            .padding(.top, 4)
                            .padding(.horizontal, 4)
                    }

                    Spacer()

                    mediumButtonsBar

                    Spacer()

                    Group {
                        timeline
                            .offset(y: 10)
                            .zIndex(1)

                        HStack {
                            Spacer()

                            bottomBar
                            #if os(macOS)
                            .background(VisualEffectBlur(material: .hudWindow))
                            #elseif os(iOS)
                            .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
                            #endif
                            .mask(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .opacity(model.presentingControls ? 1 : 0)
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
        #endif
                .environment(\.colorScheme, .dark)
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
            Text(playbackStatus)

            Text("•")

            #if !os(tvOS)
                ToggleBackendButton()
                Text("•")

                StreamControl()
                #if os(macOS)
                    .frame(maxWidth: 300)
                #endif
            #else
                Text(player.stream?.description ?? "")
            #endif
        }
        .foregroundColor(.primary)
        .padding(.trailing, 4)
        .font(.system(size: 14))
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
                #if os(iOS)
                    hidePlayerButton
                #endif

                fullscreenButton
                #if os(iOS)
                    pipButton
                #endif
                rateButton

                closeVideoButton

                Spacer()
            #endif
//            button("Music Mode", systemImage: "music.note")
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

    @ViewBuilder private var rateButton: some View {
        #if os(macOS)
            ratePicker
                .labelsHidden()
                .frame(maxWidth: 70)
        #elseif os(iOS)
            Menu {
                ratePicker
                    .frame(width: 45, height: 30)
                #if os(iOS)
                    .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
                #endif
                    .mask(RoundedRectangle(cornerRadius: 3))
            } label: {
                Text(player.rateLabel(player.currentRate))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .frame(width: 50, height: 30)
            #if os(macOS)
                .background(VisualEffectBlur(material: .hudWindow))
            #elseif os(iOS)
                .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
            #endif
                .mask(RoundedRectangle(cornerRadius: 3))
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

    var ratePicker: some View {
        Picker("Rate", selection: rateBinding) {
            ForEach(PlayerModel.availableRates, id: \.self) { rate in
                Text(player.rateLabel(rate)).tag(rate)
            }
        }
        .transaction { t in t.animation = .none }
    }

    private var rateBinding: Binding<Float> {
        .init(get: { player.currentRate }, set: { rate in player.currentRate = rate })
    }

    private var pipButton: some View {
        button("PiP", systemImage: "pip") {
            model.startPiP()
        }
    }

    var mediumButtonsBar: some View {
        HStack {
            #if !os(tvOS)
                restartVideoButton
                    .padding(.trailing, 15)

                button("Seek Backward", systemImage: "gobackward.10", size: 30, cornerRadius: 5) {
                    player.backend.seek(relative: .secondsInDefaultTimescale(-10))
                }

                #if os(tvOS)
                .focused($focusedField, equals: .backward)
                #else
                .keyboardShortcut("k", modifiers: [])
                .keyboardShortcut(KeyEquivalent.leftArrow, modifiers: [])
                #endif

            #endif

            Spacer()

            button(
                model.isPlaying ? "Pause" : "Play",
                systemImage: model.isPlaying ? "pause.fill" : "play.fill",
                size: 30, cornerRadius: 5
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

            Spacer()

            #if !os(tvOS)
                button("Seek Forward", systemImage: "goforward.10", size: 30, cornerRadius: 5) {
                    player.backend.seek(relative: .secondsInDefaultTimescale(10))
                }
                #if os(tvOS)
                .focused($focusedField, equals: .forward)
                #else
                .keyboardShortcut("l", modifiers: [])
                .keyboardShortcut(KeyEquivalent.rightArrow, modifiers: [])
                #endif

                advanceToNextItemButton
                    .padding(.leading, 15)
            #endif
        }
        .font(.system(size: 20))
        .padding(.horizontal, 4)
    }

    private var restartVideoButton: some View {
        button("Restart video", systemImage: "backward.end.fill", size: 30, cornerRadius: 5) {
            player.backend.seek(to: 0.0)
        }
    }

    private var advanceToNextItemButton: some View {
        button("Next", systemImage: "forward.fill", size: 30, cornerRadius: 5) {
            player.advanceToNextItem()
        }
        .disabled(player.queue.isEmpty)
    }

    var bottomBar: some View {
        HStack {
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
        .buttonStyle(.plain)
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
        #if os(iOS)
            model.playingFullscreen || verticalSizeClass == .compact
        #else
            model.playingFullscreen
        #endif
    }
}

struct PlayerControls_Previews: PreviewProvider {
    static var previews: some View {
        let model = PlayerControlsModel()
        model.presentingControls = true
        model.currentTime = .secondsInDefaultTimescale(0)
        model.duration = .secondsInDefaultTimescale(120)

        let view = ZStack {
            Color.gray

            PlayerControls(player: PlayerModel())
                .injectFixtureEnvironmentObjects()
                .environmentObject(model)
        }

        return Group {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
                view.previewInterfaceOrientation(.landscapeLeft)
            } else {
                view
            }
        }
    }
}
