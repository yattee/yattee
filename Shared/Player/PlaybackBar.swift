import Foundation
import SwiftUI

struct PlaybackBar: View {
    let video: Video

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playbackState: PlaybackState

    var body: some View {
        HStack {
            closeButton
                .frame(width: 60, alignment: .leading)

            Text(playbackFinishAtString)
                .foregroundColor(.gray)
                .font(.caption2)
                .frame(minWidth: 60, maxWidth: .infinity)

            VStack {
                if playbackState.stream != nil {
                    Text(currentStreamString)
                } else {
                    Image(systemName: "bolt.horizontal.fill")
                }
            }
            .foregroundColor(.gray)
            .font(.caption2)
            .frame(width: 60, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: true)
        }
        .padding(4)
        .background(.black)
    }

    var currentStreamString: String {
        playbackState.stream != nil ? "\(playbackState.stream!.resolution.height)p" : ""
    }

    var playbackFinishAtString: String {
        guard playbackState.time != nil else {
            return "loading..."
        }

        let remainingSeconds = video.length - playbackState.time!.seconds

        if remainingSeconds < 60 {
            return "less than a minute"
        }

        let timeFinishAt = Date.now.addingTimeInterval(remainingSeconds)
        let timeFinishAtString = timeFinishAt.formatted(date: .omitted, time: .shortened)

        return "finishes at \(timeFinishAtString)"
    }

    var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "chevron.down.circle.fill")
        }
        .accessibilityLabel(Text("Close"))
        .buttonStyle(.borderless)
        .foregroundColor(.gray)
        .keyboardShortcut(.cancelAction)
    }
}
