//
//  DownloadQualitySheet.swift
//  Yattee
//
//  Sheet for selecting download quality, audio track, and subtitles before downloading a video.
//

import SwiftUI

#if !os(tvOS)
struct DownloadQualitySheet: View {
    enum DownloadTab: String, CaseIterable {
        case video
        case audio
        case subtitles

        var label: String {
            switch self {
            case .video: String(localized: "player.quality.video")
            case .audio: String(localized: "stream.audio")
            case .subtitles: String(localized: "stream.subtitles")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    let video: Video
    var streams: [Stream] = []
    var captions: [Caption] = []
    var dislikeCount: Int?

    @State private var selectedTab: DownloadTab = .video
    @State private var selectedVideoStream: Stream?
    @State private var selectedAudioStream: Stream?
    @State private var selectedCaption: Caption?
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var fetchedStreams: [Stream]?
    @State private var fetchedCaptions: [Caption]?
    @State private var fetchedStoryboards: [Storyboard]?
    @State private var fetchedVideo: Video?
    @State private var isLoadingStreams = false

    private var availableStreams: [Stream] {
        fetchedStreams ?? streams
    }

    private var availableCaptions: [Caption] {
        fetchedCaptions ?? captions
    }

    /// Video to use for download - prefer fetched video with full author details
    private var videoForDownload: Video {
        fetchedVideo ?? video
    }

    /// Whether to show advanced stream details (codec, bitrate, size)
    private var showAdvancedStreamDetails: Bool {
        appEnvironment?.settingsManager.showAdvancedStreamDetails ?? false
    }

    /// The preferred audio language from settings
    private var preferredAudioLanguage: String? {
        appEnvironment?.settingsManager.preferredAudioLanguage
    }

    /// The preferred subtitles language from settings
    private var preferredSubtitlesLanguage: String? {
        appEnvironment?.settingsManager.preferredSubtitlesLanguage
    }

    /// The preferred video quality from settings
    private var preferredQuality: VideoQuality {
        appEnvironment?.settingsManager.preferredQuality ?? .auto
    }

    // MARK: - Stream Categories

    /// Video streams (both muxed and video-only), sorted by quality
    private var videoStreams: [Stream] {
        let maxRes = preferredQuality.maxResolution
        let allVideoStreams = availableStreams
            .filter { !$0.isAudioOnly && $0.resolution != nil }
            .filter {
                let format = StreamFormat.detect(from: $0)
                return format != .hls && format != .dash
            }
            .sorted { s1, s2 in
                // Preferred quality first
                let s1Preferred = s1.resolution == maxRes
                let s2Preferred = s2.resolution == maxRes
                if s1Preferred != s2Preferred {
                    return s1Preferred
                }
                // Then by resolution (higher first)
                let res1 = s1.resolution ?? .p360
                let res2 = s2.resolution ?? .p360
                if res1 != res2 {
                    return res1 > res2
                }
                // Within same resolution, muxed streams first, then by codec quality
                if s1.isMuxed != s2.isMuxed {
                    return s1.isMuxed
                }
                return videoCodecPriority(s1.videoCodec) > videoCodecPriority(s2.videoCodec)
            }

        // When advanced details are hidden, show only best stream per resolution
        if !showAdvancedStreamDetails {
            var bestByResolution: [Int: Stream] = [:]
            for stream in allVideoStreams {
                let height = stream.resolution?.height ?? 0
                if let existing = bestByResolution[height] {
                    // Prefer muxed, then better codec
                    if stream.isMuxed && !existing.isMuxed {
                        bestByResolution[height] = stream
                    } else if stream.isMuxed == existing.isMuxed &&
                              videoCodecPriority(stream.videoCodec) > videoCodecPriority(existing.videoCodec) {
                        bestByResolution[height] = stream
                    }
                } else {
                    bestByResolution[height] = stream
                }
            }
            return bestByResolution.values.sorted { s1, s2 in
                let s1Preferred = s1.resolution == maxRes
                let s2Preferred = s2.resolution == maxRes
                if s1Preferred != s2Preferred {
                    return s1Preferred
                }
                return (s1.resolution ?? .p360) > (s2.resolution ?? .p360)
            }
        }

        return allVideoStreams
    }

    /// Audio-only streams, deduplicated by language/codec
    private var audioStreams: [Stream] {
        let allAudio = availableStreams.filter { $0.isAudioOnly }

        // When advanced details are hidden, show only best stream per language
        if !showAdvancedStreamDetails {
            var bestByLanguage: [String: Stream] = [:]
            for stream in allAudio {
                let lang = stream.audioLanguage ?? ""
                if let existing = bestByLanguage[lang] {
                    if audioCodecPriority(stream.audioCodec) > audioCodecPriority(existing.audioCodec) {
                        bestByLanguage[lang] = stream
                    } else if audioCodecPriority(stream.audioCodec) == audioCodecPriority(existing.audioCodec),
                              (stream.bitrate ?? 0) > (existing.bitrate ?? 0) {
                        bestByLanguage[lang] = stream
                    }
                } else {
                    bestByLanguage[lang] = stream
                }
            }

            return bestByLanguage.values.sorted { s1, s2 in
                // Preferred language first
                if let preferred = preferredAudioLanguage {
                    let s1Preferred = (s1.audioLanguage ?? "").hasPrefix(preferred)
                    let s2Preferred = (s2.audioLanguage ?? "").hasPrefix(preferred)
                    if s1Preferred != s2Preferred {
                        return s1Preferred
                    }
                } else {
                    // Original audio first
                    if s1.isOriginalAudio != s2.isOriginalAudio {
                        return s1.isOriginalAudio
                    }
                }
                return (s1.audioLanguage ?? "") < (s2.audioLanguage ?? "")
            }
        }

        // Full details: group by language + codec
        var bestByKey: [String: Stream] = [:]
        for stream in allAudio {
            let lang = stream.audioLanguage ?? ""
            let codec = stream.audioCodec ?? ""
            let key = "\(lang)|\(codec)"
            if let existing = bestByKey[key] {
                if (stream.bitrate ?? 0) > (existing.bitrate ?? 0) {
                    bestByKey[key] = stream
                }
            } else {
                bestByKey[key] = stream
            }
        }

        return bestByKey.values.sorted { s1, s2 in
            if let preferred = preferredAudioLanguage {
                let s1Preferred = (s1.audioLanguage ?? "").hasPrefix(preferred)
                let s2Preferred = (s2.audioLanguage ?? "").hasPrefix(preferred)
                if s1Preferred != s2Preferred {
                    return s1Preferred
                }
            } else if s1.isOriginalAudio != s2.isOriginalAudio {
                return s1.isOriginalAudio
            }
            let lang1 = s1.audioLanguage ?? ""
            let lang2 = s2.audioLanguage ?? ""
            if lang1 != lang2 { return lang1 < lang2 }
            return audioCodecPriority(s1.audioCodec) > audioCodecPriority(s2.audioCodec)
        }
    }

    /// Whether the selected video stream requires a separate audio track
    private var requiresAudioTrack: Bool {
        selectedVideoStream?.isVideoOnly == true
    }

    /// Whether we have any video-only streams that would need audio
    private var hasVideoOnlyStreams: Bool {
        videoStreams.contains { $0.isVideoOnly }
    }

    /// Best audio stream for auto-selection
    private var defaultAudioStream: Stream? {
        if let preferred = preferredAudioLanguage {
            if let match = audioStreams.first(where: { ($0.audioLanguage ?? "").hasPrefix(preferred) }) {
                return match
            }
        }
        if let original = audioStreams.first(where: { $0.isOriginalAudio }) {
            return original
        }
        return audioStreams.first
    }

    /// Available tabs based on streams and captions
    private var availableTabs: [DownloadTab] {
        var tabs: [DownloadTab] = [.video]
        if hasVideoOnlyStreams && !audioStreams.isEmpty {
            tabs.append(.audio)
        }
        if !availableCaptions.isEmpty {
            tabs.append(.subtitles)
        }
        return tabs
    }

    /// Whether the download button should be enabled
    private var canDownload: Bool {
        guard let video = selectedVideoStream else { return false }
        if video.isVideoOnly && selectedAudioStream == nil {
            return false
        }
        return !isDownloading
    }

    // MARK: - Codec Priority

    private func videoCodecPriority(_ codec: String?) -> Int {
        guard let codec = codec?.lowercased() else { return 0 }
        if codec.contains("av1") || codec.contains("av01") { return 3 }
        if codec.contains("vp9") || codec.contains("vp09") { return 2 }
        if codec.contains("avc") || codec.contains("h264") { return 1 }
        return 0
    }

    private func audioCodecPriority(_ codec: String?) -> Int {
        guard let codec = codec?.lowercased() else { return 0 }
        if codec.contains("opus") { return 2 }
        if codec.contains("aac") || codec.contains("mp4a") { return 1 }
        return 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingStreams {
                    loadingContent
                } else {
                    mainContent
                }
            }
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #else
            .background(Color(.systemGroupedBackground))
            #endif
            .navigationTitle(String(localized: "download.selectQuality"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        startDownload()
                    } label: {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(String(localized: "download.start"))
                        }
                    }
                    .disabled(!canDownload)
                }
            }
            .onAppear {
                // Pre-select streams
                if selectedVideoStream == nil {
                    selectedVideoStream = videoStreams.first
                }
                if selectedAudioStream == nil {
                    selectedAudioStream = defaultAudioStream
                }

                // WebDAV/local folder videos use direct file URL, no API fetch needed
                if video.isFromMediaSource {
                    // Always create a proper download stream for media sources
                    // The passed-in streams may have nil resolution and won't pass filters
                    Task {
                        await createStreamForMediaSource()
                    }
                    return
                }

                // For Yattee Server, always fetch proxy streams for faster LAN downloads
                // even if playback streams were passed in (those point to YouTube CDN)
                let isYatteeServer = appEnvironment?.instancesManager.instance(for: video)?.isYatteeServerInstance ?? false

                if isYatteeServer || (streams.isEmpty && fetchedStreams == nil) {
                    Task {
                        await fetchStreamsAndCaptions()
                    }
                } else if captions.isEmpty && fetchedCaptions == nil {
                    // Streams provided but no captions - fetch captions only
                    Task {
                        await fetchCaptionsOnly()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Main Content Views

    @ViewBuilder
    private var loadingContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "download.selectQuality.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Tab picker
                if availableTabs.count > 1 {
                    Picker("", selection: $selectedTab) {
                        ForEach(availableTabs, id: \.self) { tab in
                            Text(tab.label).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Content based on selected tab
                switch selectedTab {
                case .video:
                    videoSection
                case .audio:
                    audioSection
                case .subtitles:
                    subtitlesSection
                }

                // Selection summary
                if selectedVideoStream != nil {
                    selectionSummary
                }
            }
            .padding()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var videoSection: some View {
        if videoStreams.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "download.noStreams.title"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(String(localized: "download.noStreams.description"))
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(videoStreams.enumerated()), id: \.element.url) { index, stream in
                    if index > 0 {
                        Divider()
                    }
                    videoStreamRow(stream)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
            }
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(.secondarySystemGroupedBackground))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if requiresAudioTrack {
                Text(String(localized: "download.videoOnly.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        if audioStreams.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "download.noAudio.title"), systemImage: "speaker.slash")
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(audioStreams.enumerated()), id: \.element.url) { index, stream in
                    if index > 0 {
                        Divider()
                    }
                    audioStreamRow(stream)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
            }
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(.secondarySystemGroupedBackground))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var subtitlesSection: some View {
        VStack(spacing: 0) {
            // "None" option
            captionRow(nil)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

            ForEach(sortedCaptions) { caption in
                Divider()
                captionRow(caption)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
        }
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
        #else
        .background(Color(.secondarySystemGroupedBackground))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sortedCaptions: [Caption] {
        availableCaptions.sorted { c1, c2 in
            if let preferred = preferredSubtitlesLanguage {
                let c1Preferred = c1.baseLanguageCode == preferred || c1.languageCode.hasPrefix(preferred)
                let c2Preferred = c2.baseLanguageCode == preferred || c2.languageCode.hasPrefix(preferred)
                if c1Preferred != c2Preferred {
                    return c1Preferred
                }
            }
            return c1.displayName.localizedCaseInsensitiveCompare(c2.displayName) == .orderedAscending
        }
    }

    @ViewBuilder
    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "download.summary"), systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                if let video = selectedVideoStream {
                    HStack {
                        Text(String(localized: "download.summary.video"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(video.qualityLabel) \(video.isMuxed ? "(muxed)" : "")")
                    }
                    .font(.caption)
                }

                if requiresAudioTrack, let audio = selectedAudioStream {
                    HStack {
                        Text(String(localized: "download.summary.audio"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatAudioLabel(audio))
                    }
                    .font(.caption)
                }

                if let caption = selectedCaption {
                    HStack {
                        Text(String(localized: "download.summary.subtitles"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(caption.displayName)
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            #if os(macOS)
            .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            #else
            .background(Color(.tertiarySystemGroupedBackground))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func videoStreamRow(_ stream: Stream) -> some View {
        let isSelected = stream.url == selectedVideoStream?.url
        let isPreferred = stream.resolution == preferredQuality.maxResolution

        Button {
            selectedVideoStream = stream
            // If switching to muxed stream, clear audio selection requirement
            // If switching to video-only, ensure audio is selected
            if stream.isVideoOnly && selectedAudioStream == nil {
                selectedAudioStream = defaultAudioStream
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isPreferred {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(stream.qualityLabel)
                            .font(.headline)

                        if showAdvancedStreamDetails {
                            if stream.isMuxed {
                                Text(String(localized: "stream.badge.muxed"))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            } else if let codec = stream.videoCodec {
                                Text(formatCodec(codec))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(codecColor(codec).opacity(0.2))
                                    .foregroundStyle(codecColor(codec))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if showAdvancedStreamDetails {
                        HStack(spacing: 4) {
                            if stream.isMuxed {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let size = stream.formattedFileSize {
                                Text(size)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let bitrate = stream.bitrate {
                                Text(formatBitrate(bitrate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .frame(minHeight: showAdvancedStreamDetails ? nil : 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func audioStreamRow(_ stream: Stream) -> some View {
        let isSelected = stream.url == selectedAudioStream?.url
        let isPreferred = preferredAudioLanguage.map { (stream.audioLanguage ?? "").hasPrefix($0) } ?? false

        Button {
            selectedAudioStream = stream
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isPreferred {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(formatAudioLabel(stream))
                            .font(.headline)

                        if showAdvancedStreamDetails, let codec = stream.audioCodec {
                            Text(codec.uppercased())
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }

                    if showAdvancedStreamDetails {
                        HStack(spacing: 4) {
                            if stream.isOriginalAudio {
                                Text(String(localized: "stream.audio.original"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let bitrate = stream.bitrate {
                                Text(formatBitrate(bitrate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let size = stream.formattedFileSize {
                                Text(size)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .frame(minHeight: showAdvancedStreamDetails ? nil : 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func captionRow(_ caption: Caption?) -> some View {
        let isSelected = caption?.id == selectedCaption?.id
        let isPreferred = caption.map { cap in
            preferredSubtitlesLanguage.map { cap.baseLanguageCode == $0 || cap.languageCode.hasPrefix($0) } ?? false
        } ?? false

        Button {
            selectedCaption = caption
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isPreferred {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(caption?.displayName ?? String(localized: "stream.subtitles.none"))
                            .font(.headline)

                        if let caption, caption.isAutoGenerated {
                            Text(String(localized: "stream.subtitle.auto"))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
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

    // MARK: - Helpers

    private func formatAudioLabel(_ stream: Stream) -> String {
        if let lang = stream.audioLanguage {
            return Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
        }
        return stream.audioTrackName ?? String(localized: "stream.audio.default")
    }

    private func formatCodec(_ codec: String) -> String {
        let lowercased = codec.lowercased()
        if lowercased.contains("avc") || lowercased.contains("h264") { return "H.264" }
        if lowercased.contains("hev") || lowercased.contains("h265") || lowercased.contains("hevc") { return "HEVC" }
        if lowercased.contains("vp9") || lowercased.contains("vp09") { return "VP9" }
        if lowercased.contains("av1") || lowercased.contains("av01") { return "AV1" }
        return codec.uppercased()
    }

    private func codecColor(_ codec: String) -> Color {
        let lowercased = codec.lowercased()
        if lowercased.contains("av1") || lowercased.contains("av01") { return .blue }
        if lowercased.contains("vp9") || lowercased.contains("vp09") { return .orange }
        if lowercased.contains("avc") || lowercased.contains("h264") { return .red }
        if lowercased.contains("hev") || lowercased.contains("h265") || lowercased.contains("hevc") { return .green }
        return .gray
    }

    private func formatBitrate(_ bitrate: Int) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        }
        return "\(bitrate / 1000) kbps"
    }

    // MARK: - Actions

    private func startDownload() {
        guard let videoStream = selectedVideoStream,
              let downloadManager = appEnvironment?.downloadManager else {
            return
        }

        // Validate audio selection for video-only streams
        if videoStream.isVideoOnly && selectedAudioStream == nil {
            errorMessage = String(localized: "download.error.audioRequired")
            return
        }

        isDownloading = true
        errorMessage = nil

        Task {
            do {
                let audioURL = videoStream.isVideoOnly ? selectedAudioStream?.url : nil
                let audioLang = videoStream.isVideoOnly ? selectedAudioStream?.audioLanguage : nil
                // For muxed streams, use the stream's audio codec; for video-only, use selected audio stream's codec
                let audioCodec = videoStream.isMuxed ? videoStream.audioCodec : selectedAudioStream?.audioCodec
                let audioBitrate = videoStream.isMuxed ? nil : selectedAudioStream?.bitrate

                // Select highest quality storyboard for download
                let preferredStoryboard = fetchedStoryboards?.highest()
                LoggingService.shared.logDownload(
                    "[Downloads] Storyboard selection",
                    details: "fetched: \(fetchedStoryboards?.count ?? 0), preferred: \(preferredStoryboard?.width ?? 0)x\(preferredStoryboard?.height ?? 0), sheets: \(preferredStoryboard?.storyboardCount ?? 0)"
                )

                try await downloadManager.enqueue(
                    videoForDownload,
                    quality: videoStream.qualityLabel,
                    formatID: videoStream.format,
                    streamURL: videoStream.url,
                    audioStreamURL: audioURL,
                    captionURL: selectedCaption?.url,
                    audioLanguage: audioLang,
                    captionLanguage: selectedCaption?.languageCode,
                    httpHeaders: videoStream.httpHeaders,
                    storyboard: preferredStoryboard,
                    dislikeCount: dislikeCount,
                    videoCodec: videoStream.videoCodec,
                    audioCodec: audioCodec,
                    videoBitrate: videoStream.bitrate,
                    audioBitrate: audioBitrate
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }

    private func createStreamForMediaSource() async {
        guard case .extracted(_, let originalURL) = video.id.source else { return }

        var authHeaders: [String: String]?

        // Get auth headers for WebDAV sources
        if video.isFromWebDAV,
           let sourceID = video.mediaSourceID,
           let appEnvironment,
           let source = appEnvironment.mediaSourcesManager.sources.first(where: { $0.id == sourceID }) {
            let password = appEnvironment.mediaSourcesManager.password(for: source)
            authHeaders = await appEnvironment.webDAVClient.authHeaders(for: source, password: password)
        }

        let fileExtension = originalURL.pathExtension.lowercased()
        // Use a placeholder resolution so the stream passes the videoStreams filter
        // Mark as muxed (has audio) since local files typically have both tracks
        let stream = Stream(
            url: originalURL,
            resolution: .p1080,  // Placeholder - actual resolution unknown
            format: fileExtension.isEmpty ? "video" : fileExtension,
            audioCodec: "aac",   // Placeholder to mark as muxed
            httpHeaders: authHeaders
        )

        await MainActor.run {
            fetchedStreams = [stream]
            selectedVideoStream = stream
        }
    }

    private func fetchStreamsAndCaptions() async {
        guard let appEnvironment,
              let instance = appEnvironment.instancesManager.instance(for: video) else {
            return
        }

        isLoadingStreams = true
        errorMessage = nil

        do {
            // For Yattee Server, use proxy streams for faster LAN downloads
            // Proxy URLs point to the server instead of YouTube CDN
            let loadedVideo: Video
            let loadedStreams: [Stream]
            let loadedCaptions: [Caption]
            let loadedStoryboards: [Storyboard]

            if case .extracted(_, let originalURL) = video.id.source {
                // Extracted videos need re-extraction via /api/v1/extract
                let result = try await appEnvironment.contentService.extractURL(originalURL, instance: instance)
                loadedVideo = result.video
                loadedStreams = result.streams
                loadedCaptions = result.captions
                loadedStoryboards = []
            } else {
                let result = try await appEnvironment.contentService.videoWithProxyStreamsAndCaptionsAndStoryboards(
                    id: video.id.videoID,
                    instance: instance
                )
                loadedVideo = result.video
                loadedStreams = result.streams
                loadedCaptions = result.captions
                loadedStoryboards = result.storyboards
            }

            await MainActor.run {
                fetchedStreams = loadedStreams
                fetchedVideo = loadedVideo
                fetchedCaptions = loadedCaptions
                fetchedStoryboards = loadedStoryboards
                isLoadingStreams = false

                // Pre-select streams after fetching
                if selectedVideoStream == nil {
                    selectedVideoStream = videoStreams.first
                }
                if selectedAudioStream == nil {
                    selectedAudioStream = defaultAudioStream
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingStreams = false
            }
        }
    }

    private func fetchCaptionsOnly() async {
        guard let appEnvironment,
              let instance = appEnvironment.instancesManager.instance(for: video) else {
            return
        }

        do {
            let loadedCaptions = try await appEnvironment.contentService.captions(
                videoID: video.id.videoID,
                instance: instance
            )

            await MainActor.run {
                fetchedCaptions = loadedCaptions
            }
        } catch {
            // Silently fail - captions are optional
            await MainActor.run {
                fetchedCaptions = []
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DownloadQualitySheet(
        video: .preview,
        streams: [
            Stream(
                url: URL(string: "https://example.com/video.mp4")!,
                resolution: .p1080,
                format: "mp4",
                videoCodec: "avc1",
                audioCodec: "mp4a",
                fileSize: 500_000_000
            ),
            Stream(
                url: URL(string: "https://example.com/video_only.webm")!,
                resolution: .p1080,
                format: "webm",
                videoCodec: "vp9",
                fileSize: 400_000_000
            ),
            Stream(
                url: URL(string: "https://example.com/audio.m4a")!,
                resolution: nil,
                format: "m4a",
                audioCodec: "mp4a",
                fileSize: 50_000_000,
                isAudioOnly: true,
                audioLanguage: "en"
            )
        ]
    )
    .appEnvironment(.preview)
}
#endif
