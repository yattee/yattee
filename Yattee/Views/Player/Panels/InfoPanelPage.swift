//
//  InfoPanelPage.swift
//  Yattee
//
//  Details panel page with title, stats, channel row, and description.
//  Consolidates the previously duplicated video info bodies.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct InfoPanelPage: View {
    let context: PanelPageContext
    var settings: InfoPageSettings = InfoPageSettings()
    var scrollConfig: PanelScrollConfig = PanelScrollConfig()

    /// Prototype: collapse the description to a few lines and show chapters
    /// and related videos as inline sections below it.
    var inlineSections: Bool = false

    /// Collapse only while something actually renders below the description —
    /// with no chapters and no related videos the description stays expanded.
    /// While details are still loading, keep it collapsed to avoid an
    /// expand-then-clamp flash when sections arrive.
    private var usesCollapsedDescription: Bool {
        inlineSections
            && (!chapters.isEmpty || !relatedVideos.isEmpty || videoDetailsState == .loading)
    }

    @State private var showFormattedDate = false
    @State private var showOriginalTitle = false
    @State private var isDescriptionExpanded = false

    private var appEnvironment: AppEnvironment? { context.appEnvironment }
    private var video: Video { context.video }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }
    private var videoDetailsState: VideoDetailsLoadState { playerState?.videoDetailsState ?? .idle }

    /// Returns the first enabled Yattee Server instance URL, if any.
    private var yatteeServerURL: URL? {
        appEnvironment?.instancesManager.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    /// Returns the DeArrow title if available and enabled.
    private var deArrowTitle: String? {
        appEnvironment?.deArrowBrandingProvider.title(for: video)
    }

    /// Returns the display title based on toggle state.
    private var displayTitle: String {
        if let deArrowTitle {
            return showOriginalTitle ? video.title : deArrowTitle
        }
        return video.title
    }

    var body: some View {
        PanelPageScrollView(config: scrollConfig) {
            videoInfo

            if settings.effectiveShowDescription {
                Divider()
                    .padding(.horizontal)

                descriptionContent
                    .padding(.vertical)
            }

            if inlineSections {
                chaptersSection
                relatedSection
            }
        }
        .onChange(of: video.id) { _, _ in
            showOriginalTitle = false
            isDescriptionExpanded = false
        }
        .task(id: context.video.id) {
            if inlineSections {
                await preloadChapterSheets()
            }
        }
    }

    // MARK: - Video Info

    private var videoInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title - full width (shows DeArrow title if available, tap toggles)
            Text(displayTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(3)
                .onTapGesture {
                    if deArrowTitle != nil {
                        showOriginalTitle.toggle()
                    }
                }

            // Stats row - only show for non-media-source videos
            if settings.effectiveShowStatsRow, !video.isFromMediaSource {
                VideoStatsRow(
                    playerState: playerState,
                    showFormattedDate: $showFormattedDate,
                    returnYouTubeDislikeEnabled: appEnvironment?.settingsManager.returnYouTubeDislikeEnabled ?? false
                )
            }

            // Channel row with context menu
            if settings.effectiveShowChannelRow {
                VideoChannelRow(
                    author: video.author,
                    source: video.id.source,
                    yatteeServerURL: yatteeServerURL,
                    onChannelTap: context.onChannelTap,
                    video: video,
                    accentColor: context.accentColor,
                    showSubscriberCount: !video.isFromMediaSource,
                    isLoadingDetails: videoDetailsState == .loading
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Description

    private var descriptionContent: some View {
        let description = video.description ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            if !description.isEmpty {
                if usesCollapsedDescription {
                    collapsibleDescription(description)
                } else {
                    Text(DescriptionText.attributed(description, linkColor: context.accentColor))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .tint(context.accentColor)
                        .padding(.horizontal)
                        .handleTimestampLinks(using: playerService)
                }
            } else if videoDetailsState == .loading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else {
                Text(String(localized: "player.noDescription"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Collapsible Description (prototype)

    private var panelBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Collapsed: 3 lines with an inline "more" cutting into the end of the
    /// last line; the whole area is tappable to expand. Expanded: full text
    /// with working links and a "less" button below.
    @ViewBuilder
    private func collapsibleDescription(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DescriptionText.attributed(description, linkColor: context.accentColor))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .tint(context.accentColor)
                .lineLimit(isDescriptionExpanded ? nil : 3)
                .handleTimestampLinks(using: playerService)
                // Collapsed: let the container tap win over link taps
                .allowsHitTesting(isDescriptionExpanded)
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
                    if !isDescriptionExpanded {
                        Text(String(localized: "common.more"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(context.accentColor)
                            .padding(.leading, 32)
                            .background(
                                LinearGradient(
                                    stops: [
                                        .init(color: panelBackground.opacity(0), location: 0),
                                        .init(color: panelBackground, location: 0.4),
                                        .init(color: panelBackground, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }

            if isDescriptionExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDescriptionExpanded = false
                    }
                } label: {
                    Text(String(localized: "common.less"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(context.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDescriptionExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDescriptionExpanded = true
                }
            }
        }
    }

    // MARK: - Inline Sections (prototype)

    private var chapters: [VideoChapter] { playerState?.chapters ?? [] }
    private var storyboard: Storyboard? { playerState?.preferredStoryboard }
    private var relatedVideos: [Video] { video.relatedVideos ?? [] }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chaptersSection: some View {
        if !chapters.isEmpty {
            Divider()
                .padding(.horizontal)
                .padding(.bottom, 8)

            sectionHeader(String(localized: "player.chapters"))

            LazyVStack(spacing: 0) {
                ForEach(chapters) { chapter in
                    ChapterRow(
                        chapter: chapter,
                        isActive: isChapterActive(chapter),
                        storyboard: storyboard,
                        showThumbnail: true,
                        onTap: {
                            Task {
                                await playerService?.seek(to: chapter.startTime)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        if !relatedVideos.isEmpty {
            Divider()
                .padding(.horizontal)
                .padding(.vertical, 8)

            sectionHeader(String(localized: "videoInfo.section.relatedVideos"))

            LazyVStack(spacing: 12) {
                ForEach(Array(relatedVideos.enumerated()), id: \.element.id) { index, relatedVideo in
                    VideoRowView(
                        video: relatedVideo,
                        style: .regular,
                        showThumbnail: true
                    )
                    .tappableVideo(
                        relatedVideo,
                        queueSource: .manual,
                        sourceLabel: String(localized: "videoInfo.section.relatedVideos"),
                        videoList: relatedVideos,
                        videoIndex: index,
                        loadMoreVideos: nil
                    )

                    if index < relatedVideos.count - 1 {
                        Divider()
                            .padding(.leading, VideoRowStyle.regular.thumbnailWidth + 12)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func isChapterActive(_ chapter: VideoChapter) -> Bool {
        // Observes only chapter transitions, not per-tick currentTime updates.
        playerState?.activeChapterID == chapter.id
    }

    private func preloadChapterSheets() async {
        guard let storyboard else { return }
        let service = StoryboardService.shared
        for chapter in chapters {
            await service.loadSheet(for: chapter.startTime, from: storyboard)
        }
    }
}

#endif
