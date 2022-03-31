import Defaults
import Foundation
import SwiftUI

struct PlaybackBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.inNavigationView) private var inNavigationView

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        HStack {
            #if !os(macOS)
                closeButton
            #endif

            if player.currentItem != nil {
                HStack {
                    Text(playbackStatus)
                    Text("•")
                    rateMenu
                }
                .font(.caption2)
                #if os(macOS)
                    .padding(.leading, 4)
                #endif

                Spacer()

                HStack(spacing: 4) {
                    if !player.lastSkipped.isNil {
                        restoreLastSkippedSegmentButton
                    }
                    if player.live {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    } else if player.isLoadingAvailableStreams || player.isLoadingStream {
                        Image(systemName: "bolt.horizontal.fill")
                    } else if !player.playerError.isNil {
                        Button {
                            player.presentingErrorDetails = true
                        } label: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    streamControl
                        .disabled(player.isLoadingAvailableStreams)
                        .frame(alignment: .trailing)
                        .onChange(of: player.streamSelection) { selection in
                            guard !selection.isNil else {
                                return
                            }

                            player.upgradeToStream(selection!)
                        }
                    #if os(macOS)
                        .frame(maxWidth: 180)
                    #endif
                }
                .transaction { t in t.animation = .none }
                .font(.caption2)
            } else {
                Spacer()
            }
        }
        .foregroundColor(colorScheme == .dark ? .gray : .black)
        .alert(isPresented: $player.presentingErrorDetails) {
            Alert(
                title: Text("Error"),
                message: Text(player.playerError?.localizedDescription ?? "")
            )
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 20)
        .padding(4)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    private var closeButton: some View {
        Button {
            player.hide()
        } label: {
            Label(
                "Close",
                systemImage: inNavigationView ? "chevron.backward.circle.fill" : "chevron.down.circle.fill"
            )
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel(Text("Close"))
        .buttonStyle(.borderless)
        .foregroundColor(.gray)
        .keyboardShortcut(.cancelAction)
    }

    private var playbackStatus: String {
        if player.live {
            return "LIVE"
        }

        guard !player.isLoadingVideo else {
            return "loading..."
        }

        guard let video = player.currentVideo else {
            return ""
        }

        let videoLengthAtRate = video.length / Double(player.currentRate)
        let remainingSeconds = videoLengthAtRate - player.time!.seconds

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

    private var rateMenu: some View {
        #if os(macOS)
            ratePicker
                .labelsHidden()
                .frame(maxWidth: 70)
        #else
            Menu {
                ratePicker
            } label: {
                Text(player.rateLabel(player.currentRate))
            }

        #endif
    }

    private var ratePicker: some View {
        Picker("", selection: $player.currentRate) {
            ForEach(PlayerModel.availableRates, id: \.self) { rate in
                Text(player.rateLabel(rate)).tag(rate)
            }
        }
    }

    private var restoreLastSkippedSegmentButton: some View {
        HStack(spacing: 4) {
            Button {
                player.restoreLastSkippedSegment()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.left.circle")
                    Text(player.lastSkipped!.title())
                }
            }
            .buttonStyle(.plain)

            Text("•")
        }
    }

    private var streamControl: some View {
        #if os(macOS)
            Picker("", selection: $player.streamSelection) {
                ForEach(InstancesModel.all) { instance in
                    let instanceStreams = availableStreamsForInstance(instance)
                    if !instanceStreams.values.isEmpty {
                        let kinds = Array(instanceStreams.keys).sorted { $0 < $1 }

                        Section(header: Text(instance.longDescription)) {
                            ForEach(kinds, id: \.self) { key in
                                ForEach(instanceStreams[key] ?? []) { stream in
                                    Text(stream.quality).tag(Stream?.some(stream))
                                }

                                if kinds.count > 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        #else
            Menu {
                ForEach(InstancesModel.all) { instance in
                    let instanceStreams = availableStreamsForInstance(instance)
                    if !instanceStreams.values.isEmpty {
                        let kinds = Array(instanceStreams.keys).sorted { $0 < $1 }
                        Picker("", selection: $player.streamSelection) {
                            ForEach(kinds, id: \.self) { key in
                                ForEach(instanceStreams[key] ?? []) { stream in
                                    Text(stream.description).tag(Stream?.some(stream))
                                }

                                if kinds.count > 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(player.streamSelection?.quality ?? "")
            }
        #endif
    }

    private func availableStreamsForInstance(_ instance: Instance) -> [Stream.Kind: [Stream]] {
        let streams = player.availableStreamsSorted.filter { $0.instance == instance }

        return Dictionary(grouping: streams, by: \.kind!)
    }
}

struct PlaybackBar_Previews: PreviewProvider {
    static var previews: some View {
        PlaybackBar()
            .injectFixtureEnvironmentObjects()
    }
}
