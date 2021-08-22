import Foundation
import SwiftUI

struct PlaybackBar: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var playbackState: PlaybackState
    let video: Video

    var body: some View {
        HStack {
            closeButton
                .frame(minWidth: 0, maxWidth: 60, alignment: .leading)

            Text(playbackFinishAtString)
                .foregroundColor(.gray)
                .font(.caption2)
                .frame(minWidth: 0, maxWidth: .infinity)

            Text(currentStreamString)
                .foregroundColor(.gray)
                .font(.caption2)
                .frame(minWidth: 0, maxWidth: 60, alignment: .trailing)
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

        let timeFinishAt = Date.now.addingTimeInterval(remainingSeconds)
        let timeFinishAtString = timeFinishAt.formatted(date: .omitted, time: .shortened)

        return "finishes at \(timeFinishAtString)"
    }

    var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "chevron.down.circle.fill")
        }
        .accessibilityLabel(Text("Close"))
        .buttonStyle(BorderlessButtonStyle())
        .foregroundColor(.gray)
        .keyboardShortcut(.cancelAction)
    }
}
