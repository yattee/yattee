//
//  OpenLinkSheet.swift
//  Yattee
//
//  Sheet for entering URLs to play or download via Yattee Server's yt-dlp extraction.
//  Supports multiple URLs (one per line) with batch processing.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Extraction Item Model

/// Tracks extraction status for each URL in batch processing.
private struct ExtractedItem: Identifiable {
    let id = UUID()
    let url: URL
    var displayHost: String { url.host ?? url.absoluteString }
    var status: ExtractionStatus = .pending
    var video: Video?
    var streams: [Stream] = []
    var captions: [Caption] = []
    var storyboards: [Storyboard] = []
}

private enum ExtractionStatus {
    case pending
    case extracting
    case success
    case failed(String)
}

// MARK: - OpenLinkSheet

/// Sheet for entering URLs to play or download from external sites.
/// Supports multiple URLs (one per line, max 20).
struct OpenLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var urlText: String
    @State private var clipboardURLs: [URL] = []
    @FocusState private var isTextEditorFocused: Bool

    // Extraction state
    @State private var isExtracting = false
    @State private var extractedItems: [ExtractedItem] = []
    @State private var hasErrors = false

    // Download flow states
    @State private var showingDownloadSheet = false
    @State private var pendingDownloadItems: [ExtractedItem] = []

    /// Maximum number of URLs allowed.
    private static let maxURLs = 20

    /// Initialize with optional pre-filled URL.
    init(prefilledURL: URL? = nil) {
        _urlText = State(initialValue: prefilledURL?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                urlInputSection
                extractionResultsSection
                actionButtonsSection
                yatteeServerWarningSection
            }
            .navigationTitle(String(localized: "openLink.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                checkClipboard()
                if urlText.isEmpty {
                    isTextEditorFocused = true
                }
            }
            #if !os(tvOS)
            .sheet(isPresented: $showingDownloadSheet, onDismiss: {
                // Close OpenLinkSheet when download sheet is dismissed (if no errors)
                if !hasErrors {
                    dismiss()
                }
            }) {
                BatchDownloadQualitySheet(videoCount: pendingDownloadItems.count) { quality, includeSubtitles in
                    Task {
                        await downloadPendingItems(quality: quality, includeSubtitles: includeSubtitles)
                    }
                }
            }
            #endif
        }
    }

    // MARK: - URL Input Section

    @ViewBuilder
    private var urlInputSection: some View {
        Section {
            #if os(tvOS)
            // tvOS doesn't have TextEditor, use TextField for single URL
            TextField(String(localized: "openLink.urlPlaceholder"), text: $urlText)
                .textContentType(.URL)
                .focused($isTextEditorFocused)
                .disabled(isExtracting)
            #else
            TextEditor(text: $urlText)
                .frame(minHeight: 100, maxHeight: 200)
                .font(.system(.body, design: .monospaced))
                #if os(iOS)
                .autocapitalization(.none)
                .keyboardType(.URL)
                #endif
                .focused($isTextEditorFocused)
                .disabled(isExtracting)
            #endif

            #if !os(tvOS)
            // URL count indicator (not shown on tvOS since it only supports single URL)
            HStack {
                if isTooManyURLs {
                    Label(
                        String(localized: "openLink.tooManyUrls \(Self.maxURLs)"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                } else if urlCount > 0 {
                    Text(String(localized: "openLink.urlCount \(urlCount)"))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
            }

            // Clipboard paste button (not available on tvOS)
            if !clipboardURLs.isEmpty, !isExtracting {
                let clipboardText = clipboardURLs.map(\.absoluteString).joined(separator: "\n")
                if clipboardText != urlText {
                    Button {
                        urlText = clipboardText
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            VStack(alignment: .leading) {
                                if clipboardURLs.count > 1 {
                                    Text(String(localized: "openLink.pasteMultiple \(clipboardURLs.count)"))
                                        .font(.subheadline)
                                } else {
                                    Text(String(localized: "openLink.pasteClipboard"))
                                        .font(.subheadline)
                                }
                                Text(clipboardURLs.first?.host ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
            #endif
        } footer: {
            Text(supportedSitesHint)
        }
    }

    /// Dynamic hint text based on enabled backend instances.
    private var supportedSitesHint: String {
        guard let instancesManager = appEnvironment?.instancesManager else {
            return String(localized: "openLink.hint.noInstances")
        }

        let hasEnabledYatteeServer = !instancesManager.enabledYatteeServerInstances.isEmpty
        let hasEnabledInvidiousPiped = instancesManager.enabledInstances.contains {
            $0.type == .invidious || $0.type == .piped
        }

        if hasEnabledYatteeServer {
            return String(localized: "openLink.hint.yatteeServer")
        } else if hasEnabledInvidiousPiped {
            return String(localized: "openLink.hint.youtubeOnly")
        } else {
            return String(localized: "openLink.hint.noInstances")
        }
    }

    // MARK: - Extraction Results Section

    @ViewBuilder
    private var extractionResultsSection: some View {
        if !extractedItems.isEmpty {
            Section {
                ForEach(extractedItems) { item in
                    HStack(spacing: 12) {
                        // Status indicator
                        Group {
                            switch item.status {
                            case .pending:
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            case .extracting:
                                ProgressView()
                                    .controlSize(.small)
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failed:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(width: 20)

                        // URL info
                        VStack(alignment: .leading, spacing: 2) {
                            if let video = item.video {
                                Text(video.title)
                                    .lineLimit(1)
                                Text(item.displayHost)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                // No video extracted - show full URL (useful for failures)
                                Text(item.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if case .failed(let error) = item.status {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }

                        Spacer()
                    }
                }
            } header: {
                if isExtracting {
                    let processed = extractedItems.filter { item in
                        switch item.status {
                        case .pending: return false
                        default: return true
                        }
                    }.count
                    Text(String(localized: "openLink.extractingProgress \(processed) \(extractedItems.count)"))
                } else {
                    Text(String(localized: "openLink.results"))
                }
            }
        }
    }

    // MARK: - Action Buttons Section

    @ViewBuilder
    private var actionButtonsSection: some View {
        Section {
            if isExtracting {
                HStack {
                    ProgressView()
                    Text(String(localized: "openLink.extracting"))
                        .foregroundStyle(.secondary)
                }
            } else {
                // Open/Play button
                Button {
                    isTextEditorFocused = false
                    Task { await openAllURLs() }
                } label: {
                    Label(
                        isMultipleURLs
                            ? String(localized: "openLink.openAll")
                            : String(localized: "openLink.open"),
                        systemImage: "play.fill"
                    )
                }
                .disabled(!isValidInput)

                #if !os(tvOS)
                // Download button
                Button {
                    isTextEditorFocused = false
                    Task { await downloadAllURLs() }
                } label: {
                    Label(
                        isMultipleURLs
                            ? String(localized: "openLink.downloadAll")
                            : String(localized: "openLink.download"),
                        systemImage: "arrow.down.circle"
                    )
                }
                .disabled(!isValidInput)
                #endif
            }
        }
    }

    // MARK: - Yattee Server Warning Section

    @ViewBuilder
    private var yatteeServerWarningSection: some View {
        if !hasYatteeServer && hasExternalURLs && !isExtracting {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(String(localized: "openLink.yatteeServerNotConfigured"))
                        .font(.subheadline)
                }
                Text(String(localized: "openLink.yatteeServerMessage"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var hasYatteeServer: Bool {
        appEnvironment?.instancesManager.yatteeServerInstance != nil
    }

    /// Parse URLs from input text, one per line.
    private var parsedURLs: [URL] {
        urlText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
            .filter { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return (scheme == "http" || scheme == "https") && url.host != nil
            }
            .prefix(Self.maxURLs)
            .map { $0 }
    }

    private var urlCount: Int { parsedURLs.count }
    private var isValidInput: Bool { !parsedURLs.isEmpty }
    private var isMultipleURLs: Bool { urlCount > 1 }

    private var isTooManyURLs: Bool {
        urlText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count > Self.maxURLs
    }

    /// Whether any of the parsed URLs are external (non-YouTube/PeerTube).
    private var hasExternalURLs: Bool {
        let router = URLRouter()
        return parsedURLs.contains { url in
            if let destination = router.route(url) {
                if case .externalVideo = destination { return true }
                return false
            }
            return true
        }
    }

    // MARK: - Clipboard

    private func checkClipboard() {
        clipboardURLs = []

        #if os(iOS)
        if let string = UIPasteboard.general.string {
            clipboardURLs = parseURLsFromString(string)
        }
        #elseif os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            clipboardURLs = parseURLsFromString(string)
        }
        #endif
    }

    private func parseURLsFromString(_ string: String) -> [URL] {
        string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
            .filter { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return (scheme == "http" || scheme == "https") && url.host != nil
            }
            .prefix(Self.maxURLs)
            .map { $0 }
    }

    // MARK: - Open (Play) Action

    private func openAllURLs() async {
        let urls = parsedURLs
        guard !urls.isEmpty, let appEnvironment else { return }

        isExtracting = true
        hasErrors = false
        extractedItems = urls.map { ExtractedItem(url: $0) }

        var successCount = 0
        var failedCount = 0
        var firstVideoPlayed = false

        for (index, url) in urls.enumerated() {
            extractedItems[index].status = .extracting

            do {
                let (video, streams) = try await extractVideo(from: url, appEnvironment: appEnvironment)
                extractedItems[index].status = .success
                extractedItems[index].video = video
                extractedItems[index].streams = streams
                successCount += 1

                if !firstVideoPlayed {
                    // Play first video - this expands player
                    playVideo(video, appEnvironment: appEnvironment)
                    firstVideoPlayed = true
                } else {
                    // Add to queue
                    appEnvironment.queueManager.addToQueue(video, queueSource: .manual)
                }
            } catch {
                extractedItems[index].status = .failed(error.localizedDescription)
                failedCount += 1
                hasErrors = true
            }
        }

        isExtracting = false

        // Show completion toast and handle dismissal
        if failedCount == 0 {
            if successCount > 1 {
                appEnvironment.toastManager.showSuccess(
                    String(localized: "openLink.queuedSuccess.title"),
                    subtitle: String(localized: "openLink.queuedSuccess.subtitle \(successCount)")
                )
            }
            dismiss()
        } else if successCount > 0 {
            appEnvironment.toastManager.show(
                category: .error,
                title: String(localized: "openLink.queuedPartial.title"),
                subtitle: String(localized: "openLink.queuedPartial.subtitle \(successCount) \(failedCount)")
            )
            // Keep sheet open so user can see errors
        } else {
            appEnvironment.toastManager.show(
                category: .error,
                title: String(localized: "openLink.allFailed.title"),
                subtitle: String(localized: "openLink.allFailed.subtitle \(failedCount)")
            )
            // Keep sheet open
        }
    }

    /// Extracts video from URL, routing through appropriate API.
    private func extractVideo(
        from url: URL,
        appEnvironment: AppEnvironment
    ) async throws -> (Video, [Stream]) {
        let router = URLRouter()
        let destination = router.route(url)

        switch destination {
        case .video(let source, _):
            guard case .id(let videoID) = source else {
                throw OpenLinkError.notAVideo
            }
            // YouTube/PeerTube - use content-aware instance selection
            guard let instance = appEnvironment.instancesManager.instance(for: videoID.source) else {
                throw OpenLinkError.noInstanceAvailable
            }
            let (video, streams, _, _) = try await appEnvironment.contentService
                .videoWithProxyStreamsAndCaptionsAndStoryboards(
                    id: videoID.videoID,
                    instance: instance
                )
            return (video, streams)

        case .directMedia(let mediaURL):
            // Direct media URL - no extraction needed
            let video = DirectMediaHelper.createVideo(from: mediaURL)
            let stream = DirectMediaHelper.createStream(from: mediaURL)
            return (video, [stream])

        case .externalVideo, nil:
            // External URL - use Yattee Server
            guard let instance = appEnvironment.instancesManager.yatteeServerInstance else {
                throw OpenLinkError.noYatteeServer
            }
            let (video, streams, _) = try await appEnvironment.contentService
                .extractURL(url, instance: instance)
            return (video, streams)

        default:
            throw OpenLinkError.notAVideo
        }
    }

    private func playVideo(_ video: Video, appEnvironment: AppEnvironment) {
        // Don't pass a specific stream - let the player's selectStreamAndBackend
        // choose the best video+audio combination. Using streams.first would
        // incorrectly select audio-only streams for sites like Bilibili.
        appEnvironment.playerService.openVideo(video)
    }

    // MARK: - Download Action

    #if !os(tvOS)
    private func downloadAllURLs() async {
        let urls = parsedURLs
        guard !urls.isEmpty, let appEnvironment else { return }

        isExtracting = true
        hasErrors = false
        extractedItems = urls.map { ExtractedItem(url: $0) }

        let downloadSettings = appEnvironment.downloadSettings
        var successCount = 0
        var failedCount = 0

        for (index, url) in urls.enumerated() {
            extractedItems[index].status = .extracting

            do {
                let (video, streams, captions, storyboards) = try await extractVideoFull(from: url, appEnvironment: appEnvironment)
                extractedItems[index].status = .success
                extractedItems[index].video = video
                extractedItems[index].streams = streams
                extractedItems[index].captions = captions
                extractedItems[index].storyboards = storyboards
                successCount += 1

                // If auto-download is configured, enqueue immediately
                if downloadSettings.preferredDownloadQuality != .ask {
                    try await enqueueDownload(
                        video: video,
                        streams: streams,
                        captions: captions,
                        storyboards: storyboards,
                        quality: downloadSettings.preferredDownloadQuality,
                        includeSubtitles: downloadSettings.includeSubtitlesInAutoDownload,
                        appEnvironment: appEnvironment
                    )
                }
            } catch {
                extractedItems[index].status = .failed(error.localizedDescription)
                failedCount += 1
                hasErrors = true
            }
        }

        isExtracting = false

        // Handle completion based on download mode
        if downloadSettings.preferredDownloadQuality == .ask {
            // Show quality picker for all extracted videos
            pendingDownloadItems = extractedItems.filter { $0.video != nil }
            if !pendingDownloadItems.isEmpty {
                showingDownloadSheet = true
            } else if failedCount > 0 {
                appEnvironment.toastManager.show(
                    category: .error,
                    title: String(localized: "openLink.allFailed.title"),
                    subtitle: String(localized: "openLink.allFailed.subtitle \(failedCount)")
                )
            }
        } else {
            // Auto-download mode - show completion toast
            if failedCount == 0 {
                if successCount >= 2 {
                    appEnvironment.toastManager.showSuccess(
                        String(localized: "openLink.downloadQueued.title"),
                        subtitle: String(localized: "openLink.downloadQueued.subtitle \(successCount)")
                    )
                }
                dismiss()
            } else if successCount > 0 {
                appEnvironment.toastManager.show(
                    category: .error,
                    title: String(localized: "openLink.downloadPartial.title"),
                    subtitle: String(localized: "openLink.downloadPartial.subtitle \(successCount) \(failedCount)")
                )
                // Keep sheet open
            } else {
                appEnvironment.toastManager.show(
                    category: .error,
                    title: String(localized: "openLink.allFailed.title"),
                    subtitle: String(localized: "openLink.allFailed.subtitle \(failedCount)")
                )
                // Keep sheet open
            }
        }
    }

    /// Extracts video with full details (including captions and storyboards) for download.
    private func extractVideoFull(
        from url: URL,
        appEnvironment: AppEnvironment
    ) async throws -> (Video, [Stream], [Caption], [Storyboard]) {
        let router = URLRouter()
        let destination = router.route(url)

        switch destination {
        case .video(let source, _):
            guard case .id(let videoID) = source else {
                throw OpenLinkError.notAVideo
            }
            // YouTube/PeerTube - use content-aware instance selection
            guard let instance = appEnvironment.instancesManager.instance(for: videoID.source) else {
                throw OpenLinkError.noInstanceAvailable
            }
            let (video, streams, captions, storyboards) = try await appEnvironment.contentService
                .videoWithProxyStreamsAndCaptionsAndStoryboards(
                    id: videoID.videoID,
                    instance: instance
                )
            return (video, streams, captions, storyboards)

        case .directMedia(let mediaURL):
            // Direct media URL - no extraction needed, no captions/storyboards
            let video = DirectMediaHelper.createVideo(from: mediaURL)
            let stream = DirectMediaHelper.createStream(from: mediaURL)
            return (video, [stream], [], [])

        case .externalVideo, nil:
            // External URL - use Yattee Server (doesn't support storyboards)
            guard let instance = appEnvironment.instancesManager.yatteeServerInstance else {
                throw OpenLinkError.noYatteeServer
            }
            let (video, streams, captions) = try await appEnvironment.contentService
                .extractURL(url, instance: instance)
            return (video, streams, captions, [])

        default:
            throw OpenLinkError.notAVideo
        }
    }

    /// Downloads pending items after user selects quality.
    private func downloadPendingItems(quality: DownloadQuality, includeSubtitles: Bool) async {
        guard let appEnvironment else { return }

        var successCount = 0
        var failedCount = 0

        for item in pendingDownloadItems {
            guard let video = item.video else { continue }

            do {
                try await enqueueDownload(
                    video: video,
                    streams: item.streams,
                    captions: item.captions,
                    storyboards: item.storyboards,
                    quality: quality,
                    includeSubtitles: includeSubtitles,
                    appEnvironment: appEnvironment
                )
                successCount += 1
            } catch {
                failedCount += 1
            }
        }

        pendingDownloadItems = []

        // Show completion toast
        if failedCount == 0 {
            if successCount >= 2 {
                appEnvironment.toastManager.showSuccess(
                    String(localized: "openLink.downloadQueued.title"),
                    subtitle: String(localized: "openLink.downloadQueued.subtitle \(successCount)")
                )
            }
            if !hasErrors {
                dismiss()
            }
        } else {
            appEnvironment.toastManager.show(
                category: .error,
                title: String(localized: "openLink.downloadPartial.title"),
                subtitle: String(localized: "openLink.downloadPartial.subtitle \(successCount) \(failedCount)")
            )
        }
    }

    /// Enqueues a single video for download with already-fetched streams.
    private func enqueueDownload(
        video: Video,
        streams: [Stream],
        captions: [Caption],
        storyboards: [Storyboard],
        quality: DownloadQuality,
        includeSubtitles: Bool,
        appEnvironment: AppEnvironment
    ) async throws {
        // Select best video stream
        let videoStream = selectBestVideoStream(from: streams, maxQuality: quality)
        guard let videoStream else {
            throw DownloadError.noStreamAvailable
        }

        // Select audio stream if needed
        var audioStream: Stream?
        if videoStream.isVideoOnly {
            audioStream = selectBestAudioStream(
                from: streams,
                preferredLanguage: appEnvironment.settingsManager.preferredAudioLanguage
            )
        }

        // Select caption if enabled
        var caption: Caption?
        if includeSubtitles, let preferredLang = appEnvironment.settingsManager.preferredSubtitlesLanguage {
            caption = selectBestCaption(from: captions, preferredLanguage: preferredLang)
        }

        let audioCodec = videoStream.isMuxed ? videoStream.audioCodec : audioStream?.audioCodec
        let audioBitrate = videoStream.isMuxed ? nil : audioStream?.bitrate

        try await appEnvironment.downloadManager.enqueue(
            video,
            quality: videoStream.qualityLabel,
            formatID: videoStream.format,
            streamURL: videoStream.url,
            audioStreamURL: videoStream.isVideoOnly ? audioStream?.url : nil,
            captionURL: caption?.url,
            audioLanguage: audioStream?.audioLanguage,
            captionLanguage: caption?.languageCode,
            httpHeaders: videoStream.httpHeaders,
            storyboard: storyboards.highest(),
            dislikeCount: nil,
            videoCodec: videoStream.videoCodec,
            audioCodec: audioCodec,
            videoBitrate: videoStream.bitrate,
            audioBitrate: audioBitrate
        )
    }

    // MARK: - Stream Selection Helpers

    private func selectBestVideoStream(from streams: [Stream], maxQuality: DownloadQuality) -> Stream? {
        let maxRes = maxQuality.maxResolution

        let videoStreams = streams
            .filter { !$0.isAudioOnly && $0.resolution != nil }
            .filter {
                let format = StreamFormat.detect(from: $0)
                return format != .hls && format != .dash
            }
            .sorted { s1, s2 in
                let res1 = s1.resolution ?? .p360
                let res2 = s2.resolution ?? .p360
                if res1 != res2 { return res1 > res2 }
                if s1.isMuxed != s2.isMuxed { return s1.isMuxed }
                return HardwareCapabilities.shared.codecPriority(for: s1.videoCodec) >
                       HardwareCapabilities.shared.codecPriority(for: s2.videoCodec)
            }

        guard let maxRes else {
            return videoStreams.first
        }

        if let stream = videoStreams.first(where: { ($0.resolution ?? .p360) <= maxRes }) {
            return stream
        }

        return videoStreams.last
    }

    private func selectBestAudioStream(from streams: [Stream], preferredLanguage: String?) -> Stream? {
        let audioStreams = streams.filter { $0.isAudioOnly }

        if let preferred = preferredLanguage {
            if let match = audioStreams.first(where: { ($0.audioLanguage ?? "").hasPrefix(preferred) }) {
                return match
            }
        }

        if let original = audioStreams.first(where: { $0.isOriginalAudio }) {
            return original
        }

        return audioStreams.first
    }

    private func selectBestCaption(from captions: [Caption], preferredLanguage: String) -> Caption? {
        if let exact = captions.first(where: { $0.languageCode == preferredLanguage }) {
            return exact
        }
        if let prefix = captions.first(where: {
            $0.languageCode.hasPrefix(preferredLanguage) || $0.baseLanguageCode == preferredLanguage
        }) {
            return prefix
        }
        return nil
    }
    #endif
}

// MARK: - Errors

private enum OpenLinkError: LocalizedError {
    case noInstanceAvailable
    case noYatteeServer
    case notAVideo

    var errorDescription: String? {
        switch self {
        case .noInstanceAvailable:
            return String(localized: "openLink.noInstance")
        case .noYatteeServer:
            return String(localized: "openLink.noYatteeServer")
        case .notAVideo:
            return String(localized: "openLink.notAVideo")
        }
    }
}

// MARK: - Previews

#Preview {
    OpenLinkSheet()
}

#Preview("With URL") {
    OpenLinkSheet(prefilledURL: URL(string: "https://vimeo.com/123456789"))
}

#Preview("Multiple URLs") {
    OpenLinkSheet(prefilledURL: URL(string: "https://youtube.com/watch?v=abc123"))
}
