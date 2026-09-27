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

    /// Pin toggle rendered before the page pills (wide layout hosts). Keeps
    /// the bar visible even when only one page is available.
    var pageBarPinAction: PanelPageBarPinAction? = nil

    /// The info page shows chapters and related as collapsible inline
    /// sections in configured order; those pages are then dropped from the
    /// page list (iPhone in every orientation, stacked iPad portrait).
    var inlineInfoSections: Bool = false

    /// Pages the host renders elsewhere (e.g. corner layout keeps info below
    /// the video), removed from this view's page list.
    var excludedPages: Set<PanelPageType> = []

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
            if !(video.relatedVideos ?? []).isEmpty { return true }
            // Keep the tab while details are still loading (spinner in the
            // page); hide only once details resolved with no related videos.
            let detailsState = playerState?.videoDetailsState ?? .idle
            return detailsState == .idle || detailsState == .loading
        case .chapters:
            return !(playerState?.chapters ?? []).isEmpty
        case .queue:
            return appEnvironment?.settingsManager.queueEnabled ?? true
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

    /// Enabled pages for this host in configured order, before runtime
    /// visibility filtering. The selection tracks this list so a page that
    /// loads late (e.g. related) still wins once its content arrives.
    private var configuredPages: [PanelPageConfiguration] {
        var pages = panelSettings.enabledPages(in: region)
        if !excludedPages.isEmpty {
            pages = pages.filter { !excludedPages.contains($0.pageType) }
        }
        guard inlineInfoSections else { return pages }
        return pages.filter { !PanelSettings.inlineSectionTypes.contains($0.pageType) }
    }

    /// Sections the info page renders inline, in configured order.
    private var inlineSections: [PanelPageConfiguration] {
        inlineInfoSections ? panelSettings.inlineSections(in: region) : []
    }

    private var visiblePages: [PanelPageConfiguration] {
        configuredPages.filter {
            Self.isRuntimeVisible($0.pageType, video: context.video, appEnvironment: appEnvironment)
        }
    }

    /// The page to render: the selection when visible, else the first page.
    private var effectivePage: PanelPageConfiguration? {
        visiblePages.first { $0.pageType == selectedPage } ?? visiblePages.first
    }

    // MARK: - Body

    var body: some View {
        let pages = visiblePages

        VStack(spacing: 0) {
            if showPageBar, pages.count >= 2 || pageBarPinAction != nil {
                // Highlight follows the rendered page (the selection when
                // visible, else the fallback); taps still set the selection.
                PanelPageBar(
                    pages: pages,
                    selectedPage: Binding(
                        get: { effectivePage?.pageType ?? selectedPage },
                        set: { selectedPage = $0 }
                    ),
                    accentColor: context.accentColor,
                    showLabels: panelSettings.effectiveShowPageBarLabels,
                    pinAction: pageBarPinAction
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
        .onChange(of: configuredPages.map(\.pageType), initial: true) { _, pageTypes in
            // Snap a selection that isn't configured for this host (e.g. the
            // host's default page was disabled or reordered away) to the
            // first configured page.
            if !pageTypes.contains(selectedPage), let first = pageTypes.first {
                selectedPage = first
            }
        }
        .onChange(of: selectedPage) { _, _ in
            // Each page owns its scroll position; reset the host's offset so
            // pills and the scroll-to-top button start from the top state.
            scrollConfig.scrollOffsetChanged?(0)
        }
        .onChange(of: context.video.id) { _, _ in
            // New video: reset to the first configured page (not the runtime
            // list — related/chapters may not have loaded yet).
            if let first = configuredPages.first?.pageType {
                selectedPage = first
            }
        }
    }

    // MARK: - Pages

    /// The host's scroll config keyed to the current video so pages jump to
    /// the top when the video changes.
    private var pageScrollConfig: PanelScrollConfig {
        var config = scrollConfig
        config.contentID = AnyHashable(context.video.id)
        return config
    }

    @ViewBuilder
    private func pageContent(_ page: PanelPageConfiguration) -> some View {
        let scrollConfig = pageScrollConfig
        switch page.pageType {
        case .info:
            InfoPanelPage(
                context: context,
                settings: page.infoSettings,
                scrollConfig: scrollConfig,
                inlineSections: inlineSections
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
        }
    }
}

#endif
