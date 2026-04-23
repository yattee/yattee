//
//  VideoCardView.swift
//  Yattee
//
//  Reusable video card component with thumbnail, progress, and metadata.
//

import SwiftUI

/// A video card for grid/horizontal scroll layouts.
///
/// Automatically handles DeArrow integration for titles and thumbnails.
/// Download status is automatically shown from the download manager.
/// On iOS/macOS, supports configurable tap zones for thumbnail and text area.
struct VideoCardView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.videoQueueContext) private var videoQueueContext

    let video: Video
    var watchProgress: Double? = nil
    /// Use compact styling for dense grids (3+ columns).
    var isCompact: Bool = false
    /// Custom metadata text to show instead of views/date (e.g., progress percentage).
    var customMetadata: String? = nil
    /// Custom duration text to show on thumbnail (e.g., remaining time). If nil, uses video.formattedDuration.
    var customDuration: String? = nil

    // Platform-specific fonts
    #if os(tvOS)
    private var titleFont: Font { isCompact ? .subheadline : .body }
    private var authorFont: Font { isCompact ? .caption : .subheadline }
    private var metadataFont: Font { isCompact ? .caption : .caption }
    #else
    private var titleFont: Font { .subheadline }
    private var authorFont: Font { isCompact ? .caption2 : .caption }
    private var metadataFont: Font { isCompact ? .caption2 : .caption }
    #endif
    
    #if !os(tvOS)
    private var thumbnailTapAction: VideoTapAction {
        appEnvironment?.settingsManager.thumbnailTapAction ?? .playVideo
    }
    
    private var textAreaTapAction: VideoTapAction {
        appEnvironment?.settingsManager.textAreaTapAction ?? .openInfo
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            // Thumbnail with overlays
            thumbnailView

            // Metadata
            metadataView
        }
        .contentShape(Rectangle())
        .zoomTransitionSource(id: video.id)
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        DeArrowVideoThumbnail(
            video: video,
            watchProgress: watchProgress,
            duration: customDuration ?? video.formattedDuration
        )
        #if !os(tvOS)
        .contentShape(Rectangle())
        .if(thumbnailTapAction != .playVideo) { view in
            view.highPriorityGesture(
                TapGesture().onEnded {
                    handleTapAction(thumbnailTapAction)
                }
            )
        }
        #endif
    }
    
    @ViewBuilder
    private var metadataView: some View {
        VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
            Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                .font(titleFont)
                .fontWeight(.medium)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)

            Text(video.author.name)
                .lineLimit(1)
                .font(authorFont)
                .foregroundStyle(.secondary)

            if let custom = customMetadata {
                Text(custom)
                    .font(metadataFont)
                    .foregroundStyle(.tertiary)
            } else if video.viewCount != nil || video.formattedPublishedDate != nil {
                if isCompact {
                    CompactVideoMetadataLine(viewCount: video.formattedViewCount, publishedText: video.formattedPublishedDate)
                        .font(metadataFont)
                        .foregroundStyle(.tertiary)
                } else {
                    VideoMetadataLine(viewCount: video.formattedViewCount, publishedText: video.formattedPublishedDate)
                        .font(metadataFont)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(tvOS)
        .contentShape(Rectangle())
        .if(textAreaTapAction != .playVideo) { view in
            view.highPriorityGesture(
                TapGesture().onEnded {
                    handleTapAction(textAreaTapAction)
                }
            )
        }
        #endif
    }
    
    #if !os(tvOS)
    private func handleTapAction(_ action: VideoTapAction) {
        guard let env = appEnvironment else { return }
        
        switch action {
        case .playVideo:
            // This should not be called since we only add gesture for non-playVideo actions
            // The .tappableVideo() modifier will handle playVideo actions
            break
        case .openInfo:
            env.navigationCoordinator.navigate(to: .video(.loaded(video), queueContext: videoQueueContext))
        case .none:
            break
        }
    }
    #endif
}

// MARK: - Preview

#Preview("Card") {
    VideoCardView(
        video: .preview,
        watchProgress: 0.4
    )
    .frame(width: 280)
    .padding()
}

#Preview("Card Compact") {
    VideoCardView(
        video: .preview,
        watchProgress: 0.4,
        isCompact: true
    )
    .frame(width: 110)
    .padding()
}
