import SwiftUI

struct StreamControl: View {
    @Binding var presentingButtonHintAlert: Bool

    @EnvironmentObject<PlayerModel> private var player

    init(presentingButtonHintAlert: Binding<Bool> = .constant(false)) {
        _presentingButtonHintAlert = presentingButtonHintAlert
    }

    var body: some View {
        Group {
            #if !os(tvOS)
                Picker("", selection: $player.streamSelection) {
                    if !availableStreamsByKind.values.isEmpty {
                        let kinds = Array(availableStreamsByKind.keys).sorted { $0 < $1 }

                        ForEach(kinds, id: \.self) { key in
                            ForEach(availableStreamsByKind[key] ?? []) { stream in
                                Text(stream.description).tag(Stream?.some(stream))
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
                #endif
            #else
                Button {
                    presentingButtonHintAlert = true
                } label: {
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
            guard let selection = selection else { return }
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
        StreamControl()
            .injectFixtureEnvironmentObjects()
    }
}
