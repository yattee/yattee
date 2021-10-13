import Foundation
import SwiftUI

struct PlaybackBar: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inNavigationView) private var inNavigationView

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        HStack {
            closeButton
                .frame(width: 80, alignment: .leading)

            if player.currentItem != nil {
                Text(playbackStatus)
                    .foregroundColor(.gray)
                    .font(.caption2)
                    .frame(minWidth: 130, maxWidth: .infinity)

                VStack {
                    if player.stream != nil {
                        Text(currentStreamString)
                    } else {
                        if player.currentVideo!.live {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                        }
                    }
                }
                .foregroundColor(.gray)
                .font(.caption2)
                .frame(width: 80, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: true)
            } else {
                Spacer()
            }
        }
        .padding(4)
        .background(.black)
    }

    var currentStreamString: String {
        "\(player.stream!.resolution.height)p"
    }

    var playbackStatus: String {
        if player.live {
            return "LIVE"
        }

        guard player.time != nil, player.time!.isValid else {
            return "loading..."
        }

        let remainingSeconds = player.currentVideo!.length - player.time!.seconds

        if remainingSeconds < 60 {
            return "less than a minute"
        }

        let timeFinishAt = Date.now.addingTimeInterval(remainingSeconds)
        let timeFinishAtString = timeFinishAt.formatted(date: .omitted, time: .shortened)

        return "ends at \(timeFinishAtString)"
    }

    var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Label("Close", systemImage: inNavigationView ? "chevron.backward.circle.fill" : "chevron.down.circle.fill")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel(Text("Close"))
        .buttonStyle(.borderless)
        .foregroundColor(.gray)
        .keyboardShortcut(.cancelAction)
    }
}

struct PlaybackBar_Previews: PreviewProvider {
    static var previews: some View {
        PlaybackBar()
            .injectFixtureEnvironmentObjects()
    }
}
