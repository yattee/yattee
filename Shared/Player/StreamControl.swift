import SwiftUI

struct StreamControl: View {
    #if os(tvOS)
        var focusedField: FocusState<ControlsOverlay.Field?>.Binding?

        init(focusedField: FocusState<ControlsOverlay.Field?>.Binding?) {
            self.focusedField = focusedField
        }
    #endif

    @ObservedObject private var player = PlayerModel.shared

    var body: some View {
        Group {
            #if !os(tvOS)
                Picker("", selection: $player.streamSelection) {
                    if !availableStreamsByKind.values.isEmpty {
                        let kinds = Array(availableStreamsByKind.keys).sorted { $0 < $1 }

                        ForEach(kinds, id: \.self) { key in
                            ForEach(availableStreamsByKind[key] ?? []) { stream in
                                Text(stream.description)
                                    #if os(macOS)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    #endif
                                    .tag(Stream?.some(stream))
                            }

                            #if os(macOS)
                                if kinds.count > 1 {
                                    Divider()
                                }
                            #endif
                        }
                    }
                }
                .disabled(player.isLoadingAvailableStreams)
                #if os(iOS)
                    .frame(minWidth: 110)
                    .fixedSize(horizontal: true, vertical: true)
                    .disabled(player.isLoadingAvailableStreams)
                #elseif os(macOS)
                    .fixedSize()
                #endif
            #else
                ControlsOverlayButton(focusedField: focusedField!, field: .stream) {
                    Text(player.streamSelection?.shortQuality ?? "loading")
                        .frame(maxWidth: 320)
                }
                .contextMenu {
                    ForEach(streams) { stream in
                        Button(stream.description) { player.streamSelection = stream }
                    }

                    Button("Close", role: .cancel) {}
                }
            #endif
        }
        .transaction { t in t.animation = .none }
        .onChange(of: player.streamSelection) { selection in
            guard let selection else { return }
            player.upgradeToStream(selection)
            player.controls.hideOverlays()
        }
        .frame(alignment: .trailing)
    }

    private var availableStreamsByKind: [Stream.Kind: [Stream]] {
        Dictionary(grouping: streams, by: \.kind!)
    }

    var streams: [Stream] {
        player.availableStreamsSorted.filter { player.backend.canPlay($0) }
    }
}

struct StreamControl_Previews: PreviewProvider {
    static var previews: some View {
        #if os(tvOS)
            StreamControl(focusedField: .none)
                .injectFixtureEnvironmentObjects()
        #else
            StreamControl()
        #endif
    }
}
