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

    @State private var showFormattedDate = false
    @State private var showOriginalTitle = false

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
        }
        .onChange(of: video.id) { _, _ in
            showOriginalTitle = false
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
                Text(DescriptionText.attributed(description, linkColor: context.accentColor))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .tint(context.accentColor)
                    .padding(.horizontal)
                    .handleTimestampLinks(using: playerService)
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
}

#endif
