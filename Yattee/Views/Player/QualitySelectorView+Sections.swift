//
//  QualitySelectorView+Sections.swift
//  Yattee
//
//  Section content views for QualitySelectorView.
//

import SwiftUI

extension QualitySelectorView {
    // MARK: - Main Content Views

    @ViewBuilder
    var loadingContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "player.quality.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    var emptyContent: some View {
        ContentUnavailableView(
            String(localized: "player.quality.unavailable"),
            systemImage: "film.stack",
            description: Text(String(localized: "player.quality.unavailable.description"))
        )
    }

    @ViewBuilder
    var downloadedContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !hasOnlineStreams {
                    downloadInfoSection
                    loadOnlineStreamsButton
                } else {
                    onlineStreamsAfterDownload
                }

                if showTabPicker {
                    generalSectionContent
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    var streamsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showTabPicker && availableTabs.count > 1 {
                    mediaSelectionRows
                } else {
                    tabContent
                }

                if showTabPicker {
                    generalSectionContent
                }
            }
            .padding()
        }
        .onAppear {
            selectedTab = initialTab
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var mediaSelectionRows: some View {
        #if os(tvOS)
        // tvOS: each row is its own rounded card with vertical spacing so the
        // system focus hover effect has clean bounds (no clipped dividers).
        VStack(spacing: 8) {
            mediaSelectionRow(
                destination: .video,
                label: String(localized: "player.quality.video"),
                systemImage: "film",
                value: currentVideoDisplayValue
            )
            if availableTabs.contains(.audio) {
                mediaSelectionRow(
                    destination: .audio,
                    label: String(localized: "stream.audio"),
                    systemImage: "speaker.wave.2",
                    value: currentAudioDisplayValue
                )
            }
            if availableTabs.contains(.subtitles) {
                mediaSelectionRow(
                    destination: .subtitles,
                    label: String(localized: "stream.subtitles"),
                    systemImage: "captions.bubble",
                    value: currentSubtitlesDisplayValue
                )
            }
        }
        #else
        VStack(spacing: 0) {
            mediaSelectionRow(
                destination: .video,
                label: String(localized: "player.quality.video"),
                systemImage: "film",
                value: currentVideoDisplayValue
            )
            if availableTabs.contains(.audio) {
                Divider()
                mediaSelectionRow(
                    destination: .audio,
                    label: String(localized: "stream.audio"),
                    systemImage: "speaker.wave.2",
                    value: currentAudioDisplayValue
                )
            }
            if availableTabs.contains(.subtitles) {
                Divider()
                mediaSelectionRow(
                    destination: .subtitles,
                    label: String(localized: "stream.subtitles"),
                    systemImage: "captions.bubble",
                    value: currentSubtitlesDisplayValue
                )
            }
        }
        .cardBackground()
        #endif
    }

    @ViewBuilder
    private func mediaSelectionRow(
        destination: QualitySelectorDestination,
        label: String,
        systemImage: String,
        value: String
    ) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Label(label, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(TVSettingsRowButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - Display Value Computed Properties

    private var currentVideoDisplayValue: String {
        guard let stream = currentStream else {
            return String(localized: "stream.subtitles.none")
        }
        let format = StreamFormat.detect(from: stream)
        if format == .hls || format == .dash {
            return format == .hls ? "HLS" : "DASH"
        }
        return stream.qualityLabel
    }

    private var currentAudioDisplayValue: String {
        if isCurrentStreamMuxed {
            return String(localized: "player.quality.audioFromVideo.short")
        }
        if let audio = selectedAudioStream ?? currentAudioStream {
            return parseAudioTrackName(audio).language
        }
        return String(localized: "stream.audio.default")
    }

    private var currentSubtitlesDisplayValue: String {
        currentCaption?.displayName ?? String(localized: "stream.subtitles.off")
    }

    // MARK: - Detail Content Views

    @ViewBuilder
    var videoDetailContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !adaptiveStreams.isEmpty {
                    adaptiveSectionContent
                }
                if !videoStreams.isEmpty {
                    videoSectionContent
                }
            }
            .padding()
        }
        .background(ListBackgroundStyle.grouped.color)
        .navigationTitle(String(localized: "player.quality.video"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    var audioDetailContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                audioSectionContent
            }
            .padding()
        }
        .background(ListBackgroundStyle.grouped.color)
        .navigationTitle(String(localized: "stream.audio"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    var subtitlesDetailContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                subtitlesSectionContent
            }
            .padding()
        }
        .background(ListBackgroundStyle.grouped.color)
        .navigationTitle(String(localized: "stream.subtitles"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == .video && !adaptiveStreams.isEmpty {
            adaptiveSectionContent
        }

        switch selectedTab {
        case .video:
            if !videoStreams.isEmpty {
                videoSectionContent
            }
        case .audio:
            audioSectionContent
        case .subtitles:
            subtitlesSectionContent
        }
    }

    @ViewBuilder
    private var onlineStreamsAfterDownload: some View {
        if availableTabs.count > 1 {
            mediaSelectionRows
        } else {
            if selectedTab == .video && !adaptiveStreams.isEmpty {
                adaptiveSectionContent
            }

            switch selectedTab {
            case .video:
                if !videoStreams.isEmpty {
                    videoSectionContent
                }
            case .audio:
                audioSectionContent
            case .subtitles:
                subtitlesSectionContent
            }
        }
    }

    // MARK: - General Section

    @ViewBuilder
    var generalSectionContent: some View {
        #if os(tvOS)
        // tvOS only has the speed row here; style it to match the Settings rows.
        playbackSpeedRow
        #else
        VStack(spacing: 0) {
            playbackSpeedRow

            Divider()

            lockControlsRow
        }
        .cardBackground()
        #endif
    }

    @ViewBuilder
    private var playbackSpeedRow: some View {
        HStack {
            Label(String(localized: "player.quality.playbackSpeed"), systemImage: "gauge.with.needle")
                .font(.headline)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    if let newRate = previousRate() {
                        onRateChanged?(newRate)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.medium))
                        .frame(minWidth: 18, minHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(previousRate() == nil)

                Menu {
                    ForEach(PlaybackRate.allCases) { rate in
                        Button {
                            onRateChanged?(rate)
                        } label: {
                            if currentRate == rate {
                                Label(rate.displayText, systemImage: "checkmark")
                            } else {
                                Text(rate.displayText)
                            }
                        }
                    }
                } label: {
                    Text(currentRate.displayText)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 80)
                }
                #if os(tvOS)
                // Default menu style on tvOS renders a focusable bordered pill.
                #else
                .menuStyle(.borderlessButton)
                #endif

                Button {
                    if let newRate = nextRate() {
                        onRateChanged?(newRate)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .frame(minWidth: 18, minHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(nextRate() == nil)
            }
        }
        #if os(tvOS)
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        #else
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        #endif
    }

    #if !os(tvOS)
    @ViewBuilder
    private var lockControlsRow: some View {
        HStack {
            Label(String(localized: "player.quality.lockControls"), systemImage: "lock")
                .font(.headline)

            Spacer()

            Toggle("", isOn: Binding(
                get: { isControlsLocked },
                set: { onLockToggled?($0) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }
    #endif

    // MARK: - Download Info Section

    @ViewBuilder
    var downloadInfoSection: some View {
        if let download = currentDownload {
            // Video section
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "player.quality.video"), systemImage: "film")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    DownloadedVideoRowView(download: download, showAdvancedDetails: showAdvancedStreamDetails)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
                .cardBackground()
            }

            // Audio section (if separate audio track)
            if download.localAudioPath != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "stream.audio"), systemImage: "speaker.wave.2")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        DownloadedAudioRowView(download: download, showAdvancedDetails: showAdvancedStreamDetails)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                    }
                    .cardBackground()
                }
            }

            // Subtitles section (if downloaded)
            if download.localCaptionPath != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "stream.subtitles"), systemImage: "captions.bubble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        CaptionRowView(
                            caption: nil,
                            isSelected: currentCaption == nil,
                            isPreferred: false,
                            onTap: {
                                onCaptionSelected(nil)
                                dismiss()
                            }
                        )
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                        Divider()

                        DownloadedCaptionRowView(
                            download: download,
                            localCaptionURL: localCaptionURL,
                            currentCaption: currentCaption,
                            onCaptionSelected: onCaptionSelected,
                            onDismiss: { dismiss() }
                        )
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .cardBackground()
                }
            }
        }
    }

    @ViewBuilder
    var loadOnlineStreamsButton: some View {
        Button {
            onLoadOnlineStreams()
        } label: {
            HStack {
                if isLoadingOnlineStreams {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(String(localized: "player.quality.loadOnline"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .disabled(isLoadingOnlineStreams)
    }

    // MARK: - Adaptive Section

    @ViewBuilder
    var adaptiveSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "stream.adaptive"), systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            #if os(tvOS)
            VStack(spacing: 8) {
                ForEach(adaptiveStreams, id: \.url) { stream in
                    AdaptiveStreamRowView(
                        stream: stream,
                        isSelected: stream.url == currentStream?.url,
                        onTap: {
                            handleAdaptiveStreamTap(stream)
                        }
                    )
                }
            }
            #else
            VStack(spacing: 0) {
                ForEach(Array(adaptiveStreams.enumerated()), id: \.element.url) { index, stream in
                    if index > 0 {
                        Divider()
                    }
                    AdaptiveStreamRowView(
                        stream: stream,
                        isSelected: stream.url == currentStream?.url,
                        onTap: {
                            handleAdaptiveStreamTap(stream)
                        }
                    )
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
            }
            .cardBackground()
            #endif
        }
    }

    private func handleAdaptiveStreamTap(_ stream: Stream) {
        if isPlayingDownloadedContent {
            onSwitchToOnlineStream(stream, nil)
        } else {
            onStreamSelected(stream, nil)
        }
        dismiss()
    }

    // MARK: - Video Section

    @ViewBuilder
    var videoSectionContent: some View {
        VStack(spacing: 16) {
            // Recommended section
            if !recommendedVideoStreams.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "player.quality.recommended"), systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    #if os(tvOS)
                    VStack(spacing: 8) {
                        ForEach(recommendedVideoStreams, id: \.url) { stream in
                            videoStreamRow(stream)
                        }
                    }
                    #else
                    VStack(spacing: 0) {
                        ForEach(Array(recommendedVideoStreams.enumerated()), id: \.element.url) { index, stream in
                            if index > 0 {
                                Divider()
                            }
                            videoStreamRow(stream)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                        }
                    }
                    .cardBackground()
                    #endif
                }
            }

            // Other section (software decode)
            if showAdvancedStreamDetails && !otherVideoStreams.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "player.quality.other"), systemImage: "cpu")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    #if os(tvOS)
                    VStack(spacing: 8) {
                        ForEach(otherVideoStreams, id: \.url) { stream in
                            videoStreamRow(stream)
                        }
                    }
                    #else
                    VStack(spacing: 0) {
                        ForEach(Array(otherVideoStreams.enumerated()), id: \.element.url) { index, stream in
                            if index > 0 {
                                Divider()
                            }
                            videoStreamRow(stream)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                        }
                    }
                    .cardBackground()
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private func videoStreamRow(_ stream: Stream) -> some View {
        let isDownloadedStream: Bool = stream.url.isFileURL
        let isSelected: Bool = stream.isMuxed
            ? stream.url == currentStream?.url
            : stream.url == selectedVideoStream?.url
        let isPreferredQuality: Bool = stream.resolution == preferredQuality.maxResolution

        VideoStreamRowView(
            stream: stream,
            isSelected: isSelected,
            isPreferredQuality: isPreferredQuality,
            isDownloaded: isDownloadedStream,
            showAdvancedDetails: showAdvancedStreamDetails,
            requiresSoftwareDecode: !stream.isMuxed && requiresSoftwareDecode(stream.videoCodec),
            onTap: {
                handleVideoStreamTap(stream, isDownloaded: isDownloadedStream)
            }
        )
    }

    private func handleVideoStreamTap(_ stream: Stream, isDownloaded: Bool) {
        if isDownloaded {
            if stream.isMuxed {
                onStreamSelected(stream, nil)
                dismiss()
            } else {
                selectedVideoStream = stream
                if let audio = selectedAudioStream {
                    onStreamSelected(stream, audio)
                    dismiss()
                }
            }
        } else if isPlayingDownloadedContent {
            let audioStream: Stream? = stream.isVideoOnly ? (selectedAudioStream ?? defaultAudioStream) : nil
            onSwitchToOnlineStream(stream, audioStream)
            dismiss()
        } else {
            if stream.isMuxed {
                onStreamSelected(stream, nil)
                dismiss()
            } else {
                selectedVideoStream = stream
                if let audio = selectedAudioStream {
                    onStreamSelected(stream, audio)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Audio Section

    @ViewBuilder
    var audioSectionContent: some View {
        if isCurrentStreamMuxed {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "player.quality.audioFromVideo"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
            .cardBackground()
        } else {
            #if os(tvOS)
            VStack(spacing: 8) {
                ForEach(audioStreams, id: \.url) { stream in
                    audioStreamRow(stream)
                }
            }
            #else
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
            .cardBackground()
            #endif
        }
    }

    @ViewBuilder
    private func audioStreamRow(_ stream: Stream) -> some View {
        let isSelected: Bool = stream.url == selectedAudioStream?.url
        let isPreferred: Bool = preferredAudioLanguage.map { (stream.audioLanguage ?? "").hasPrefix($0) } ?? false
        let trackInfo: AudioTrackInfo = parseAudioTrackName(stream)

        AudioStreamRowView(
            stream: stream,
            isSelected: isSelected,
            isPreferred: isPreferred,
            showAdvancedDetails: showAdvancedStreamDetails,
            trackInfo: trackInfo,
            onTap: {
                handleAudioStreamTap(stream)
            }
        )
    }

    private func handleAudioStreamTap(_ stream: Stream) {
        selectedAudioStream = stream
        if let video = selectedVideoStream, video.isVideoOnly {
            onStreamSelected(video, stream)
            dismiss()
        }
    }

    // MARK: - Subtitles Section

    @ViewBuilder
    var subtitlesSectionContent: some View {
        #if os(tvOS)
        VStack(spacing: 8) {
            CaptionRowView(
                caption: nil,
                isSelected: currentCaption == nil,
                isPreferred: false,
                onTap: {
                    handleCaptionTap(nil)
                }
            )

            ForEach(sortedCaptions) { caption in
                CaptionRowView(
                    caption: caption,
                    isSelected: caption.id == currentCaption?.id,
                    isPreferred: isCaptionPreferred(caption),
                    onTap: {
                        handleCaptionTap(caption)
                    }
                )
            }
        }
        #else
        VStack(spacing: 0) {
            CaptionRowView(
                caption: nil,
                isSelected: currentCaption == nil,
                isPreferred: false,
                onTap: {
                    handleCaptionTap(nil)
                }
            )
            .padding(.vertical, 8)
            .padding(.horizontal, 12)

            ForEach(sortedCaptions) { caption in
                Divider()

                CaptionRowView(
                    caption: caption,
                    isSelected: caption.id == currentCaption?.id,
                    isPreferred: isCaptionPreferred(caption),
                    onTap: {
                        handleCaptionTap(caption)
                    }
                )
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
        }
        .cardBackground()
        #endif
    }

    private func isCaptionPreferred(_ caption: Caption) -> Bool {
        guard let preferred = preferredSubtitlesLanguage else { return false }
        return caption.baseLanguageCode == preferred || caption.languageCode.hasPrefix(preferred)
    }

    private func handleCaptionTap(_ caption: Caption?) {
        if caption?.id == currentCaption?.id && caption != nil {
            onCaptionSelected(nil)
        } else {
            onCaptionSelected(caption)
        }
        dismiss()
    }
}

#if os(tvOS)
/// Row button style for Settings-style navigation/selection rows on tvOS.
/// Avoids the default focus lift/scale so rows stay aligned; focus state is
/// communicated via a background tint and a thin stroke.
struct TVSettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isFocused ? Color.white.opacity(0.4) : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
#endif
