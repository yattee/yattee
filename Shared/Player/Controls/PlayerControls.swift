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
        VStack {
            ZStack(alignment: .bottom) {
                VStack(alignment: .trailing, spacing: 4) {
                    #if !os(tvOS)
                        buttonsBar

                        HStack(spacing: 4) {
                            qualityButton
                            backendButton
                        }
                    #else
                        Text(player.stream?.description ?? "")
                    #endif

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
            .padding(.top, 4)
            .padding(.horizontal, 4)
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
                .background(controlsBackground)
        #endif
                .environment(\.colorScheme, .dark)
    }

    @ViewBuilder var controlsBackground: some View {
        if player.musicMode,
           let item = self.player.currentItem,
           let url = thumbnails.best(item.video)
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
        HStack {
            #if !os(tvOS)
                #if os(iOS)
                    hidePlayerButton
                #endif

                fullscreenButton

                #if os(iOS)
                    pipButton
                #endif

                Spacer()

                rateButton

                musicModeButton

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

    @ViewBuilder private var qualityButton: some View {
        #if os(macOS)
            StreamControl()
                .labelsHidden()
                .frame(maxWidth: 300)
        #elseif os(iOS)
            Menu {
                StreamControl()
                    .frame(width: 45, height: 30)
                #if os(iOS)
                    .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
                #endif
                    .mask(RoundedRectangle(cornerRadius: 3))
            } label: {
                Text(player.streamSelection?.shortQuality ?? "loading")
                    .frame(width: 140, height: 30)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .frame(width: 140, height: 30)
            #if os(macOS)
                .background(VisualEffectBlur(material: .hudWindow))
            #elseif os(iOS)
                .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
            #endif
                .mask(RoundedRectangle(cornerRadius: 3))
        #endif
    }

    @ViewBuilder private var backendButton: some View {
        button(player.activeBackend.label, width: 100) {
            player.saveTime {
                player.changeActiveBackend(from: player.activeBackend, to: player.activeBackend.next())
                model.resetTimer()
            }
        }
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
        button("Music Mode", systemImage: "music.note", active: player.musicMode, action: player.toggleMusicMode)
            .disabled(player.activeBackend == .appleAVPlayer)
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
        systemImage: String? = nil,
        size: Double = 30,
        width: Double? = nil,
        height: Double? = nil,
        cornerRadius: Double = 3,
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
        .buttonStyle(.plain)
        .foregroundColor(active ? .accentColor : .primary)
        .frame(width: width ?? size, height: height ?? size)
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

        return ZStack {
            Color.gray

            PlayerControls(player: PlayerModel(), thumbnails: ThumbnailsModel())
                .injectFixtureEnvironmentObjects()
                .environmentObject(model)
        }
    }
}
