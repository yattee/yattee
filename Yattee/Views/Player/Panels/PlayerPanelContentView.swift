//
//  PlayerPanelContentView.swift
//  Yattee
//
//  Unified details panel content: page bar plus the selected page. Hosted by
//  the portrait panel, the floating panel, and (later) the corner layout
//  regions.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct PlayerPanelContentView: View {
    let panelSettings: PanelSettings

    /// Region filter for corner mode; `nil` shows pages from all regions.
    var region: PanelRegion? = nil

    @Binding var selectedPage: PanelPageType
    let context: PanelPageContext
    var scrollConfig: PanelScrollConfig = PanelScrollConfig()

    /// Extra space above the page bar (e.g. below the portrait drag handle).
    var pageBarTopPadding: CGFloat = 0

    /// Hosts that provide their own page switcher (portrait bottom-row menu)
    /// hide the top page bar.
    var showPageBar: Bool = true

    /// Prototype: the info page shows chapters and related as inline sections;
    /// those pages are then dropped from the page list.
    var inlineInfoSections: Bool = false

    private var appEnvironment: AppEnvironment? { context.appEnvironment }

    // MARK: - Page Visibility

    /// Config enables a page; runtime hides pages with nothing to show.
    static func isRuntimeVisible(
        _ pageType: PanelPageType,
        video: Video,
        appEnvironment: AppEnvironment?
    ) -> Bool {
        let playerState = appEnvironment?.playerService.state
        switch pageType {
        case .info:
            return true
        case .comments:
            return !video.isFromMediaSource
                && playerState?.commentsState != .disabled
        case .related:
            return !(video.relatedVideos ?? []).isEmpty
        case .chapters:
            return !(playerState?.chapters ?? []).isEmpty
        case .queue:
            return appEnvironment?.settingsManager.queueEnabled ?? true
        case .tracks:
            return true
        }
    }

    /// Enabled pages that currently have content, in configured order.
    static func visiblePages(
        panelSettings: PanelSettings,
        region: PanelRegion?,
        video: Video,
        appEnvironment: AppEnvironment?
    ) -> [PanelPageConfiguration] {
        panelSettings.enabledPages(in: region).filter {
            isRuntimeVisible($0.pageType, video: video, appEnvironment: appEnvironment)
        }
    }

    private var visiblePages: [PanelPageConfiguration] {
        let pages = Self.visiblePages(
            panelSettings: panelSettings,
            region: region,
            video: context.video,
            appEnvironment: appEnvironment
        )
        guard inlineInfoSections else { return pages }
        return pages.filter { $0.pageType != .chapters && $0.pageType != .related }
    }

    /// The page to render: the selection when visible, else the first page.
    private var effectivePage: PanelPageConfiguration? {
        visiblePages.first { $0.pageType == selectedPage } ?? visiblePages.first
    }

    // MARK: - Body

    var body: some View {
        let pages = visiblePages

        VStack(spacing: 0) {
            if showPageBar, pages.count >= 2 {
                PanelPageBar(
                    pages: pages,
                    selectedPage: $selectedPage,
                    accentColor: context.accentColor,
                    showLabels: panelSettings.effectiveShowPageBarLabels
                )
                .padding(.top, pageBarTopPadding)
            }

            if let page = effectivePage {
                pageContent(page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .onChange(of: selectedPage) { _, _ in
            // Each page owns its scroll position; reset the host's offset so
            // pills and the scroll-to-top button start from the top state.
            scrollConfig.scrollOffsetChanged?(0)
        }
        .onChange(of: context.video.id) { _, _ in
            // New video: fall back to the first configured page.
            if let first = visiblePages.first?.pageType {
                selectedPage = first
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageContent(_ page: PanelPageConfiguration) -> some View {
        switch page.pageType {
        case .info:
            InfoPanelPage(
                context: context,
                settings: page.infoSettings,
                scrollConfig: scrollConfig,
                inlineSections: inlineInfoSections
            )
            .id(PanelPageType.info)
        case .comments:
            CommentsPanelPage(context: context, settings: page.commentsSettings, scrollConfig: scrollConfig)
                .id(PanelPageType.comments)
        case .related:
            RelatedPanelPage(context: context, settings: page.relatedSettings, scrollConfig: scrollConfig)
                .id(PanelPageType.related)
        case .chapters:
            ChaptersPanelPage(context: context, settings: page.chaptersSettings, scrollConfig: scrollConfig)
                .id(PanelPageType.chapters)
        case .queue:
            QueuePanelPage(context: context, settings: page.queueSettings, bottomInset: scrollConfig.bottomInset)
                .id(PanelPageType.queue)
        case .tracks:
            TracksPanelPage(context: context, settings: page.tracksSettings, bottomInset: scrollConfig.bottomInset)
                .id(PanelPageType.tracks)
        }
    }
}

#endif
