//
//  DownloadRowView.swift
//  Yattee
//
//  Row view for displaying a download item.
//

import SwiftUI

#if !os(tvOS)
/// Row view for displaying a download item.
/// Automatically handles DeArrow integration.
/// For completed downloads, uses VideoRowView with tap zone support (thumbnail plays, text opens info).
/// For active downloads, shows custom progress UI with no tap actions.
struct DownloadRowView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let download: Download
    let isActive: Bool
    var onDelete: (() -> Void)? = nil

    // Queue context (optional, enables auto-play when provided)
    var queueSource: QueueSource? = nil
    var sourceLabel: String? = nil
    var videoList: [Video]? = nil
    var videoIndex: Int? = nil
    var loadMoreVideos: LoadMoreVideosCallback? = nil

    // Cache watch progress to avoid CoreData fetches on every re-render
    @State private var cachedWatchProgress: Double?
    @State private var cachedWatchedSeconds: TimeInterval?
    @State private var hasLoadedWatchData = false

    private var video: Video {
        download.toVideo()
    }

    /// Watch progress for this video (0.0 to 1.0), or nil if not watched.
    /// Uses cached value to avoid CoreData fetch on every re-render.
    private var watchProgress: Double? {
        guard !isActive else { return nil }
        return cachedWatchProgress
    }

    /// Watch position in seconds for resume functionality.
    /// Uses cached value to avoid CoreData fetch on every re-render.
    private var watchedSeconds: TimeInterval? {
        guard !isActive else { return nil }
        return cachedWatchedSeconds
    }

    /// Loads watch data from CoreData once on appear.
    private func loadWatchDataIfNeeded() {
        guard !hasLoadedWatchData, !isActive else { return }
        hasLoadedWatchData = true

        guard let dataManager = appEnvironment?.dataManager else { return }

        // Load watch progress
        if let entry = dataManager.watchEntry(for: video.id.videoID) {
            let progress = entry.progress
            cachedWatchProgress = progress > 0 && progress < 1 ? progress : nil
        }

        // Load watched seconds
        cachedWatchedSeconds = dataManager.watchProgress(for: video.id.videoID)
    }

    /// Metadata text for completed downloads (file size + download date)
    private var downloadMetadata: String {
        let sizeText = formatBytes(download.totalBytes)
        
        if let completedAt = download.completedAt {
            let dateText = RelativeDateFormatter.string(for: completedAt)
            return "\(sizeText) • \(dateText)"
        }
        
        return sizeText
    }

    var body: some View {
        if isActive {
            // Active downloads: custom row with progress indicators, no tap actions
            activeDownloadContent
                .if(onDelete != nil) { view in
                    view.videoContextMenu(
                        video: video,
                        customActions: [
                            VideoContextAction(
                                String(localized: "downloads.delete"),
                                systemImage: "trash",
                                role: .destructive,
                                action: { onDelete?() }
                            )
                        ],
                        context: .downloads
                    )
                }
        } else {
            // Completed downloads: use VideoRowView with tap zones (thumbnail plays, text opens info)
            VideoRowView(
                video: video,
                style: .regular,
                watchProgress: watchProgress,
                customMetadata: downloadMetadata
            )
            .tappableVideo(
                video,
                startTime: watchedSeconds,
                queueSource: queueSource,
                sourceLabel: sourceLabel,
                videoList: videoList,
                videoIndex: videoIndex,
                loadMoreVideos: loadMoreVideos
            )
            .videoContextMenu(
                video: video,
                customActions: [
                    VideoContextAction(
                        String(localized: "downloads.delete"),
                        systemImage: "trash",
                        role: .destructive,
                        action: { onDelete?() }
                    )
                ],
                context: .downloads
            )
            .onAppear {
                loadWatchDataIfNeeded()
            }
        }
    }

    private var activeDownloadContent: some View {
        HStack(spacing: 12) {
            // Thumbnail (download status shown automatically)
            DeArrowVideoThumbnail(
                video: video,
                duration: video.formattedDuration
            )
            .frame(width: 120, height: 68)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                    .font(.subheadline)
                    .lineLimit(2)

                Text(download.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isActive {
                    activeDownloadStatusView
                } else {
                    Text(formatBytes(download.totalBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    #if os(iOS)
    private var isWaitingForWiFi: Bool {
        guard let settings = appEnvironment?.downloadSettings,
              let connectivity = appEnvironment?.connectivityMonitor else {
            return false
        }
        return !settings.allowCellularDownloads && connectivity.isCellular
    }
    #endif

    @ViewBuilder
    private var activeDownloadStatusView: some View {
        switch download.status {
        case .queued:
            #if os(iOS)
            if isWaitingForWiFi {
                Label(String(localized: "downloads.status.waitingForWiFi"), systemImage: "wifi")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label(String(localized: "downloads.status.queued"), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #else
            Label(String(localized: "downloads.status.queued"), systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif

        case .downloading:
            #if os(iOS)
            if isWaitingForWiFi {
                waitingForWiFiProgressView
            } else {
                streamProgressView
            }
            #else
            streamProgressView
            #endif

        case .paused:
            Label(String(localized: "downloads.status.paused"), systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.orange)

        case .failed:
            Label(String(localized: "downloads.status.failed"), systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.red)

        case .completed:
            EmptyView()
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var waitingForWiFiProgressView: some View {
        let hasAudio = download.audioStreamURL != nil
        let hasCaption = download.captionURL != nil

        VStack(alignment: .leading, spacing: 3) {
            // Video progress with waiting indicator
            waitingProgressRow(
                icon: "film",
                progress: download.videoProgress,
                isCompleted: download.videoProgress >= 1.0
            )

            // Audio progress (if applicable)
            if hasAudio {
                waitingProgressRow(
                    icon: "waveform",
                    progress: download.audioProgress,
                    isCompleted: download.audioProgress >= 1.0
                )
            }

            // Caption progress (if applicable)
            if hasCaption {
                waitingProgressRow(
                    icon: "captions.bubble",
                    progress: download.captionProgress,
                    isCompleted: download.captionProgress >= 1.0
                )
            }

            // Waiting for WiFi label
            Label(String(localized: "downloads.status.waitingForWiFi"), systemImage: "wifi")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func waitingProgressRow(
        icon: String,
        progress: Double,
        isCompleted: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                ProgressView(value: progress)
                    .frame(width: 50)
                    .tint(.orange)

                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }
    #endif

    @ViewBuilder
    private var streamProgressView: some View {
        let hasAudio = download.audioStreamURL != nil
        let hasCaption = download.captionURL != nil

        VStack(alignment: .leading, spacing: 3) {
            // Video progress
            streamProgressRow(
                icon: "film",
                progress: download.videoProgress,
                speed: download.videoDownloadSpeed,
                isActive: download.videoProgress < 1.0,
                isCompleted: download.videoProgress >= 1.0,
                isSizeUnknown: download.videoSizeUnknown,
                downloadedBytes: download.videoDownloadedBytes
            )

            // Audio progress (if applicable)
            if hasAudio {
                streamProgressRow(
                    icon: "waveform",
                    progress: download.audioProgress,
                    speed: download.audioDownloadSpeed,
                    isActive: download.audioProgress < 1.0,
                    isCompleted: download.audioProgress >= 1.0,
                    isSizeUnknown: download.audioSizeUnknown,
                    downloadedBytes: download.audioDownloadedBytes
                )
            }

            // Caption progress (if applicable)
            if hasCaption {
                streamProgressRow(
                    icon: "captions.bubble",
                    progress: download.captionProgress,
                    speed: download.captionDownloadSpeed,
                    isActive: download.captionProgress < 1.0,
                    isCompleted: download.captionProgress >= 1.0,
                    isSizeUnknown: download.captionSizeUnknown,
                    downloadedBytes: download.captionDownloadedBytes
                )
            }
        }
    }

    @ViewBuilder
    private func streamProgressRow(
        icon: String,
        progress: Double,
        speed: Int64,
        isActive: Bool,
        isCompleted: Bool,
        isSizeUnknown: Bool = false,
        downloadedBytes: Int64 = 0
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if isSizeUnknown {
                // Indeterminate: show bytes downloaded instead of percentage
                Text(formatBytes(downloadedBytes))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()

                if isActive && speed > 0 {
                    Text(formatSpeed(speed))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            } else {
                ProgressView(value: progress)
                    .frame(width: 50)

                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()

                if isActive && speed > 0 {
                    Text(formatSpeed(speed))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytesPerSecond) + "/s"
    }
}

// MARK: - Preview
// Note: Preview requires a Video object for Download initialization.
// See DownloadsView.swift for usage examples.
#endif
