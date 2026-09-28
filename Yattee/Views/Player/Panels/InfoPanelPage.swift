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

    /// Enabled pages rendered as collapsible inline sections below the
    /// description, in configured order (see `PanelSettings.inlineSections`).
    /// Empty means the page shows the video info and description only.
    var inlineSections: [PanelPageConfiguration] = []

    /// Collapse only while something actually renders below the description —
    /// with no section content the description stays expanded. While details
    /// are still loading, keep it collapsed to avoid an expand-then-clamp
    /// flash when sections arrive.
    private var usesCollapsedDescription: Bool {
        guard !inlineSections.isEmpty else { return false }
        return inlineSections.contains { sectionHasContent($0.pageType) }
            || videoDetailsState == .loading
    }

    private func sectionHasContent(_ pageType: PanelPageType) -> Bool {
        switch pageType {
        case .chapters:
            return !chapters.isEmpty
        case .related:
            return !relatedVideos.isEmpty
        default:
            return false
        }
    }

    private var chaptersSectionSettings: ChaptersPageSettings? {
        inlineSections.first { $0.pageType == .chapters }?.chaptersSettings
    }

    private var relatedSectionSettings: RelatedPageSettings? {
        inlineSections.first { $0.pageType == .related }?.relatedSettings
    }

    /// Seeds the description and section collapse state from the configured
    /// defaults.
    private func resetSectionCollapseState() {
        isDescriptionExpanded = settings.effectiveDescriptionExpandedByDefault
        isChaptersCollapsed = !(chaptersSectionSettings?.effectiveExpandedByDefault ?? true)
        isRelatedCollapsed = !(relatedSectionSettings?.effectiveExpandedByDefault ?? true)
    }

    @State private var showFormattedDate = false
    @State private var showOriginalTitle = false
    @State private var isDescriptionExpanded = false
    @State private var moreLabelSize: CGSize = .zero
    @State private var isChaptersCollapsed = false
    @State private var isRelatedCollapsed = false

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
        PanelPageScrollView(config: scrollConfig) { proxy in
            videoInfo

            if showsDescriptionSection {
                Divider()
                    .panelHorizontalPadding()

                descriptionContent
                    .padding(.vertical)
            }

            ForEach(inlineSections) { section in
                // One container per section so the scroll anchor is a single
                // view (the divider + header + rows), not each child.
                VStack(alignment: .leading, spacing: 0) {
                    inlineSection(section, scrollProxy: proxy)
                }
                .id(Self.sectionScrollID(section.pageType))
            }
        }
        .onChange(of: video.id) { _, _ in
            showOriginalTitle = false
            resetSectionCollapseState()
        }
        .onAppear {
            resetSectionCollapseState()
        }
        .task(id: context.video.id) {
            if chaptersSectionSettings?.effectiveShowThumbnails == true {
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
        .panelHorizontalPadding()
        .padding(.vertical, 8)
    }

    // MARK: - Description

    private var description: String { video.description ?? "" }

    /// Nothing renders below the video info when there is no description and
    /// nothing is loading — no placeholder, no divider (direct media links).
    private var showsDescriptionSection: Bool {
        settings.effectiveShowDescription
            && (!description.isEmpty || videoDetailsState == .loading)
    }

    private var descriptionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !description.isEmpty {
                if usesCollapsedDescription {
                    collapsibleDescription(description)
                } else {
                    Text(DescriptionText.attributed(description, linkColor: context.accentColor))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .tint(context.accentColor)
                        .panelHorizontalPadding()
                        .handleTimestampLinks(using: playerService)
                }
            } else if videoDetailsState == .loading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            }
        }
    }

    // MARK: - Collapsible Description

    /// Width of the fade between the last line's text and the "more" label.
    private static let moreFadeWidth: CGFloat = 40

    /// Alpha mask for the collapsed description: fully visible except the
    /// end of the last line, which fades out under the "more" label. Masking
    /// the text (instead of painting a background-colored gradient over it)
    /// works on any host background, including the floating panel's
    /// translucent material.
    private var collapsedDescriptionMask: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.black)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(.black)

                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.moreFadeWidth)

                Color.clear
                    .frame(width: moreLabelSize.width)
            }
            .frame(height: moreLabelSize.height)
        }
    }

    /// Collapsed: the configured number of lines with an inline "more"
    /// cutting into the end of the last line; the whole area is tappable to
    /// expand. Expanded: full text
    /// with working links and a "less" button below.
    @ViewBuilder
    private func collapsibleDescription(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DescriptionText.attributed(description, linkColor: context.accentColor))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .tint(context.accentColor)
                .lineLimit(isDescriptionExpanded ? nil : settings.effectiveDescriptionCollapsedLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .handleTimestampLinks(using: playerService)
                // Collapsed: let the container tap win over link taps
                .allowsHitTesting(isDescriptionExpanded)
                .mask {
                    if isDescriptionExpanded {
                        Rectangle()
                    } else {
                        collapsedDescriptionMask
                    }
                }
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
                    if !isDescriptionExpanded {
                        Text(String(localized: "common.more"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(context.accentColor)
                            .onGeometryChange(for: CGSize.self) { proxy in
                                proxy.size
                            } action: { size in
                                moreLabelSize = size
                            }
                    }
                }

            if isDescriptionExpanded {
                Button {
                    isDescriptionExpanded = false
                } label: {
                    Text(String(localized: "common.less"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(context.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .panelHorizontalPadding()
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDescriptionExpanded {
                isDescriptionExpanded = true
            }
        }
    }

    // MARK: - Inline Sections

    private var chapters: [VideoChapter] { playerState?.chapters ?? [] }
    private var storyboard: Storyboard? { playerState?.preferredStoryboard }
    private var relatedVideos: [Video] { video.relatedVideos ?? [] }

    /// Scroll anchor for a section: its Divider + header, so scrolling to it
    /// puts the tapped header at the top of the panel.
    private static func sectionScrollID(_ pageType: PanelPageType) -> String {
        "inlineSection-\(pageType.rawValue)"
    }

    @ViewBuilder
    private func inlineSection(_ section: PanelPageConfiguration, scrollProxy: ScrollViewProxy) -> some View {
        switch section.pageType {
        case .chapters:
            chaptersSection(settings: section.chaptersSettings, scrollProxy: scrollProxy)
        case .related:
            relatedSection(settings: section.relatedSettings, scrollProxy: scrollProxy)
        default:
            EmptyView()
        }
    }

    /// Section header that toggles the section's collapsed state on tap.
    /// Expanding also scrolls the section to the top of the panel so the
    /// revealed content starts right under the tapped header, instead of
    /// growing below the fold.
    @ViewBuilder
    private func sectionHeader(
        _ title: String,
        isCollapsed: Binding<Bool>,
        scrollProxy: ScrollViewProxy,
        scrollID: String
    ) -> some View {
        Button {
            let expanding = isCollapsed.wrappedValue
            withAnimation(.easeInOut(duration: 0.25)) {
                isCollapsed.wrappedValue.toggle()
            }
            if expanding {
                // Next runloop: the expanded content must be laid out before
                // the scroll view can reach the section's top.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo(scrollID, anchor: .top)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed.wrappedValue ? -90 : 0))

                Spacer(minLength: 0)
            }
            .panelHorizontalPadding()
            .padding(.top, 4)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chaptersSection(settings: ChaptersPageSettings, scrollProxy: ScrollViewProxy) -> some View {
        if !chapters.isEmpty {
            Divider()
                .panelHorizontalPadding()
                .padding(.bottom, 8)

            sectionHeader(
                String(localized: "player.chapters"),
                isCollapsed: $isChaptersCollapsed,
                scrollProxy: scrollProxy,
                scrollID: Self.sectionScrollID(.chapters)
            )

            if !isChaptersCollapsed {
                LazyVStack(spacing: 0) {
                    ForEach(chapters) { chapter in
                        ChapterRow(
                            chapter: chapter,
                            isActive: isChapterActive(chapter),
                            storyboard: storyboard,
                            showThumbnail: settings.effectiveShowThumbnails,
                            onTap: {
                                Task {
                                    await playerService?.seek(to: chapter.startTime)
                                }
                            }
                        )
                    }
                }
                .panelHorizontalPadding()
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func relatedSection(settings: RelatedPageSettings, scrollProxy: ScrollViewProxy) -> some View {
        if !relatedVideos.isEmpty {
            Divider()
                .panelHorizontalPadding()
                .padding(.bottom, 8)

            sectionHeader(
                String(localized: "videoInfo.section.relatedVideos"),
                isCollapsed: $isRelatedCollapsed,
                scrollProxy: scrollProxy,
                scrollID: Self.sectionScrollID(.related)
            )

            if !isRelatedCollapsed {
                LazyVStack(spacing: 12) {
                    ForEach(Array(relatedVideos.enumerated()), id: \.element.id) { index, relatedVideo in
                        VideoRowView(
                            video: relatedVideo,
                            style: .regular,
                            disableInternalTapHandling: true,
                            showThumbnail: settings.effectiveShowThumbnails
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
                .panelHorizontalPadding()
                .padding(.bottom, 8)
            }
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
