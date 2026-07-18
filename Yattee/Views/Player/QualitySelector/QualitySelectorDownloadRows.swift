//
//  QualitySelectorDownloadRows.swift
//  Yattee
//
//  Row views for downloaded content in quality selector.
//

import SwiftUI

// MARK: - Downloaded Video Row

/// Row view for downloaded video - displays download info (not tappable).
struct DownloadedVideoRowView: View {
    let download: Download
    let showAdvancedDetails: Bool

    /// Whether this is a muxed download (has embedded audio).
    private var isMuxed: Bool {
        download.localAudioPath == nil
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                titleRow
                if showAdvancedDetails {
                    detailsRow
                }
            }

            Spacer()
        }
        .frame(minHeight: showAdvancedDetails ? nil : 36)
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

            Text(download.quality)
                .font(.headline)

            if showAdvancedDetails {
                codecBadge
            }
        }
    }

    @ViewBuilder
    private var codecBadge: some View {
        if isMuxed {
            Text(String(localized: "stream.badge.stream"))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        } else if let codec = download.videoCodec {
            Text(formatCodec(codec))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(codecColor(codec).opacity(0.2))
                .foregroundStyle(codecColor(codec))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var detailsRow: some View {
        let fileSize: String? = download.videoTotalBytes > 0 ? formatFileSize(download.videoTotalBytes) : nil
        let details = formatStreamDetails(bitrate: download.videoBitrate, fileSize: fileSize)

        if isMuxed || !details.isEmpty {
            HStack(spacing: 4) {
                if isMuxed {
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

    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

// MARK: - Downloaded Audio Row

/// Row view for downloaded audio - displays download info (not tappable).
struct DownloadedAudioRowView: View {
    let download: Download
    let showAdvancedDetails: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                titleRow
                if showAdvancedDetails {
                    detailsRow
                }
            }

            Spacer()
        }
        .frame(minHeight: showAdvancedDetails ? nil : 36)
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

            if let lang = download.audioLanguage {
                Text(Locale.current.localizedString(forLanguageCode: lang) ?? lang)
                    .font(.headline)
            } else {
                Text(String(localized: "stream.audio"))
                    .font(.headline)
            }

            if showAdvancedDetails, let codec = download.audioCodec {
                Text(codec.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var detailsRow: some View {
        let fileSize: String? = download.audioTotalBytes > 0 ? formatFileSize(download.audioTotalBytes) : nil
        let details = formatStreamDetails(bitrate: download.audioBitrate, fileSize: fileSize)
        if !details.isEmpty {
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

// MARK: - Downloaded Caption Row

/// Row view for downloaded caption - tappable to select/toggle subtitles.
struct DownloadedCaptionRowView: View {
    let download: Download
    let localCaptionURL: URL?
    let currentCaption: Caption?
    let onCaptionSelected: (Caption?) -> Void
    let onDismiss: () -> Void

    private var languageCode: String {
        download.captionLanguage ?? "unknown"
    }

    private var languageName: String {
        Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode
    }

    private var caption: Caption? {
        localCaptionURL.map { url in
            Caption(label: languageName, languageCode: languageCode, url: url)
        }
    }

    private var isSelected: Bool {
        caption?.url == currentCaption?.url
    }

    var body: some View {
        Button {
            if isSelected {
                onCaptionSelected(nil)
            } else if let caption {
                onCaptionSelected(caption)
            }
            onDismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        Text(languageName)
                            .font(.headline)
                    }
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
}

// MARK: - Previews

#Preview("Downloaded Video Row") {
    VStack(spacing: 0) {
        DownloadedVideoRowView(
            download: .preview,
            showAdvancedDetails: true
        )
        .padding()

        Divider()

        DownloadedVideoRowView(
            download: .muxedPreview,
            showAdvancedDetails: true
        )
        .padding()
    }
    .cardBackground()
    .padding()
}

#Preview("Downloaded Audio Row") {
    VStack(spacing: 0) {
        DownloadedAudioRowView(
            download: .preview,
            showAdvancedDetails: true
        )
        .padding()
    }
    .cardBackground()
    .padding()
}

#Preview("Downloaded Caption Row") {
    VStack(spacing: 0) {
        DownloadedCaptionRowView(
            download: .preview,
            localCaptionURL: URL(string: "file:///Downloads/captions.vtt"),
            currentCaption: nil,
            onCaptionSelected: { _ in },
            onDismiss: {}
        )
        .padding()
    }
    .cardBackground()
    .padding()
}
