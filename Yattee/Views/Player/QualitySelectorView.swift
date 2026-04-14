//
//  QualitySelectorView.swift
//  Yattee
//
//  Sheet for selecting video quality, audio track, and subtitles.
//

import SwiftUI

struct QualitySelectorView: View {
    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    // MARK: - Properties

    let streams: [Stream]
    let captions: [Caption]
    let currentStream: Stream?
    let currentAudioStream: Stream?
    let currentCaption: Caption?
    let isLoading: Bool
    let currentDownload: Download?
    let isLoadingOnlineStreams: Bool
    let localCaptionURL: URL?
    let onStreamSelected: (Stream, Stream?) -> Void
    let onCaptionSelected: (Caption?) -> Void
    let onLoadOnlineStreams: () -> Void
    let onSwitchToOnlineStream: (Stream, Stream?) -> Void

    /// Current playback rate
    var currentRate: PlaybackRate = .x1
    /// Callback when playback rate changes
    var onRateChanged: ((PlaybackRate) -> Void)?

    /// Whether controls are locked
    var isControlsLocked: Bool = false
    /// Callback when lock state changes
    var onLockToggled: ((Bool) -> Void)?

    /// Initial tab to show when view appears
    var initialTab: QualitySelectorTab = .video
    /// Whether to show the segmented tab picker (false for focused single-tab mode)
    var showTabPicker: Bool = true

    // MARK: - State
    @State var selectedTab: QualitySelectorTab = .video
    @State var selectedVideoStream: Stream?
    @State var selectedAudioStream: Stream?

    // MARK: - Settings Access

    /// The preferred audio language from settings
    var preferredAudioLanguage: String? {
        appEnvironment?.settingsManager.preferredAudioLanguage
    }

    /// The preferred subtitles language from settings
    var preferredSubtitlesLanguage: String? {
        appEnvironment?.settingsManager.preferredSubtitlesLanguage
    }

    /// The preferred video quality from settings
    var preferredQuality: VideoQuality {
        appEnvironment?.settingsManager.preferredQuality ?? .auto
    }

    /// Whether to show advanced stream details (codec, bitrate, size)
    var showAdvancedStreamDetails: Bool {
        appEnvironment?.settingsManager.showAdvancedStreamDetails ?? false
    }

    // MARK: - Computed Properties

    /// Available tabs based on streams
    var availableTabs: [QualitySelectorTab] {
        var tabs: [QualitySelectorTab] = [.video]
        if hasVideoOnlyStreams && !audioStreams.isEmpty {
            tabs.append(.audio)
        }
        if !captions.isEmpty {
            tabs.append(.subtitles)
        }
        return tabs
    }

    /// Navigation title based on mode
    var navigationTitle: String {
        if showTabPicker {
            return String(localized: "player.quality.settings")
        } else {
            switch initialTab {
            case .video:
                return String(localized: "player.quality.video")
            case .audio:
                return String(localized: "stream.audio")
            case .subtitles:
                return String(localized: "stream.subtitles")
            }
        }
    }

    /// Whether we're playing downloaded content
    var isPlayingDownloadedContent: Bool {
        currentDownload != nil
    }

    /// Whether streams are empty (not loading, but no streams available)
    var hasNoStreams: Bool {
        if !showTabPicker && initialTab == .subtitles {
            return !isLoading && captions.isEmpty && !isPlayingDownloadedContent
        }
        return !isLoading && streams.isEmpty && !isPlayingDownloadedContent
    }

    /// Whether online streams have been loaded
    var hasOnlineStreams: Bool {
        streams.contains { !$0.url.isFileURL }
    }

    /// Whether the current or selected video stream is muxed
    var isCurrentStreamMuxed: Bool {
        if let selected = selectedVideoStream {
            return selected.isMuxed
        }
        return currentStream?.isMuxed ?? false
    }

    // MARK: - Initialization

    init(
        streams: [Stream],
        captions: [Caption] = [],
        currentStream: Stream?,
        currentAudioStream: Stream? = nil,
        currentCaption: Caption? = nil,
        isLoading: Bool = false,
        currentDownload: Download? = nil,
        isLoadingOnlineStreams: Bool = false,
        localCaptionURL: URL? = nil,
        currentRate: PlaybackRate = .x1,
        isControlsLocked: Bool = false,
        initialTab: QualitySelectorTab = .video,
        showTabPicker: Bool = true,
        onStreamSelected: @escaping (Stream, Stream?) -> Void,
        onCaptionSelected: @escaping (Caption?) -> Void = { _ in },
        onLoadOnlineStreams: @escaping () -> Void = {},
        onSwitchToOnlineStream: @escaping (Stream, Stream?) -> Void = { _, _ in },
        onRateChanged: ((PlaybackRate) -> Void)? = nil,
        onLockToggled: ((Bool) -> Void)? = nil
    ) {
        self.streams = streams
        self.captions = captions
        self.currentStream = currentStream
        self.currentAudioStream = currentAudioStream
        self.currentCaption = currentCaption
        self.isLoading = isLoading
        self.currentDownload = currentDownload
        self.isLoadingOnlineStreams = isLoadingOnlineStreams
        self.localCaptionURL = localCaptionURL
        self.initialTab = initialTab
        self.showTabPicker = showTabPicker
        self.currentRate = currentRate
        self.isControlsLocked = isControlsLocked
        self.onStreamSelected = onStreamSelected
        self.onCaptionSelected = onCaptionSelected
        self.onLoadOnlineStreams = onLoadOnlineStreams
        self.onSwitchToOnlineStream = onSwitchToOnlineStream
        self.onRateChanged = onRateChanged
        self.onLockToggled = onLockToggled
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingContent
                } else if isPlayingDownloadedContent {
                    downloadedContent
                } else if hasNoStreams {
                    emptyContent
                } else {
                    streamsContent
                }
            }
            .background(ListBackgroundStyle.grouped.color)
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(tvOS)
            // Menu at the root dismisses; pushed detail views use NavigationStack's
            // default pop-on-Menu behavior and won't hit this handler.
            .onExitCommand { dismiss() }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label(String(localized: "common.close"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            #endif
            .navigationDestination(for: QualitySelectorDestination.self) { destination in
                switch destination {
                case .video:
                    videoDetailContent
                case .audio:
                    audioDetailContent
                case .subtitles:
                    subtitlesDetailContent
                }
            }
            .onAppear {
                selectedVideoStream = currentStream
                selectedAudioStream = currentAudioStream ?? defaultAudioStream
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview

#Preview {
    QualitySelectorView(
        streams: [.preview, .videoOnlyPreview, .audioPreview],
        captions: [.preview, .autoGeneratedPreview],
        currentStream: .preview,
        onStreamSelected: { _, _ in }
    )
}

#Preview("Loading") {
    QualitySelectorView(
        streams: [],
        currentStream: nil,
        isLoading: true,
        onStreamSelected: { _, _ in }
    )
}

#Preview("Empty") {
    QualitySelectorView(
        streams: [],
        currentStream: nil,
        onStreamSelected: { _, _ in }
    )
}
