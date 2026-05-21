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

    /// Optional dismiss callback used when the view is presented inline (e.g. as
    /// the tvOS half-screen panel). When nil, falls back to `@Environment(\.dismiss)`.
    var onDismiss: (() -> Void)?

    #if os(tvOS)
    /// Bound to the first focusable row so we can programmatically pull focus
    /// into the panel on appear (the system doesn't auto-focus an inline
    /// overlay the way it does for `fullScreenCover`).
    @FocusState var inlinePanelInitialFocus: Bool

    /// Tracks pushed destinations so the Menu-button handler can pop instead
    /// of dismissing when the user has navigated into a detail screen.
    @State private var navigationPath = NavigationPath()
    #endif

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

    var allowSoftwareDecodedFormats: Bool {
        appEnvironment?.settingsManager.allowSoftwareDecodedFormats ?? false
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
        onLockToggled: ((Bool) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
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
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    @ViewBuilder
    private var rootContent: some View {
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

    var body: some View {
        #if os(tvOS)
        NavigationStack(path: $navigationPath) {
            stackRoot
        }
        .onExitCommand {
            // Pop the pushed detail view if present, otherwise dismiss the
            // whole panel. (Without this, Menu always falls through to
            // `performDismiss()` and closes the entire overlay even from a
            // detail screen.)
            if !navigationPath.isEmpty {
                navigationPath.removeLast()
            } else {
                performDismiss()
            }
        }
        #else
        NavigationStack {
            stackRoot
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 500)
        #endif
        #endif
    }

    @ViewBuilder
    private var stackRoot: some View {
        Group {
            #if os(tvOS)
            // Custom title bar matches the queue panel's style.
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Text(navigationTitle)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 80)
                .padding(.top, 32)
                .padding(.bottom, 16)

                rootContent
            }
            #else
            rootContent
            #endif
        }
        #if os(tvOS)
        // On tvOS the panel is presented inline as a half-screen overlay; it
        // supplies its own glass backdrop so the underlying video stays partly
        // visible while the menu is readable on top of the bright frame.
        .background(panelGlassBackground)
        // Disable the title-safe-area inset that NavigationStack would
        // otherwise apply on the trailing edge (because the panel sits at
        // the physical right edge of the screen).
        .ignoresSafeArea(.container, edges: .horizontal)
        #else
        .background(ListBackgroundStyle.grouped.color)
        .navigationTitle(navigationTitle)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(tvOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .cancel) {
                    performDismiss()
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
            #if os(tvOS)
            // Defer until after the slide-in transition so the focus engine
            // has finished routing focus away from the (now hidden) player
            // controls, then pull focus into the first row.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                inlinePanelInitialFocus = true
            }
            #endif
        }
    }

    #if os(tvOS)
    /// Reusable ultraThinMaterial backdrop applied to the panel root and to
    /// each pushed destination view so the glass remains continuous as the
    /// user navigates into Video / Audio / Subtitles detail screens.
    private var panelGlassBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
    }
    #endif

    func performDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
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
