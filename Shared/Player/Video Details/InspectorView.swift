import SwiftUI

struct InspectorView: View {
    var video: Video?

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                if let video {
                    Group {
                        if player.activeBackend == .mpv, player.mpvBackend.videoFormat != "unknown" {
                            videoDetailGroupHeading("Video")

                            videoDetailRow("Format", value: player.mpvBackend.videoFormat)
                            videoDetailRow("Codec", value: player.mpvBackend.videoCodec)
                            videoDetailRow("Hardware Decoder", value: player.mpvBackend.hwDecoder)
                            videoDetailRow("Driver", value: player.mpvBackend.currentVo)
                            videoDetailRow("Size", value: player.formattedSize)
                            videoDetailRow("FPS", value: player.mpvBackend.formattedOutputFps)
                        } else if player.activeBackend == .appleAVPlayer, let width = player.backend.videoWidth, width > 0 {
                            videoDetailGroupHeading("Video")
                            videoDetailRow("Size", value: player.formattedSize)
                        }
                    }

                    if player.activeBackend == .mpv, player.mpvBackend.audioFormat != "unknown" {
                        Group {
                            videoDetailGroupHeading("Audio")
                            videoDetailRow("Format", value: player.mpvBackend.audioFormat)
                            videoDetailRow("Codec", value: player.mpvBackend.audioCodec)
                            videoDetailRow("Driver", value: player.mpvBackend.currentAo)
                            videoDetailRow("Channels", value: player.mpvBackend.audioChannels)
                            videoDetailRow("Sample Rate", value: player.mpvBackend.audioSampleRate)
                        }
                    }

                    if video.localStream != nil || video.localStreamFileExtension != nil {
                        videoDetailGroupHeading("File")
                    }

                    if let fileExtension = video.localStreamFileExtension {
                        videoDetailRow("File Extension", value: fileExtension)
                    }

                    if let url = video.localStream?.localURL, video.localStreamIsRemoteURL {
                        videoDetailRow("URL", value: url.absoluteString)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder func videoDetailGroupHeading(_ heading: String) -> some View {
        Text(heading.uppercased())
            .font(.footnote)
            .foregroundColor(.secondary)
    }

    @ViewBuilder func videoDetailRow(_ detail: String, value: String) -> some View {
        HStack {
            Text(detail)
                .foregroundColor(.secondary)
            Spacer()
            let value = Text(value)
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
    }
}
