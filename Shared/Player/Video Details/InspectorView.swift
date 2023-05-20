import SwiftUI

struct InspectorView: View {
    var video: Video?

    @ObservedObject private var player = PlayerModel.shared

    var body: some View {
        Section(header: header) {
            VStack(alignment: .leading, spacing: 12) {
                if let video {
                    VStack(spacing: 4) {
                        if player.activeBackend == .mpv, player.mpvBackend.videoFormat != "unknown" {
                            videoDetailGroupHeading("Video", image: "film")

                            videoDetailRow("Format", value: player.mpvBackend.videoFormat)
                            videoDetailRow("Codec", value: player.mpvBackend.videoCodec)
                            videoDetailRow("Hardware decoder", value: player.mpvBackend.hwDecoder)
                            videoDetailRow("Driver", value: player.mpvBackend.currentVo)
                            videoDetailRow("Size", value: player.formattedSize)
                            videoDetailRow("FPS", value: player.mpvBackend.formattedOutputFps)
                        } else if player.activeBackend == .appleAVPlayer, let width = player.backend.videoWidth, width > 0 {
                            videoDetailGroupHeading("Video")
                            videoDetailRow("Size", value: player.formattedSize)
                        }
                    }

                    if player.activeBackend == .mpv, player.mpvBackend.audioFormat != "unknown" {
                        VStack(spacing: 4) {
                            videoDetailGroupHeading("Audio", image: "music.note")
                            videoDetailRow("Format", value: player.mpvBackend.audioFormat)
                            videoDetailRow("Codec", value: player.mpvBackend.audioCodec)
                            videoDetailRow("Driver", value: player.mpvBackend.currentAo)
                            videoDetailRow("Channels", value: player.mpvBackend.audioChannels)
                            videoDetailRow("Sample Rate", value: player.mpvBackend.audioSampleRate)
                        }
                    }

                    VStack(spacing: 4) {
                        if video.localStream != nil || video.localStreamFileExtension != nil {
                            videoDetailGroupHeading("File", image: "doc")
                        }

                        if let fileExtension = video.localStreamFileExtension {
                            videoDetailRow("File Extension", value: fileExtension)
                        }

                        if let url = video.localStream?.localURL, video.localStreamIsRemoteURL {
                            videoDetailRow("URL", value: url.absoluteString)
                        }
                    }
                } else {
                    NoCommentsView(text: "Not playing", systemImage: "stop.circle.fill")
                }
            }
        }
    }

    var header: some View {
        Text("Inspector".localized())
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func videoDetailGroupHeading(_ heading: String, image systemName: String? = nil) -> some View {
        HStack {
            if let systemName {
                Image(systemName: systemName)
            }
            Text(heading.localized().uppercased())
                .font(.footnote)
        }
        .foregroundColor(.secondary)
    }

    @ViewBuilder func videoDetailRow(_ detail: String, value: String) -> some View {
        HStack {
            Text(detail.localized())
                .foregroundColor(.secondary)
            Spacer()
            let value = Text(value).lineLimit(1)
            if #available(iOS 15.0, macOS 12.0, *) {
                value
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
            } else {
                value
            }
        }
        .font(.caption)
    }
}

struct InspectorView_Previews: PreviewProvider {
    static var previews: some View {
        InspectorView(video: .fixture)
            .injectFixtureEnvironmentObjects()
    }
}
