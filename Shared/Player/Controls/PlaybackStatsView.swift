import SwiftUI

struct PlaybackStatsView: View {
    @ObservedObject private var networkState = NetworkStateModel.shared

    private var player: PlayerModel { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mpvPlaybackStatRow("Hardware decoder".localized(), player.mpvBackend.hwDecoder)
            mpvPlaybackStatRow("Dropped frames".localized(), String(player.mpvBackend.frameDropCount))
            mpvPlaybackStatRow("Stream FPS".localized(), player.mpvBackend.formattedOutputFps)
            mpvPlaybackStatRow("Cached time".localized(), String(format: "%.2fs", networkState.cacheDuration))
        }
        .padding(.top, 2)
        #if os(tvOS)
            .font(.system(size: 20))
        #else
            .font(.system(size: 11))
        #endif
    }

    func mpvPlaybackStatRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

struct PlaybackStatsView_Previews: PreviewProvider {
    static var previews: some View {
        PlaybackStatsView()
    }
}
