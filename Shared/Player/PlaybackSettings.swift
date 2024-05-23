import Combine
import Defaults
import SwiftUI

struct PlaybackSettings: View {
    @ObservedObject private var player = PlayerModel.shared
    private var model = PlayerControlsModel.shared

    @State private var contentSize: CGSize = .zero

    @Default(.showMPVPlaybackStats) private var showMPVPlaybackStats
    @Default(.qualityProfiles) private var qualityProfiles

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    #if os(tvOS)
        enum Field: Hashable {
            case qualityProfile
            case stream
            case increaseRate
            case decreaseRate
            case captions
        }

        @FocusState private var focusedField: Field?
        @State private var presentingButtonHintAlert = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        withAnimation(ControlOverlaysModel.animation) {
                            NavigationModel.shared.presentingPlaybackSettings = false
                        }
                    } label: {
                        Label("Close", systemImage: "xmark")
                        #if os(iOS)
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: 50, alignment: .leading)
                        #endif
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()
                    Text("Playback Settings")
                        .font(.headline)
                        .frame(maxWidth: .infinity)

                    Spacer()
                        .frame(maxWidth: 50, alignment: .trailing)
                }

                HStack {
                    controlsHeader("Playback Mode".localized())
                    Spacer()
                    playbackModeControl
                }
                .padding(.vertical, 10)

                if player.activeBackend == .mpv || !player.avPlayerUsesSystemControls {
                    HStack {
                        controlsHeader("Rate".localized())
                        Spacer()
                        HStack(spacing: rateButtonsSpacing) {
                            decreaseRateButton
                            #if os(tvOS)
                            .focused($focusedField, equals: .decreaseRate)
                            #endif
                            rateButton
                            increaseRateButton
                            #if os(tvOS)
                            .focused($focusedField, equals: .increaseRate)
                            #endif
                        }
                    }
                }

                if player.activeBackend == .mpv {
                    HStack {
                        controlsHeader("Captions".localized())
                        Spacer()
                        captionsButton
                        #if os(tvOS)
                        .focused($focusedField, equals: .captions)
                        #endif

                        #if os(iOS)
                        .foregroundColor(.white)
                        #endif
                    }
                }

                HStack {
                    controlsHeader("Quality Profile".localized())
                    Spacer()
                    qualityProfileButton
                    #if os(tvOS)
                    .focused($focusedField, equals: .qualityProfile)
                    #endif
                }

                HStack {
                    controlsHeader("Stream".localized())
                    Spacer()
                    streamButton
                    #if os(tvOS)
                    .focused($focusedField, equals: .stream)
                    #endif
                }

                HStack(spacing: 8) {
                    controlsHeader("Backend".localized())
                    Spacer()
                    backendButtons
                }

                if player.activeBackend == .mpv,
                   showMPVPlaybackStats
                {
                    Section(header: controlsHeader("Statistics".localized()).padding(.top, 15)) {
                        PlaybackStatsView()
                    }
                }
            }
            #if os(iOS)
            .padding(.top, verticalSizeClass == .regular ? 10 : 0)
            .padding(.bottom, 15)
            #else
            .padding(.top)
            #endif
            .padding(.horizontal)
            .overlay(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        contentSize = geometry.size
                    }
                }
            )
        }
        .animation(nil, value: player.activeBackend)
        .frame(alignment: .topLeading)
        .ignoresSafeArea(.all, edges: .bottom)
        .backport
        .playbackSettingsPresentationDetents()
        #if os(macOS)
            .frame(width: 500)
            .frame(minHeight: 350, maxHeight: 450)
        #endif
    }

    private func controlsHeader(_ text: String) -> some View {
        Text(text)
    }

    private var backendButtons: some View {
        ForEach(PlayerBackendType.allCases, id: \.self) { backend in
            backendButton(backend)
                .frame(height: 40)
            #if os(iOS)
                .padding(12)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 4).foregroundColor(player.activeBackend == backend ? Color.accentColor : Color.clear))
                .contentShape(Rectangle())
            #endif
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
                .fontWeight(player.activeBackend == backend ? .bold : .regular)
            #if os(iOS)
                .foregroundColor(player.activeBackend == backend ? .white : .secondary)
            #else
                .foregroundColor(player.activeBackend == backend ? .accentColor : .secondary)
            #endif
        }
        #if os(macOS)
        .buttonStyle(.bordered)
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
            } label: {
                Text(player.rateLabel(player.currentRate))
                    .foregroundColor(.primary)
                    .frame(width: 70)
            }
            .transaction { t in t.animation = .none }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .frame(width: 70, height: 40)
        #else
            Text(player.rateLabel(player.currentRate))
                .frame(minWidth: 120)
        #endif
    }

    var ratePicker: some View {
        Picker("Rate", selection: $player.currentRate) {
            ForEach(player.backend.suggestedPlaybackRates, id: \.self) { rate in
                Text(player.rateLabel(rate)).tag(rate)
            }
        }
        .transaction { t in t.animation = .none }
    }

    private var increaseRateButton: some View {
        let increasedRate = player.backend.suggestedPlaybackRates.first { $0 > player.currentRate }
        return Button {
            if let rate = increasedRate {
                player.currentRate = rate
            }
        } label: {
            Label("Increase rate", systemImage: "plus")
                .foregroundColor(.accentColor)
                .imageScale(.large)
                .labelStyle(.iconOnly)
            #if os(iOS)
                .padding(12)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1))
                .contentShape(Rectangle())
            #endif
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        #endif
        .disabled(increasedRate.isNil)
    }

    private var decreaseRateButton: some View {
        let decreasedRate = player.backend.suggestedPlaybackRates.last { $0 < player.currentRate }

        return Button {
            if let rate = decreasedRate {
                player.currentRate = rate
            }
        } label: {
            Label("Decrease rate", systemImage: "minus")
                .foregroundColor(.accentColor)
                .imageScale(.large)
                .labelStyle(.iconOnly)
            #if os(iOS)
                .padding(12)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1))
                .contentShape(Rectangle())
            #endif
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        #elseif os(iOS)
        #endif
            .disabled(decreasedRate.isNil)
    }

    private var rateButtonsSpacing: Double {
        #if os(tvOS)
            10
        #else
            8
        #endif
    }

    @ViewBuilder var playbackModeControl: some View {
        #if os(tvOS)
            Button {
                player.playbackMode = player.playbackMode.next()
            } label: {
                Label(player.playbackMode.description.localized(), systemImage: player.playbackMode.systemImage)
                    .transaction { t in t.animation = nil }
                    .frame(minWidth: 350)
            }
        #elseif os(macOS)
            playbackModePicker
                .modifier(SettingsPickerModifier())
            #if os(macOS)
                .frame(maxWidth: 150)
            #endif
        #else
            Menu {
                playbackModePicker
            } label: {
                Label(player.playbackMode.description.localized(), systemImage: player.playbackMode.systemImage)
            }
            .transaction { t in t.animation = .none }
        #endif
    }

    var playbackModePicker: some View {
        Picker("Playback Mode", selection: $player.playbackMode) {
            ForEach(PlayerModel.PlaybackMode.allCases, id: \.rawValue) { mode in
                Label(mode.description.localized(), systemImage: mode.systemImage).tag(mode)
            }
        }
        .labelsHidden()
    }

    @ViewBuilder private var qualityProfileButton: some View {
        #if os(macOS)
            qualityProfilePicker
                .labelsHidden()
                .frame(maxWidth: 300)
        #elseif os(iOS)
            Menu {
                qualityProfilePicker
            } label: {
                Text(player.qualityProfileSelection?.description ?? "Automatic".localized())
                    .frame(maxWidth: 240, alignment: .trailing)
            }
            .transaction { t in t.animation = .none }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .frame(maxWidth: 240, alignment: .trailing)
            .frame(height: 40)
        #else
            ControlsOverlayButton(focusedField: $focusedField, field: .qualityProfile) {
                Text(player.qualityProfileSelection?.description ?? "Automatic".localized())
                    .lineLimit(1)
                    .frame(maxWidth: 320)
            }
            .contextMenu {
                Button("Automatic") { player.qualityProfileSelection = nil }

                ForEach(qualityProfiles) { qualityProfile in
                    Button {
                        player.qualityProfileSelection = qualityProfile
                    } label: {
                        Text(qualityProfile.description)
                    }

                    Button("Cancel", role: .cancel) {}
                }
            }
        #endif
    }

    private var qualityProfilePicker: some View {
        Picker("Quality Profile", selection: $player.qualityProfileSelection) {
            Text("Automatic").tag(QualityProfile?.none)
            ForEach(qualityProfiles) { qualityProfile in
                Text(qualityProfile.description).tag(qualityProfile as QualityProfile?)
            }
        }
        .transaction { t in t.animation = .none }
    }

    @ViewBuilder private var streamButton: some View {
        #if os(macOS)
            StreamControl()
                .labelsHidden()
                .frame(maxWidth: 300)
        #elseif os(iOS)
            Menu {
                StreamControl()
            } label: {
                Text(player.streamSelection?.resolutionAndFormat ?? "loading...")
                    .frame(width: 140, height: 40, alignment: .trailing)
                    .foregroundColor(player.streamSelection == nil ? .secondary : .accentColor)
            }
            .transaction { t in t.animation = .none }
            .buttonStyle(.plain)
            .frame(height: 40, alignment: .trailing)
        #else
            StreamControl(focusedField: $focusedField)
        #endif
    }

    @ViewBuilder private var captionsButton: some View {
        let videoCaptions = player.currentVideo?.captions
        #if os(macOS)
            captionsPicker
                .labelsHidden()
                .frame(maxWidth: 300)
        #elseif os(iOS)
            Menu {
                if videoCaptions?.isEmpty == false {
                    captionsPicker
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                    if let captions = player.captions,
                       let language = LanguageCodes(rawValue: captions.code)
                    {
                        Text("\(language.description.capitalized) (\(language.rawValue))")
                            .foregroundColor(.accentColor)
                    } else {
                        if videoCaptions?.isEmpty == true {
                            Text("Not available")
                        } else {
                            Text("Disabled")
                        }
                    }
                }
                .frame(alignment: .trailing)
                .frame(height: 40)
                .disabled(videoCaptions?.isEmpty == true)
            }
            .transaction { t in t.animation = .none }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        #else
            ControlsOverlayButton(focusedField: $focusedField, field: .captions) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                    if let captions = captionsBinding.wrappedValue {
                        Text(captions.code)
                    }
                }
                .frame(maxWidth: 320)
            }
            .contextMenu {
                Button("Disabled") { captionsBinding.wrappedValue = nil }

                ForEach(player.currentVideo?.captions ?? []) { caption in
                    Button(caption.description) { captionsBinding.wrappedValue = caption }
                }
                Button("Cancel", role: .cancel) {}
            }

        #endif
    }

    @ViewBuilder private var captionsPicker: some View {
        let captions = player.currentVideo?.captions ?? []
        Picker("Captions".localized(), selection: $player.captions) {
            if captions.isEmpty {
                Text("Not available").tag(Captions?.none)
            } else {
                Text("Disabled").tag(Captions?.none)
                ForEach(captions) { caption in
                    Text(caption.description).tag(Optional(caption))
                }
            }
        }
        .disabled(captions.isEmpty)
    }
}

struct PlaybackSettings_Previews: PreviewProvider {
    static var previews: some View {
        PlaybackSettings()
    }
}
