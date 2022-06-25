import Defaults
import SwiftUI

struct ControlsOverlay: View {
    @EnvironmentObject<NetworkStateModel> private var networkState
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<PlayerControlsModel> private var model

    @Default(.showMPVPlaybackStats) private var showMPVPlaybackStats

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                backendButtons
            }
            qualityButton
            HStack {
                decreaseRateButton
                rateButton
                increaseRateButton
            }
            #if os(iOS)
            .foregroundColor(.white)
            #endif

            if player.activeBackend == .mpv,
               showMPVPlaybackStats
            {
                mpvPlaybackStats
            }
        }
    }

    private var backendButtons: some View {
        ForEach(PlayerBackendType.allCases, id: \.self) { backend in
            backendButton(backend)
        }
    }

    private func backendButton(_ backend: PlayerBackendType) -> some View {
        Button {
            player.saveTime {
                player.changeActiveBackend(from: player.activeBackend, to: backend)
                model.resetTimer()
            }
        } label: {
            Text(backend.label)
                .padding(6)
                .foregroundColor(player.activeBackend == backend ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var increaseRateButton: some View {
        let increasedRate = PlayerModel.availableRates.first { $0 > player.currentRate }
        return Button {
            if let rate = increasedRate {
                player.currentRate = rate
            }
        } label: {
            Label("Increase rate", systemImage: "plus")
                .labelStyle(.iconOnly)
                .padding(8)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        #else
        .modifier(ControlBackgroundModifier())
        .clipShape(RoundedRectangle(cornerRadius: 4))
        #endif
        .disabled(increasedRate.isNil)
    }

    private var decreaseRateButton: some View {
        let decreasedRate = PlayerModel.availableRates.last { $0 < player.currentRate }

        return Button {
            if let rate = decreasedRate {
                player.currentRate = rate
            }
        } label: {
            Label("Decrease rate", systemImage: "minus")
                .labelStyle(.iconOnly)
                .padding(8)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        #else
        .modifier(ControlBackgroundModifier())
        .clipShape(RoundedRectangle(cornerRadius: 4))
        #endif
        .disabled(decreasedRate.isNil)
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
            .transaction { t in t.animation = .none }

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

    @ViewBuilder private var rateButton: some View {
        #if os(macOS)
            ratePicker
                .labelsHidden()
                .frame(maxWidth: 100)
        #elseif os(iOS)
            Menu {
                ratePicker
                    .frame(width: 100, height: 30)
                    .mask(RoundedRectangle(cornerRadius: 3))
            } label: {
                Text(player.rateLabel(player.currentRate))
                    .foregroundColor(.primary)
                    .frame(width: 80)
            }
            .transaction { t in t.animation = .none }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .frame(width: 100, height: 30)
            .modifier(ControlBackgroundModifier())
            .mask(RoundedRectangle(cornerRadius: 3))
        #endif
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

    var mpvPlaybackStats: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text("hw decoder: \(player.mpvBackend.hwDecoder)")
                Text("dropped: \(player.mpvBackend.frameDropCount)")
                Text("video: \(String(format: "%.2ffps", player.mpvBackend.outputFps))")
                Text("buffering: \(String(format: "%.0f%%", networkState.bufferingState))")
                Text("cache: \(String(format: "%.2fs", player.mpvBackend.cacheDuration))")
            }
            .mask(RoundedRectangle(cornerRadius: 3))
        }
        #if !os(tvOS)
        .font(.system(size: 9))
        #endif
    }
}

struct ControlsOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ControlsOverlay()
            .environmentObject(PlayerModel())
            .environmentObject(PlayerControlsModel())
    }
}
