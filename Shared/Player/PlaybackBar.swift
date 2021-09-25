import Foundation
import SwiftUI

struct PlaybackBar: View {
    let video: Video

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playback: PlaybackModel

    var body: some View {
        HStack {
            closeButton
                .frame(width: 60, alignment: .leading)

            Text(playbackStatus)
                .foregroundColor(.gray)
                .font(.caption2)
                .frame(minWidth: 60, maxWidth: .infinity)

            VStack {
                if playback.stream != nil {
                    Text(currentStreamString)
                } else {
                    if video.live {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
                    }
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
        playback.stream != nil ? "\(playback.stream!.resolution.height)p" : ""
    }

    var playbackStatus: String {
        guard playback.time != nil else {
            if playback.live {
                return "LIVE"
            } else {
                return "loading..."
            }
        }

        let remainingSeconds = video.length - playback.time!.seconds

        if remainingSeconds < 60 {
            return "less than a minute"
        }

        let timeFinishAt = Date.now.addingTimeInterval(remainingSeconds)
        let timeFinishAtString = timeFinishAt.formatted(date: .omitted, time: .shortened)

        return "finishes at \(timeFinishAtString)"
    }

    var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark.circle.fill")
        }
        .accessibilityLabel(Text("Close"))
        .buttonStyle(.borderless)
        .foregroundColor(.gray)
        .keyboardShortcut(.cancelAction)
    }
}
