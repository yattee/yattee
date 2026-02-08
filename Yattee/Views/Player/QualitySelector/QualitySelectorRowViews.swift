//
//  QualitySelectorRowViews.swift
//  Yattee
//
//  Row views for stream selection in quality selector.
//

import SwiftUI

// MARK: - Adaptive Stream Row

/// Row view for HLS/DASH adaptive streams.
struct AdaptiveStreamRowView: View {
    let stream: Stream
    let isSelected: Bool
    let onTap: () -> Void

    private var format: StreamFormat {
        StreamFormat.detect(from: stream)
    }

    /// Quality label from resolution/fps if available
    private var qualityLabel: String? {
        if let resolution = stream.resolution {
            var label = resolution.description
            if let fps = stream.fps, fps > 30 {
                label += " \(fps)fps"
            }
            return label
        }
        return nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(format == .hls ? "HLS" : "DASH")
                            .font(.headline)

                        // Show quality badge when available
                        if let quality = qualityLabel {
                            Text(quality)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(format == .hls ? "Apple HLS" : "MPEG-DASH (Best for MPV)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Video Stream Row

/// Row view for video streams (muxed or video-only).
struct VideoStreamRowView: View {
    let stream: Stream
    let isSelected: Bool
    let isPreferredQuality: Bool
    let isDownloaded: Bool
    let showAdvancedDetails: Bool
    let requiresSoftwareDecode: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    if showAdvancedDetails {
                        detailsRow
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .frame(minHeight: showAdvancedDetails ? nil : 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 6) {
            if isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if isPreferredQuality {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text(stream.qualityLabel)
                .font(.headline)

            if !stream.isMuxed && requiresSoftwareDecode {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .help(String(localized: "player.quality.softwareDecode.warning"))
            }

            if showAdvancedDetails {
                codecBadge
            }
        }
    }

    @ViewBuilder
    private var codecBadge: some View {
        if stream.isMuxed {
            Text("STREAM")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        } else if let codec = stream.videoCodec {
            let isSoftware = requiresSoftwareDecode
            Text(formatCodec(codec))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSoftware ? Color.yellow.opacity(0.2) : codecColor(codec).opacity(0.2))
                .foregroundStyle(isSoftware ? .yellow : codecColor(codec))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var detailsRow: some View {
        let details = formatStreamDetails(bitrate: stream.bitrate, fileSize: stream.formattedFileSize)
        if stream.isMuxed || !details.isEmpty {
            HStack(spacing: 4) {
                if stream.isMuxed {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatCodec(_ codec: String) -> String {
        let lowercased = codec.lowercased()
        if lowercased.contains("avc") || lowercased.contains("h264") {
            return "H.264"
        } else if lowercased.contains("hev") || lowercased.contains("h265") || lowercased.contains("hevc") {
            return "HEVC"
        } else if lowercased.contains("vp9") || lowercased.contains("vp09") {
            return "VP9"
        } else if lowercased.contains("av1") || lowercased.contains("av01") {
            return "AV1"
        }
        return codec.uppercased()
    }

    private func codecColor(_ codec: String) -> Color {
        let lowercased = codec.lowercased()
        if lowercased.contains("av1") || lowercased.contains("av01") {
            return .blue
        } else if lowercased.contains("vp9") || lowercased.contains("vp09") {
            return .orange
        } else if lowercased.contains("avc") || lowercased.contains("h264") {
            return .red
        } else if lowercased.contains("hev") || lowercased.contains("h265") || lowercased.contains("hevc") {
            return .green
        }
        return .gray
    }

    private func formatStreamDetails(bitrate: Int?, fileSize: String?) -> String {
        var parts: [String] = []
        if let bitrate {
            parts.append(formatBitrate(bitrate))
        }
        if let fileSize {
            parts.append(fileSize)
        }
        return parts.joined(separator: " · ")
    }

    private func formatBitrate(_ bitrate: Int) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        } else {
            return "\(bitrate / 1000) kbps"
        }
    }
}

// MARK: - Audio Stream Row

/// Row view for audio-only streams.
struct AudioStreamRowView: View {
    let stream: Stream
    let isSelected: Bool
    let isPreferred: Bool
    let showAdvancedDetails: Bool
    let trackInfo: AudioTrackInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    if showAdvancedDetails {
                        detailsRow
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .frame(minHeight: showAdvancedDetails ? nil : 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 6) {
            if isPreferred {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text(trackInfo.language)
                .font(.headline)

            if showAdvancedDetails, let codec = stream.audioCodec {
                Text(codec.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var detailsRow: some View {
        let details = formatAudioDetails(
            trackType: trackInfo.trackType,
            bitrate: stream.bitrate,
            fileSize: stream.formattedFileSize
        )
        if !details.isEmpty {
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatAudioDetails(trackType: String?, bitrate: Int?, fileSize: String?) -> String {
        var parts: [String] = []
        if let trackType {
            parts.append(trackType)
        }
        if let bitrate {
            parts.append(formatBitrate(bitrate))
        }
        if let fileSize {
            parts.append(fileSize)
        }
        return parts.joined(separator: " · ")
    }

    private func formatBitrate(_ bitrate: Int) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        } else {
            return "\(bitrate / 1000) kbps"
        }
    }
}

// MARK: - Caption Row

/// Row view for caption/subtitle selection.
struct CaptionRowView: View {
    let caption: Caption?
    let isSelected: Bool
    let isPreferred: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 6) {
            if isPreferred {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text(caption?.displayName ?? String(localized: "stream.subtitles.off"))
                .font(.headline)

            if let caption, caption.isAutoGenerated {
                Text("AUTO")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Previews

#Preview("Adaptive Stream Row") {
    VStack(spacing: 0) {
        AdaptiveStreamRowView(
            stream: .hlsPreview,
            isSelected: true,
            onTap: {}
        )
        .padding()

        Divider()

        AdaptiveStreamRowView(
            stream: .hlsNoQualityPreview,
            isSelected: false,
            onTap: {}
        )
        .padding()
    }
    .cardBackground()
    .padding()
}

#Preview("Video Stream Row") {
    VStack(spacing: 0) {
        VideoStreamRowView(
            stream: .preview,
            isSelected: true,
            isPreferredQuality: true,
            isDownloaded: false,
            showAdvancedDetails: true,
            requiresSoftwareDecode: false,
            onTap: {}
        )
        .padding()

        Divider()

        VideoStreamRowView(
            stream: .videoOnlyPreview,
            isSelected: false,
            isPreferredQuality: false,
            isDownloaded: false,
            showAdvancedDetails: true,
            requiresSoftwareDecode: true,
            onTap: {}
        )
        .padding()
    }
    .cardBackground()
    .padding()
}

#Preview("Audio Stream Row") {
    VStack(spacing: 0) {
        AudioStreamRowView(
            stream: .audioPreview,
            isSelected: true,
            isPreferred: true,
            showAdvancedDetails: true,
            trackInfo: AudioTrackInfo(language: "English", trackType: "ORIGINAL"),
            onTap: {}
        )
        .padding()
    }
    .cardBackground()
    .padding()
}

#Preview("Caption Row") {
    VStack(spacing: 0) {
        CaptionRowView(
            caption: nil,
            isSelected: true,
            isPreferred: false,
            onTap: {}
        )
        .padding()

        Divider()

        CaptionRowView(
            caption: .preview,
            isSelected: false,
            isPreferred: true,
            onTap: {}
        )
        .padding()

        Divider()

        CaptionRowView(
            caption: .autoGeneratedPreview,
            isSelected: false,
            isPreferred: false,
            onTap: {}
        )
        .padding()
    }
    .cardBackground()
    .padding()
}
